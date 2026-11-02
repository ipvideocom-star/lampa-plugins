#requires -Version 7.0
# IPTV Manager / UA EPG preview v1 - no publication, no scheduled tasks.
# Generates a validated XMLTV preview in C:\ReservLampac; never edits prod M3U or plugins.json.
param()

$ErrorActionPreference = 'Stop'
$m3uPath = 'C:\IPTV-Manager\public\playlists\IPTV-UA.m3u'
$stageRoot = 'C:\ReservLampac\IPTVPlus\EPG-Staging'
$sourceUrls = [ordered]@{
    EPGShare = 'https://epgshare01.online/epgshare01/epg_ripper_UA1.xml.gz'
    OpenEPG  = 'https://www.open-epg.com/files/ukraine.xml.gz'
}
# Manually identified channel mappings; future additions require review.
$shareMap = @{
    'VivaLatino.ua@SD'           = 'Viva.Latino.[UA-UA].ua'
    '1Plus1International.ua@HD'  = '1+1.International.[UA-UA].ua'
    '366TV.ua@SD'               = '36,6.TV.[UA-UA].ua'
    'Bolt.ua@SD'                = 'Bolt.[UA-UA].ua'
    'DynamoKyivTV.ua@SD'        = 'Dynamo.Kyiv.TV.[UA-UA].ua'
    'Equalympic.ua@SD'          = 'Equalympic.[UA-UA].ua'
    'FilmUALive.ua@SD'          = 'FILMUA.Live.[UA-UA].ua'
    'ICTV2.ua@SD'               = 'ICTV2.[UA-UA].ua'
    'ITV.ua@SD'                 = 'ITV.[UA-UA].ua'
    'Kino1.ua@SD'               = 'Kino.1.[UA-UA].ua'
    'MegogoMusic.ua@SD'         = 'Megogo.Music.[UA-UA].ua'
    'Sport5.ua@SD'              = 'Sport.5.[UA-RU].ua'
    'UAMusic.ua@HD'             = 'UA.Music.[UA-UA].ua'
    'Zoom.ua@SD'                = 'Zoom.[UA-UA].ua'
}

function Read-XmltvFile([string]$path) {
    $fs = [IO.File]::OpenRead($path)
    $stream = $null
    $xr = $null
    try {
        $signature = [byte[]]::new(3)
        $n = $fs.Read($signature, 0, 3)
        $fs.Position = 0
        if ($n -eq 3 -and $signature[0] -eq 31 -and
            $signature[1] -eq 139 -and $signature[2] -eq 8) {
            $stream = [IO.Compression.GZipStream]::new(
                $fs, [IO.Compression.CompressionMode]::Decompress)
        } else {
            $stream = $fs
        }
        $settings = [Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [Xml.DtdProcessing]::Ignore
        $settings.XmlResolver = $null
        $xr = [Xml.XmlReader]::Create($stream, $settings)
        $doc = [Xml.XmlDocument]::new()
        $doc.XmlResolver = $null
        $doc.Load($xr)
        if ($doc.DocumentElement.LocalName -ne 'tv') {
            throw "Not XMLTV: $path"
        }
        return $doc
    }
    finally {
        if ($xr) { $xr.Dispose() }
        if ($stream) { $stream.Dispose() }
        $fs.Dispose()
    }
}

function Convert-XmltvTime([string]$value) {
    if ($value -notmatch '^([0-9]{14}|[0-9]{12})(?:\s*([+-][0-9]{4}))?') {
        return $null
    }
    $stamp = $Matches[1]
    $zone = $Matches[2]
    if ($stamp.Length -eq 12) { $stamp += '00' }
    try {
        $date = [DateTime]::ParseExact(
            $stamp, 'yyyyMMddHHmmss', [Globalization.CultureInfo]::InvariantCulture)
        $minutes = 0
        if ($zone) {
            $direction = if ($zone.StartsWith('-')) { -1 } else { 1 }
            $hours = [int]$zone.Substring(1,2)
            $mins = [int]$zone.Substring(3,2)
            $minutes = $direction * ($hours * 60 + $mins)
        }
        return ([DateTimeOffset]::new(
            $date, [TimeSpan]::FromMinutes($minutes))).UtcDateTime
    }
    catch {
        return $null
    }
}

function Test-MeaningfulTitle([Xml.XmlNode]$node) {
    $titleNode = $node.SelectSingleNode('title')
    $title = if ($titleNode) { $titleNode.InnerText.Trim() } else { '' }
    if (-not $title) { return $false }
    if ($title -match '(?i)^(no data|no epg|n/?a|unknown|tba|нет данных|немає даних|програма відсутня|программа отсутствует|no programme information|no program information)\.?\s*$') {
        return $false
    }
    $description = $node.SelectSingleNode('desc')
    if ($description -and $description.InnerText -match 'iptv-epg\.org/help') {
        return $false
    }
    return $true
}

function Get-ProgrammeIndex([Xml.XmlDocument]$doc, $allowed, [DateTime]$minUtc, [DateTime]$maxUtc) {
    $index = @{}
    foreach ($node in $doc.SelectNodes('/tv/programme')) {
        $id = $node.GetAttribute('channel')
        if (-not $allowed.Contains($id)) { continue }
        if (-not (Test-MeaningfulTitle $node)) { continue }
        $start = Convert-XmltvTime $node.GetAttribute('start')
        $stop = Convert-XmltvTime $node.GetAttribute('stop')
        if ($null -eq $start -or $null -eq $stop -or
            $stop -le $start -or $stop -le $minUtc -or $start -ge $maxUtc) { continue }
        if (-not $index.ContainsKey($id)) {
            $index[$id] = [Collections.Generic.List[object]]::new()
        }
        $index[$id].Add([pscustomobject]@{
            Start = $start; Stop = $stop; Node = $node
        })
    }
    return $index
}

function Get-CoverageMinutes($items, [DateTime]$from, [DateTime]$until) {
    if ($null -eq $items) { return 0 }
    $ranges = @(
        foreach ($item in $items) {
            if ($item.Stop -le $from -or $item.Start -ge $until) { continue }
            [pscustomobject]@{
                Start = if ($item.Start -lt $from) { $from } else { $item.Start }
                Stop  = if ($item.Stop -gt $until) { $until } else { $item.Stop }
            }
        }
    ) | Sort-Object Start
    if (-not $ranges) { return 0 }
    $left = $ranges[0].Start
    $right = $ranges[0].Stop
    $minutes = 0.0
    foreach ($range in @($ranges | Select-Object -Skip 1)) {
        if ($range.Start -le $right) {
            if ($range.Stop -gt $right) { $right = $range.Stop }
        } else {
            $minutes += ($right - $left).TotalMinutes
            $left = $range.Start
            $right = $range.Stop
        }
    }
    $minutes += ($right - $left).TotalMinutes
    return [math]::Round($minutes)
}

if (-not (Test-Path -LiteralPath $m3uPath -PathType Leaf)) {
    throw "Missing M3U: $m3uPath"
}
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' +
    [Guid]::NewGuid().ToString('N').Substring(0,8)
$runDir = Join-Path $stageRoot "preview-$runId"
New-Item -ItemType Directory -Path $runDir | Out-Null
$now = [DateTime]::UtcNow
$future24 = $now.AddHours(24)
$future48 = $now.AddHours(48)
$from = $now.AddDays(-1)
$until = $now.AddDays(3)

Write-Host '=== IPTV EPG PREVIEW (NO PUBLICATION) ==='
Write-Host "Run: $runId"
$ids = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($line in (Get-Content -LiteralPath $m3uPath -Encoding UTF8)) {
    if ($line -match '^#EXTINF:' -and $line -match 'tvg-id="([^"]+)"') {
        [void]$ids.Add($Matches[1])
    }
}
if ($ids.Count -ne 84) { throw "Unexpected M3U count: $($ids.Count)" }
Write-Host "M3U IDs: $($ids.Count)"

$docs = @{}
foreach ($source in $sourceUrls.GetEnumerator()) {
    $file = Join-Path $runDir ($source.Key + '.download')
    Write-Host "Downloading: $($source.Key)"
    & curl.exe -fLsS --connect-timeout 10 --max-time 90 --max-filesize 20000000 -o $file $source.Value
    if ($LASTEXITCODE -ne 0) { throw "$($source.Key) download failed: $LASTEXITCODE" }
    $docs[$source.Key] = Read-XmltvFile $file
}
$openSourceIdByBase = @{}
$openAllowed = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($ch in $docs.OpenEPG.SelectNodes('/tv/channel')) {
    $sourceId = $ch.GetAttribute('id')
    $base = ($sourceId -split '@')[0]
    if (-not $openSourceIdByBase.ContainsKey($base)) {
        $openSourceIdByBase[$base] = $sourceId
        [void]$openAllowed.Add($sourceId)
    }
}
$shareAllowed = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($sourceId in $shareMap.Values) { [void]$shareAllowed.Add($sourceId) }
$openIndex = Get-ProgrammeIndex $docs.OpenEPG $openAllowed $from $until
$shareIndex = Get-ProgrammeIndex $docs.EPGShare $shareAllowed $from $until

$channelNodes = @{}
foreach ($sourceName in @('OpenEPG','EPGShare')) {
    $channelNodes[$sourceName] = @{}
    foreach ($node in $docs[$sourceName].SelectNodes('/tv/channel')) {
        $channelNodes[$sourceName][$node.GetAttribute('id')] = $node
    }
}

$generated = [Xml.XmlDocument]::new()
[void]$generated.AppendChild(
    $generated.CreateXmlDeclaration('1.0','UTF-8',$null))
$root = $generated.CreateElement('tv')
$root.SetAttribute('generator-info-name','IPTV Manager UA EPG preview v1')
[void]$generated.AppendChild($root)
$rows = [Collections.Generic.List[object]]::new()
$programmes = 0
$coveredNow = 0

foreach ($target in ($ids | Sort-Object)) {
    $candidates = [Collections.Generic.List[object]]::new()
    $base = ($target -split '@')[0]
    if ($openSourceIdByBase.ContainsKey($base)) {
        $sourceId = $openSourceIdByBase[$base]
        if ($openIndex.ContainsKey($sourceId)) {
            $items = @($openIndex[$sourceId].ToArray())
            $candidates.Add([pscustomobject]@{
                Source = 'OpenEPG'; Id = $sourceId; Items = $items
                Next24 = Get-CoverageMinutes $items $now $future24
                Next48 = Get-CoverageMinutes $items $now $future48
            })
        }
    }
    if ($shareMap.ContainsKey($target)) {
        $sourceId = $shareMap[$target]
        if ($shareIndex.ContainsKey($sourceId)) {
            $items = @($shareIndex[$sourceId].ToArray())
            $candidates.Add([pscustomobject]@{
                Source = 'EPGShare'; Id = $sourceId; Items = $items
                Next24 = Get-CoverageMinutes $items $now $future24
                Next48 = Get-CoverageMinutes $items $now $future48
            })
        }
    }
    if ($candidates.Count -eq 0) { continue }
    $best = $candidates |
        Sort-Object -Property @{Expression='Next24';Descending=$true},
                               @{Expression='Next48';Descending=$true} |
        Select-Object -First 1
    # Avoid advertising stale/historical-only programme information.
    if ($best.Next24 -le 0) { continue }
    $sourceChannel = $channelNodes[$best.Source][$best.Id]
    if ($null -ne $sourceChannel) {
        $newChannel = $generated.ImportNode($sourceChannel, $true)
        $newChannel.SetAttribute('id', $target)
    } else {
        $newChannel = $generated.CreateElement('channel')
        $newChannel.SetAttribute('id', $target)
        $name = $generated.CreateElement('display-name')
        $name.InnerText = $target
        [void]$newChannel.AppendChild($name)
    }
    [void]$root.AppendChild($newChannel)
    $seen = [Collections.Generic.HashSet[string]]::new()
    $copied = 0
    $active = $false
    foreach ($item in ($best.Items | Sort-Object Start)) {
        $title = $item.Node.SelectSingleNode('title').InnerText.Trim()
        $key = "$($item.Start.Ticks)|$($item.Stop.Ticks)|$title"
        if (-not $seen.Add($key)) { continue }
        $copy = $generated.ImportNode($item.Node, $true)
        $copy.SetAttribute('channel', $target)
        [void]$root.AppendChild($copy)
        $copied++
        if ($item.Start -le $now -and $item.Stop -gt $now) { $active = $true }
    }
    if ($active) { $coveredNow++ }
    $programmes += $copied
    $rows.Add([pscustomobject]@{
        Channel = $target; Source = $best.Source
        CoverageNext24Min = $best.Next24
        CoverageNext48Min = $best.Next48
        LiveNow = $active; Programmes = $copied
    })
}
if ($rows.Count -lt 5 -or $programmes -lt 50) {
    throw "Preview rejected: channels=$($rows.Count), programmes=$programmes"
}
$outputFile = Join-Path $runDir 'IPTV-UA-EPG-preview.xml'
$generated.Save($outputFile)

# Read back the exact generated file and validate all IDs and title contents.
$check = Read-XmltvFile $outputFile
$xmlChannels = @($check.SelectNodes('/tv/channel'))
$xmlProgrammes = @($check.SelectNodes('/tv/programme'))
if ($xmlChannels.Count -ne $rows.Count -or $xmlProgrammes.Count -ne $programmes) {
    throw 'XMLTV counts failed after read-back'
}
$chosenIds = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($node in $xmlChannels) {
    if (-not $ids.Contains($node.GetAttribute('id')) -or
        -not $chosenIds.Add($node.GetAttribute('id'))) {
        throw 'Duplicate/unknown output channel ID'
    }
}
foreach ($node in $xmlProgrammes) {
    if (-not $chosenIds.Contains($node.GetAttribute('channel')) -or
        -not (Test-MeaningfulTitle $node)) {
        throw 'Invalid programme in generated XMLTV'
    }
}

$report = [ordered]@{
    status='STAGED_NOT_PUBLISHED'; generatedUtc=$now.ToString('o')
    m3uChannels=$ids.Count; epgChannels=$rows.Count
    channelsWithProgrammeNow=$coveredNow; programmes=$programmes
    totalMinutesCoveredNext24=($rows | Measure-Object CoverageNext24Min -Sum).Sum
    sha256=(Get-FileHash $outputFile -Algorithm SHA256).Hash
    file=$outputFile
    details=@($rows)
}
$reportPath = Join-Path $runDir 'report.json'
[IO.File]::WriteAllText(
    $reportPath, ($report | ConvertTo-Json -Depth 12),
    [Text.UTF8Encoding]::new($false))

Write-Host '=== QUALITY BY CHANNEL ==='
$rows | Sort-Object CoverageNext24Min -Descending |
    Format-Table Channel, Source, CoverageNext24Min, CoverageNext48Min, LiveNow, Programmes -AutoSize
Write-Host '=== SUMMARY ==='
[pscustomobject]@{
    M3UChannels=$ids.Count; EPGChannels=$rows.Count
    ChannelsWithProgrammeNow=$coveredNow; Programmes=$programmes
    CoveredHoursAcrossAllChannels=[math]::Round(($report.totalMinutesCoveredNext24 / 60),1)
    Preview=$outputFile; Report=$reportPath
    Publication='NONE'
} | Format-List
Write-Host 'EPG PREVIEW: OK (NOT PUBLISHED)'
