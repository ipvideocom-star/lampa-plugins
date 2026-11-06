#requires -Version 7.0
<#{
Read-only diagnostic for the current 257-channel IPTV+ pilot.
- Maps ALL 85 RU channels (173-257) to current routes.
- Compares selected RU sources from W2022 via DIRECT and W2019S 3proxy.
- Tests HLS manifest timing and a bounded segment-range fetch.
- No config changes, no relay restarts, no public stream URLs or tokens in reports.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$PSNativeCommandUseErrorActionPreference = $false

$pilot = 'C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\IPTV-UA-RU-Relay-v02-257-STAGING-NOT-PUBLISHED.m3u'
$stage = 'C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\First-Expansion-20261105-215516-d198e6bb\RU-Relay-Candidates-FIRST-STAGING.json'
$start = 'C:\IPTV-Manager\relay\iptv_hls_relay_v02\Start-IPTV-HLS-Relay-v02.ps1'
$reportDir = 'C:\ReservLampac\IPTVPlus\RU-Network-Diagnostics'

foreach ($path in @($pilot,$stage,$start)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required input missing: $path" }
}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'curl.exe unavailable' }

$stageObj = Get-Content -LiteralPath $stage -Raw -Encoding UTF8 | ConvertFrom-Json
if ($stageObj.Mode -ne 'STAGING_ONLY' -or [bool]$stageObj.AutoPublish -or
    @($stageObj.Candidates).Count -ne 65) { throw 'Unexpected candidate staging; no tests started' }

# Read proxy URL from the currently installed, existing starter. Never print it.
$startSource = Get-Content -LiteralPath $start -Raw -Encoding UTF8
$m = [regex]::Match($startSource, '(?m)\[string\]\$ProxyUrl\s*=\s*''(?<value>https?://[^'']+)''')
if (-not $m.Success) { throw 'Could not identify existing 3proxy URL in relay starter; no tests started' }
$proxyUrl = $m.Groups['value'].Value

$channels = [Collections.Generic.List[object]]::new()
$currentName = $null
$currentGroup = ''
foreach ($line0 in [IO.File]::ReadAllLines($pilot)) {
    $line = $line0.Trim()
    if ($line.StartsWith('#EXTINF:')) {
        $currentName = $line.Substring($line.LastIndexOf(',') + 1).Trim()
        $gm = [regex]::Match($line,'group-title="([^"]*)"','IgnoreCase')
        $currentGroup = if ($gm.Success) { $gm.Groups[1].Value } else { 'Без группы' }
    } elseif ($null -ne $currentName -and $line.StartsWith('#EXTGRP:')) {
        $currentGroup = $line.Substring(8).Trim()
    } elseif ($null -ne $currentName -and $line -match '^https?://') {
        $channels.Add([pscustomobject]@{
            Number = $channels.Count + 1; Name = $currentName; Group = $currentGroup; Url = $line
        })
        $currentName = $null
    }
}
if ($channels.Count -ne 257) { throw "Expected 257 entries, got $($channels.Count)" }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$routeCsv = Join-Path $reportDir "RU-Route-Map-85-$stamp.csv"
$timingCsv = Join-Path $reportDir "RU-Path-Timings-$stamp.csv"
$summary = Join-Path $reportDir "RU-Path-Summary-$stamp.txt"

$routeRows = [Collections.Generic.List[object]]::new()
foreach ($ch in ($channels | Where-Object { $_.Number -ge 173 -and $_.Number -le 257 })) {
    $ruIndex = $ch.Number - 124
    $candidates = @($stageObj.Candidates | Where-Object { [int]$_.Index -eq $ruIndex })
    $isRelay = $ch.Url.Contains('/iptv-relay/p/')
    $observed = if ($isRelay) { 'RELAY' } elseif ($ch.Url -match '^https?://lampa\.v6\.army/') { 'LOCAL_WEB' } else { 'CLIENT_DIRECT' }
    $route = if ($isRelay -and $candidates.Count) { [string]$candidates[0].Route } elseif ($isRelay) { 'UNKNOWN_RELAY' } else { 'NOT_USING_RELAY' }
    $routeRows.Add([pscustomobject]@{
        PlaylistIndex = $ch.Number; RUIndex = $ruIndex; Channel = $ch.Name
        ClientURLType = $observed; SelectedRelayRoute = $route
        AvailableRelayCandidates = $candidates.Count
    })
}
$routeRows | Export-Csv -LiteralPath $routeCsv -NoTypeInformation -Encoding UTF8

# Bounded set of central RU channels, selected by existing playlist position.
$sampleIds = @(180,184,189,190,196,200,205,206,214,218,222,225,226,227,235,239,243)
$timings = [Collections.Generic.List[object]]::new()
$tmpDir = Join-Path $reportDir ".temporary-$stamp-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

function Read-TestUrl {
    param([string]$Url, [string]$Method, [bool]$Segment)
    $dest = Join-Path $tmpDir ([guid]::NewGuid().ToString('N') + '.part')
    $args = @('--silent','--show-error','--globoff','--location','--max-redirs','3',
              '--connect-timeout','4','--max-time','9','--max-filesize','262144',
              '--output',$dest,'--write-out','TEST|%{http_code}|%{time_starttransfer}|%{time_total}|%{size_download}')
    if ($Segment) { $args += @('--range','0-65535','--max-filesize','131072') }
    if ($Method -eq 'PROXY_W2019S') { $args += @('--proxy',$proxyUrl) }
    else { $args += @('--noproxy','*') }
    $args += $Url
    $raw = @( & curl.exe @args 2>$null )
    $exitCode = $LASTEXITCODE
    $metric = [string](@($raw | Where-Object { $_ -match '^TEST\|' } | Select-Object -Last 1)[0])
    $parts = $metric -split '\|'
    $http = if ($parts.Count -ge 5) { $parts[1] } else { '000' }
    $first = if ($parts.Count -ge 5) { $parts[2] } else { '0' }
    $total = if ($parts.Count -ge 5) { $parts[3] } else { '0' }
    $bytes = if ($parts.Count -ge 5) { $parts[4] } else { '0' }
    $body = ''
    if (-not $Segment -and (Test-Path -LiteralPath $dest -PathType Leaf)) {
        if ((Get-Item -LiteralPath $dest).Length -le 262144) {
            $body = [IO.File]::ReadAllText($dest)
        }
    }
    Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        Http = $http; TTFB = $first; Total = $total; Bytes = $bytes
        Exit = $exitCode; Body = $body
    }
}

function Find-Segment {
    param([string]$Text, [string]$BaseUrl)
    if (-not $Text.TrimStart([char]0xFEFF).StartsWith('#EXTM3U')) { return $null }
    $lines = @($Text -split "`r?`n")
    # Master playlists point to a media playlist, not a segment; caller may fetch one more level.
    $variants = [Collections.Generic.List[string]]::new()
    $segments = [Collections.Generic.List[string]]::new()
    for ($i=0; $i -lt $lines.Count-1; $i++) {
        if ($lines[$i].Trim() -match '^#EXT-X-STREAM-INF:') {
            $next = $lines[$i+1].Trim()
            if ($next -and -not $next.StartsWith('#')) { $variants.Add($next) }
        }
        if ($lines[$i].Trim() -match '^#EXTINF:') {
            $next = $lines[$i+1].Trim()
            if ($next -and -not $next.StartsWith('#')) { $segments.Add($next) }
        }
    }
    $link = if ($segments.Count) { $segments[-1] } elseif ($variants.Count) { $variants[0] } else { $null }
    if (-not $link) { return $null }
    try {
        $resolved = [Uri]::new([Uri]$BaseUrl,$link)
        if ($resolved.Scheme -notin @('https','http')) { return $null }
        return [pscustomobject]@{ Url = $resolved.AbsoluteUri; IsVariant = ($segments.Count -eq 0) }
    } catch { return $null }
}

Write-Host '=== RUSSIAN IPTV: DIRECT VS W2019S/3PROXY ==='
Write-Host '85 RU channels mapped. Now testing selected central channels (read-only).'
Write-Host 'Metrics: HTTP status, time to first byte (TTFB), HLS segment response.'
Write-Host 'Source URLs, relay tokens and proxy details are NOT printed.'
Write-Host ''

try {
    foreach ($id in $sampleIds) {
        $ch = $channels[$id-1]
        $ruIndex = $id - 124
        $choices = @($stageObj.Candidates | Where-Object { [int]$_.Index -eq $ruIndex } | Select-Object -First 2)
        $sources = [Collections.Generic.List[object]]::new()
        if ($choices.Count) {
            for ($i=0; $i -lt $choices.Count; $i++) {
                $sources.Add([pscustomobject]@{Url=[string]$choices[$i].URL; Route=[string]$choices[$i].Route; Number=$i})
            }
        } elseif ($ch.Url -notmatch '/iptv-relay/p/') {
            $sources.Add([pscustomobject]@{Url=$ch.Url;Route='CLIENT_DIRECT';Number=0})
        }
        if ($sources.Count -eq 0) {
            Write-Host ('{0:000} {1}: SKIP (no verified upstream mapping)' -f $id,$ch.Name)
            continue
        }
        foreach ($src in $sources) {
            if ($src.Url -notmatch '^https?://') { continue }
            foreach ($method in @('DIRECT_W2022','PROXY_W2019S')) {
                $r = Read-TestUrl -Url $src.Url -Method $method -Segment $false
                $segment = 'NOT_TESTED'
                $segmentCode = '-'
                $segmentTTFB = '-'
                if ($r.Http -eq '200') {
                    $link = Find-Segment -Text $r.Body -BaseUrl $src.Url
                    if ($link -and $link.IsVariant) {
                        $variant = Read-TestUrl -Url $link.Url -Method $method -Segment $false
                        if ($variant.Http -eq '200') { $link = Find-Segment -Text $variant.Body -BaseUrl $link.Url }
                        else { $link = $null }
                    }
                    if ($link -and -not $link.IsVariant) {
                        $s = Read-TestUrl -Url $link.Url -Method $method -Segment $true
                        $segmentCode = $s.Http
                        $segmentTTFB = $s.TTFB
                        $segment = if ($s.Http -in @('200','206') -and $s.Exit -eq 0) { 'OK' }
                                   elseif ($s.Http -in @('200','206') -and $s.Bytes -gt 0) { 'PARTIAL' }
                                   else { 'FAILED' }
                    } else { $segment = 'NO_MEDIA_SEGMENT' }
                }
                $timings.Add([pscustomobject]@{
                    PlaylistIndex = $id; Channel = $ch.Name; Candidate = $src.Number
                    SourceIntendedRoute = $src.Route; TestedRoute = $method
                    ManifestHTTP = $r.Http; ManifestExitCode = $r.Exit
                    ManifestTTFBSeconds = $r.TTFB; ManifestTotalSeconds = $r.Total
                    SegmentStatus = $segment; SegmentHTTP = $segmentCode
                    SegmentTTFBSeconds = $segmentTTFB
                })
                Write-Host ('{0:000} {1} | source={2} {3} | HLS={4} TTFB={5}s | SEG={6} {7}' -f `
                    $id,$ch.Name,$src.Number,$method,$r.Http,$r.TTFB,$segment,$segmentTTFB)
            }
        }
    }
} finally {
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
$timings | Export-Csv -LiteralPath $timingCsv -NoTypeInformation -Encoding UTF8
$relayCount = @($routeRows | Where-Object { $_.ClientURLType -eq 'RELAY' }).Count
$directCount = @($routeRows | Where-Object { $_.ClientURLType -eq 'CLIENT_DIRECT' }).Count
$proxyCount = @($routeRows | Where-Object { $_.SelectedRelayRoute -eq 'REMOTE_W2019S_NEEDS_RELAY' }).Count
$lines = @(
    'RU IPTV PATH DIAGNOSTIC - READ ONLY',
    '==================================',
    "Total RU channels mapped: $($routeRows.Count)",
    "Current pilot entries via Relay: $relayCount",
    "Current pilot entries direct to client: $directCount",
    "Relay entries configured for W2019S proxy: $proxyCount",
    "Timing tests performed: $($timings.Count)",
    "Full routing map (85): $routeCsv",
    "Direct / proxy benchmark: $timingCsv",
    '',
    'Interpretation:',
    'DIRECT slow, PROXY fast: upstream path or geolocation likely affects performance.',
    'DIRECT fast, PROXY slow: W2019S path / 3proxy / exit path likely affects performance.',
    'Both slow: origin/CDN, stream availability, or common route may be the cause.',
    'Both fast but Samsung slow: inspect client playback, exact playlist route and device codec.',
    'These tests do NOT prove deliberate traffic blocking; only compare observed behavior.',
    'Original Relay 9144 / First Relay 9145 / Caddy / M3U: UNCHANGED.'
)
[IO.File]::WriteAllLines($summary,$lines,[Text.UTF8Encoding]::new($true))
Write-Host ''
Write-Host '=== DIAGNOSTIC COMPLETE ==='
Write-Host "RU channels mapped: $($routeRows.Count)"
Write-Host "Via Relay: $relayCount; client direct: $directCount; through W2019S marked in Relay: $proxyCount"
Write-Host "Measurements: $($timings.Count)"
Write-Host "SUMMARY: $summary"
Write-Host "ROUTES:  $routeCsv"
Write-Host "TIMINGS: $timingCsv"
Write-Host 'NO CONFIGURATION CHANGES'