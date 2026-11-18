# IPTV Manager / UA EPG coverage audit v1.3 (read-only, permanent component)
# Requires PowerShell 7+; supports -SelfTest. No production writes or Windows task changes.
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$ManagerRoot = 'C:\IPTV-Manager',
    [string]$CandidateCsv = (Join-Path $PSScriptRoot 'UA_EPG_CANDIDATES_READONLY_2026-11-18.csv')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Convert-XmlTvUtc {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    if ($Value -notmatch '^([0-9]{14})\s+([+-])([0-9]{2})([0-9]{2})$') { return $null }
    $datePart = $Matches[1]; $offset = "$($Matches[2])$($Matches[3]):$($Matches[4])"
    try {
        $dt = [datetime]::ParseExact($datePart, 'yyyyMMddHHmmss',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None)
        $span = [timespan]::Parse($offset.TrimStart('+','-'))
        if ($offset.StartsWith('-')) { $span = $span.Negate() }
        return [datetimeoffset]::new($dt, $span).ToUniversalTime()
    } catch { return $null }
}

function Test-UsefulTitle {
    param([string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return $false }
    $v = $Title.Trim().ToLowerInvariant()
    if ($v -match '^(no\s*(data|information|epg)|not\s*available|n/a|unknown|tba|program(me)?\s*(unavailable|not\s*available)|немає\s*(інформації|програми)|нет\s*(данных|информации)|без\s*програми|програма\s*відсутня)$') { return $false }
    return $true
}

function Read-XmlTvFacts {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$Wanted,
        [Parameter(Mandatory)][datetimeoffset]$Now
    )
    $channels = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $stats = [System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 90000000
    $settings.MaxCharactersFromEntities = 0
    $settings.IgnoreComments = $true
    $settings.IgnoreWhitespace = $true
    $reader = $null
    try {
        $reader = [System.Xml.XmlReader]::Create($Path, $settings)
        # ReadOuterXml / Skip already advances to the following sibling. Do not
        # call Read() unconditionally or every second programme may be lost.
        while (-not $reader.EOF) {
            if ($reader.NodeType -ne [System.Xml.XmlNodeType]::Element) {
                if (-not $reader.Read()) { break }
                continue
            }
            if ($reader.Name -eq 'channel') {
                $id = $reader.GetAttribute('id')
                if (-not [string]::IsNullOrWhiteSpace($id)) { [void]$channels.Add($id) }
                $reader.Skip()
                continue
            }
            if ($reader.Name -ne 'programme') {
                if (-not $reader.Read()) { break }
                continue
            }
            $id = $reader.GetAttribute('channel')
            if ([string]::IsNullOrWhiteSpace($id) -or -not $Wanted.Contains($id)) { $reader.Skip(); continue }
            $start = Convert-XmlTvUtc ($reader.GetAttribute('start'))
            $stop = Convert-XmlTvUtc ($reader.GetAttribute('stop'))
            if ($null -eq $start -or $null -eq $stop -or $stop -le $start) { $reader.Skip(); continue }
            if ($stop -le $Now -or $start -ge $Now.AddDays(7)) { $reader.Skip(); continue }
            $outer = $reader.ReadOuterXml()
            if (-not $outer) { continue }
            $fragment = [System.Xml.XmlDocument]::new()
            $fragment.XmlResolver = $null
            $fragment.LoadXml($outer)
            $titleNode = $fragment.SelectSingleNode('/programme/title')
            if ($null -eq $titleNode -or -not (Test-UsefulTitle $titleNode.InnerText)) { continue }
            if (-not $stats.ContainsKey($id)) {
                $stats[$id] = [pscustomobject]@{ Now = 0; Next24 = 0; Next7 = 0; Titles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal) }
            }
            $s = $stats[$id]
            $s.Next7++
            if ($start -le $Now -and $stop -gt $Now) { $s.Now++ }
            if ($start -lt $Now.AddHours(24) -and $stop -gt $Now) { $s.Next24++ }
            [void]$s.Titles.Add($titleNode.InnerText.Trim())
        }
    } finally { if ($null -ne $reader) { $reader.Dispose() } }
    return [pscustomobject]@{ Channels = $channels; Facts = $stats }
}

function Get-BoundedGuide {
    param([string]$Url, [string]$CompressedPath, [string]$XmlPath)
    # Only predeclared HTTPS EPG guide URLs; no arbitrary URL input.
    $allowed = @('https://epgshare01.online/epgshare01/epg_ripper_UA1.xml.gz',
                 'https://free-epg.de/api/epg/ua.xml.gz')
    if ($Url -cnotin $allowed) { throw 'EPG SOURCE NOT ALLOWLISTED' }
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [timespan]::FromSeconds(75)
    $response = $null
    $networkStream = $null
    $compressed = $null
    try {
        $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) { throw "HTTP $([int]$response.StatusCode)" }
        if ($null -ne $response.Content.Headers.ContentLength -and $response.Content.Headers.ContentLength -gt 25000000) { throw 'COMPRESSED SIZE LIMIT' }
        $networkStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $compressed = [System.IO.File]::Create($CompressedPath)
        $buffer = [byte[]]::new(65536); $bytes = 0L
        while (($n = $networkStream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $bytes += $n
            if ($bytes -gt 25000000) { throw 'COMPRESSED SIZE LIMIT' }
            $compressed.Write($buffer,0,$n)
        }
    } finally {
        if ($null -ne $compressed) { $compressed.Dispose() }
        if ($null -ne $networkStream) { $networkStream.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        $client.Dispose(); $handler.Dispose()
    }
    $src = $null; $gzip = $null; $dst = $null
    try {
        $src = [IO.File]::OpenRead($CompressedPath)
        $gzip = [IO.Compression.GZipStream]::new($src,[IO.Compression.CompressionMode]::Decompress)
        $dst = [IO.File]::Create($XmlPath)
        $buffer = [byte[]]::new(65536); $bytes = 0L
        while (($n = $gzip.Read($buffer,0,$buffer.Length)) -gt 0) {
            $bytes += $n
            if ($bytes -gt 90000000) { throw 'UNCOMPRESSED SIZE LIMIT' }
            $dst.Write($buffer,0,$n)
        }
    } finally {
        if ($null -ne $dst) { $dst.Dispose() }
        if ($null -ne $gzip) { $gzip.Dispose() }
        if ($null -ne $src) { $src.Dispose() }
    }
}

function Invoke-InternalSelfTest {
    $d = Join-Path ([IO.Path]::GetTempPath()) ('ua-epg-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $d | Out-Null
    try {
        $now = [datetimeoffset]::UtcNow
        $start = $now.AddMinutes(-5).ToString('yyyyMMddHHmmss +0000')
        $stop = $now.AddMinutes(55).ToString('yyyyMMddHHmmss +0000')
        $f = Join-Path $d 'ok.xml'
        [IO.File]::WriteAllText($f, "<?xml version='1.0'?><tv><channel id='good'/><programme start='$start' stop='$stop' channel='good'><title>Новини</title></programme><programme start='$start' stop='$stop' channel='good'><title>No Data</title></programme></tv>")
        $wanted = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        [void]$wanted.Add('good')
        $got = Read-XmlTvFacts -Path $f -Wanted $wanted -Now $now
        if (-not $got.Channels.Contains('good') -or $got.Facts['good'].Next7 -ne 1 -or $got.Facts['good'].Now -ne 1) { throw 'SELFTEST PROGRAMME' }
        if ((Convert-XmlTvUtc '20261118120000 +0200').ToString('yyyy-MM-ddTHH:mm:ssZ') -ne '2026-11-18T10:00:00Z') { throw 'SELFTEST UTC OFFSET' }
        [IO.File]::WriteAllText($f, '<!DOCTYPE tv [<!ENTITY x SYSTEM "file:///etc/passwd">]><tv/>')
        $blocked = $false
        try { [void](Read-XmlTvFacts -Path $f -Wanted $wanted -Now $now) } catch { $blocked = $true }
        if (-not $blocked) { throw 'SELFTEST DTD PROHIBITION' }
        Write-Host 'UA EPG COVERAGE v1.3 SELFTEST PASS: XMLTV UTC/now, placeholder filter, DTD rejection'
    } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-InternalSelfTest
if ($SelfTest) { return }

$m3uPath = Join-Path $ManagerRoot 'public\playlists\IPTV-UA-NEW.m3u'
$epgPath = Join-Path $ManagerRoot 'public\playlists\IPTV-UA-EPG-NEW.xml'
foreach ($path in @($m3uPath,$epgPath,$CandidateCsv)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "REQUIRED INPUT MISSING: $path" }
}
$rows = @(Import-Csv -LiteralPath $CandidateCsv -Encoding UTF8)
if ($rows.Count -ne 105) { throw "CANDIDATE BASELINE CHANGED: expected 105, got $($rows.Count)" }
$allIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$m3uLines = [IO.File]::ReadAllLines($m3uPath)
foreach ($line in $m3uLines) {
    if ($line -match '^#EXTINF:.*\btvg-id="([^"]+)"') {
        if (-not $allIds.Add($Matches[1])) { throw "DUPLICATE TVG ID: $($Matches[1])" }
    }
}
if ($allIds.Count -ne 158) { throw "PLAYLIST CHANNEL COUNT GUARD: expected 158, got $($allIds.Count)" }
foreach ($r in $rows) {
    if (-not $allIds.Contains($r.TVGID)) { throw "CANDIDATE NOT IN PLAYLIST: $($r.TVGID)" }
}
$now = [datetimeoffset]::UtcNow
$base = Read-XmlTvFacts -Path $epgPath -Wanted $allIds -Now $now
$baselineActive = 0
foreach ($id in $allIds) {
    if ($base.Facts.ContainsKey($id) -and $base.Facts[$id].Now -gt 0) { $baselineActive++ }
}
if ($baselineActive -lt 40) { throw "BASELINE TOO LOW ($baselineActive) - verify live published XMLTV before any extension" }

$runDir = Join-Path $ManagerRoot ('data\ua-autocatalog\v3\epg-audit\review-' + $now.UtcDateTime.ToString('yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$wantedGuides = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($r in $rows) {
    [void]$wantedGuides.Add($r.TVGID)
    if ($r.EPGShareUA1GuideIDCandidate) { [void]$wantedGuides.Add($r.EPGShareUA1GuideIDCandidate) }
}
$sourceData = @{}
$sourceStatuses = @()
$sourceDefs = @(
    @{ Id='EPGSHARE-UA1'; Uri='https://epgshare01.online/epgshare01/epg_ripper_UA1.xml.gz' },
    @{ Id='FREEEPG-UA'; Uri='https://free-epg.de/api/epg/ua.xml.gz' }
)
foreach ($source in $sourceDefs) {
    $srcId = $source.Id
    $tmpGz = Join-Path $runDir ($srcId + '.temporary.gz')
    $tmpXml = Join-Path $runDir ($srcId + '.temporary.xml')
    try {
        Get-BoundedGuide -Url $source.Uri -CompressedPath $tmpGz -XmlPath $tmpXml
        $parsed = Read-XmlTvFacts -Path $tmpXml -Wanted $wantedGuides -Now $now
        $sourceData[$srcId] = $parsed
        $sourceStatuses += [pscustomobject]@{ Source=$srcId; Status='OK'; ChannelIds=$parsed.Channels.Count; Error='' }
    } catch {
        # Failure is UNKNOWN, never silently represented as zero programmes.
        $sourceStatuses += [pscustomobject]@{ Source=$srcId; Status='UNAVAILABLE'; ChannelIds=$null; Error=$_.Exception.Message }
    } finally {
        Remove-Item -LiteralPath $tmpGz,$tmpXml -Force -ErrorAction SilentlyContinue
    }
}
$report = [System.Collections.Generic.List[object]]::new()
foreach ($r in $rows) {
    $tvgId = $r.TVGID
    $alias = $r.EPGShareUA1GuideIDCandidate
    $baseNow = if ($base.Facts.ContainsKey($tvgId)) { $base.Facts[$tvgId].Now } else { 0 }
    $matchSource = ''; $progNow=0; $progNext7=0; $titles=0
    $aliasFound = $false
    if ($alias -and $sourceData.ContainsKey('EPGSHARE-UA1')) {
        $dat = $sourceData['EPGSHARE-UA1']
        if ($dat.Channels.Contains($alias)) {
            $aliasFound = $true
            if ($dat.Facts.ContainsKey($alias)) {
                $rec = $dat.Facts[$alias]
                $progNow=$rec.Now; $progNext7=$rec.Next7; $titles=$rec.Titles.Count
                $matchSource='EPGSHARE-UA1'
            }
        }
    }
    $exactFree = $false
    if ($sourceData.ContainsKey('FREEEPG-UA')) {
        $dat2 = $sourceData['FREEEPG-UA']
        if ($dat2.Channels.Contains($tvgId) -and $dat2.Facts.ContainsKey($tvgId) -and $dat2.Facts[$tvgId].Now -gt 0) { $exactFree = $true }
    }
    $state = 'NO_VERIFIED_LIVE_PROGRAMMES'
    if ($baseNow -gt 0) { $state = 'ALREADY_COVERED' }
    elseif ($progNow -gt 0 -and $progNext7 -gt 0) { $state = 'LIVE_PROGRAMMES_IDENTITY_REVIEW_REQUIRED' }
    elseif ($aliasFound) { $state = 'CHANNEL_EXISTS_NO_CURRENT_PROGRAMMES' }
    elseif (-not $sourceData.ContainsKey('EPGSHARE-UA1')) { $state = 'EPGSHARE_UNAVAILABLE_NO_CONCLUSION' }
    if ($exactFree -and $baseNow -eq 0) { $state = 'FREEEPG_EXACT_ID_LIVE_REVIEW_REQUIRED' }
    if ($state -eq 'LIVE_PROGRAMMES_IDENTITY_REVIEW_REQUIRED' -and $tvgId -match 'Suspilne|Суспільне') { $state='REGIONAL_LIVE_IDENTITY_REVIEW_REQUIRED' }
    $report.Add([pscustomobject]@{
        TVGID=$tvgId; Name=$r.ChannelName; Group=$r.Group; BaselineNow=$baseNow;
        CandidateGuideId=$alias; Source=$matchSource; GuideChannelPresent=$aliasFound;
        ValidNow=$progNow; ValidNext7=$progNext7; DistinctTitles=$titles;
        FreeEpgExactIdNow=$exactFree; ReviewStatus=$state;
        AutoPublish='OFF'; StreamURLs='NOT_INCLUDED'
    })
}
$outCsv=Join-Path $runDir 'UA-EPG-COVERAGE-LIVE-CANDIDATES-URL-FREE.csv'
$report | Export-Csv -LiteralPath $outCsv -NoTypeInformation -Encoding utf8
$candidatesNow=@($report | Where-Object { $_.BaselineNow -eq 0 -and ($_.ValidNow -gt 0 -or $_.FreeEpgExactIdNow) }).Count
$summary=[ordered]@{
    Status='READ_ONLY_LIVE_GUIDE_AUDIT'; DateUTC=$now.UtcDateTime.ToString('o');
    Channels=$allIds.Count; ExpectedMissingInput=$rows.Count; BaselineLiveCurrent=$baselineActive;
    LiveCandidatesForIdentityReview=$candidatesNow; Sources=$sourceStatuses;
    Csv=$outCsv; PublishedM3UChanged=$false; PublishedEPGChanged=$false;
    StreamProbes=0; AutoPublish='OFF'; RU='NOT_TOUCHED'
}
$outJson=Join-Path $runDir 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outJson -Encoding UTF8
Write-Host "=== UA EPG LIVE COVERAGE AUDIT ==="
Write-Host "Baseline live EPG: $baselineActive / $($allIds.Count)"
Write-Host "Candidates with CURRENT programmes (not yet approved): $candidatesNow"
$sourceStatuses | Format-Table -AutoSize | Out-Host
Write-Host "Report: $outCsv"
Write-Host "Summary: $outJson"
Write-Host 'PRODUCTION UNCHANGED. Next step: identity review and guarded integration into existing 6-hour generator.'