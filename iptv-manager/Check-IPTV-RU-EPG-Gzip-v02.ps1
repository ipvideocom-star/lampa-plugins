#requires -Version 7.0
# RU pilot EPG validation v02: compressed feed + streaming XML.
# Never publishes or changes playlists, EPG files or Plugin Manager.
$ErrorActionPreference='Stop'
$playlist='C:\IPTV-Manager\public\playlists\IPTV-RU-Pilot-v1.m3u'
$url='https://iptv-epg.org/files/epg-ru.xml.gz'
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$stage=Join-Path 'C:\ReservLampac\IPTVPlus\RU-EPG' $runId
$download=Join-Path $stage 'epg-ru.xml.gz'
$today=(Get-Date).ToString('yyyyMMdd')
$tomorrow=(Get-Date).AddDays(1).ToString('yyyyMMdd')
function Normalize-Channel([string]$v) {
    $v=$v.Trim()
    $v=$v -replace '(?i)\.[a-z]{2}(?:@[a-z0-9_-]+)?$',''
    $v=$v -replace '(?i)\s*\(\d{3,4}[pi]\)',''
    $v=$v -replace '(?i)\s*\[geo-blocked\]',''
    $v=$v -replace '(?i)\s+(HD|SD|FHD|UHD|4K)$',''
    return [regex]::Replace($v.ToLowerInvariant(),'[^\p{L}\p{Nd}]','')
}
function Is-MeaningfulTitle([string]$title,[string]$description) {
    if (-not $title.Trim()) { return $false }
    if ($title -match '(?i)^(no data|no epg|unknown|tba|n/?a|нет данных|немає даних|програма відсутня|программа отсутствует)\.?\s*$') {
        return $false
    }
    if ($description -match 'iptv-epg\.org/help') { return $false }
    return $true
}
if (-not (Test-Path -LiteralPath $playlist -PathType Leaf)) {
    throw "RU pilot playlist missing: $playlist"
}
$targets=[Collections.Generic.List[object]]::new()
$index=@{}
foreach($line in [IO.File]::ReadLines($playlist,[Text.Encoding]::UTF8)) {
    if ($line -notmatch '^#EXTINF:') { continue }
    $m=[regex]::Match($line,'tvg-id="([^"]+)"')
    if (-not $m.Success) { continue }
    $id=$m.Groups[1].Value
    $name=$line.Substring($line.LastIndexOf(',')+1).Trim()
    $targets.Add([pscustomobject]@{Id=$id;Name=$name})
    foreach($text in @($id,$name)) {
        $key=Normalize-Channel $text
        if (-not $key) { continue }
        if (-not $index.ContainsKey($key)) {
            $index[$key]=[Collections.Generic.HashSet[string]]::new(
                [StringComparer]::OrdinalIgnoreCase)
        }
        [void]$index[$key].Add($id)
    }
}
if ($targets.Count -ne 14) { throw "Expected 14 RU channels; got $($targets.Count)" }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Write-Host '=== DOWNLOAD COMPRESSED RU XMLTV ==='
& curl.exe -fLsS --connect-timeout 12 --max-time 120 --max-filesize 40000000 -o $download $url
if ($LASTEXITCODE -ne 0) { throw "EPG download error: $LASTEXITCODE" }
Write-Host "Compressed bytes: $((Get-Item $download).Length)"
$hitsByTarget=@{}
foreach($t in $targets) {
    $hitsByTarget[$t.Id]=[Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
}
$stats=@{}
$totalChannels=0
$totalPrograms=0
$fs=$null
$stream=$null
$xr=$null
try {
    $fs=[IO.File]::OpenRead($download)
    $magic=[byte[]]::new(3)
    $n=$fs.Read($magic,0,3)
    $fs.Position=0
    if ($n -eq 3 -and $magic[0] -eq 31 -and $magic[1] -eq 139 -and $magic[2] -eq 8) {
        $stream=[IO.Compression.GZipStream]::new($fs,[IO.Compression.CompressionMode]::Decompress)
        Write-Host 'Payload: GZIP'
    } else {
        $stream=$fs
        Write-Host 'Payload: PLAIN XML'
    }
    $settings=[Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing=[Xml.DtdProcessing]::Ignore
    $settings.XmlResolver=$null
    $xr=[Xml.XmlReader]::Create($stream,$settings)
    Write-Host '=== STREAMING CHANNELS AND PROGRAMMES ==='
    while (-not $xr.EOF) {
        if ($xr.NodeType -eq [Xml.XmlNodeType]::Element) {
            if ($xr.LocalName -eq 'channel') {
                $totalChannels++
                $epgId=$xr.GetAttribute('id')
                $outer=$xr.ReadOuterXml()
                if (-not $epgId) { continue }
                $doc=[Xml.XmlDocument]::new()
                $doc.XmlResolver=$null
                $doc.LoadXml($outer)
                $values=@($epgId)+@(
                    foreach($nameNode in $doc.DocumentElement.SelectNodes('display-name')) {
                        $nameNode.InnerText
                    }
                )
                $matched=[Collections.Generic.HashSet[string]]::new(
                    [StringComparer]::OrdinalIgnoreCase)
                foreach($v in $values) {
                    $key=Normalize-Channel $v
                    if ($key -and $index.ContainsKey($key)) {
                        foreach($targetId in $index[$key]) {
                            [void]$matched.Add($targetId)
                        }
                    }
                }
                if ($matched.Count -gt 0) {
                    $stats[$epgId]=[pscustomobject]@{Today=0;Tomorrow=0;Example=''}
                    foreach($targetId in $matched) {
                        [void]$hitsByTarget[$targetId].Add($epgId)
                    }
                }
                continue
            }
            if ($xr.LocalName -eq 'programme') {
                $totalPrograms++
                $epgId=$xr.GetAttribute('channel')
                if ($epgId -and $stats.ContainsKey($epgId)) {
                    $date=$xr.GetAttribute('start')
                    if ($date -and $date.Length -ge 8) {
                        $day=$date.Substring(0,8)
                        if ($day -eq $today -or $day -eq $tomorrow) {
                            $outer=$xr.ReadOuterXml()
                            $doc=[Xml.XmlDocument]::new()
                            $doc.XmlResolver=$null
                            $doc.LoadXml($outer)
                            $t=$doc.DocumentElement.SelectSingleNode('title')
                            $d=$doc.DocumentElement.SelectSingleNode('desc')
                            $title=if($t){$t.InnerText.Trim()}else{''}
                            $desc=if($d){$d.InnerText.Trim()}else{''}
                            if (Is-MeaningfulTitle $title $desc) {
                                if ($day -eq $today) {$stats[$epgId].Today++}
                                else {$stats[$epgId].Tomorrow++}
                                if(-not $stats[$epgId].Example){$stats[$epgId].Example=$title}
                            }
                            continue
                        }
                    }
                }
            }
        }
        if (-not $xr.Read()) { break }
    }
}
finally {
    if ($xr) { $xr.Dispose() }
    if ($stream) { $stream.Dispose() }
    if ($fs) { $fs.Dispose() }
}
$rows=@(
    foreach($target in $targets) {
        $epgIds=@($hitsByTarget[$target.Id] | Sort-Object)
        $s=if($epgIds.Count -eq 1){$stats[$epgIds[0]]}else{$null}
        [pscustomobject]@{
            Channel=$target.Name
            M3uId=$target.Id
            Candidates=$epgIds.Count
            EpgIds=($epgIds -join ' | ')
            Today=if($s){$s.Today}else{0}
            Tomorrow=if($s){$s.Tomorrow}else{0}
            Example=if($s){$s.Example}else{''}
        }
    }
)
Write-Host '=== MATCH RESULTS ==='
$rows | Format-Table Channel,EpgIds,Candidates,Today,Tomorrow,Example -Wrap -AutoSize
$summary=[pscustomobject]@{
    RUChannels=$targets.Count
    GuideChannels=$totalChannels
    GuideProgrammes=$totalPrograms
    UniqueMatches=@($rows | Where-Object {$_.Candidates -eq 1}).Count
    Today=@($rows | Where-Object {$_.Today -gt 0}).Count
    Tomorrow=@($rows | Where-Object {$_.Tomorrow -gt 0}).Count
    Ambiguous=@($rows | Where-Object {$_.Candidates -gt 1}).Count
    Report=(Join-Path $stage 'matches.json')
    Publication='NONE'
}
[IO.File]::WriteAllText(
    $summary.Report,
    (([ordered]@{summary=$summary;channels=@($rows)}) | ConvertTo-Json -Depth 7),
    [Text.UTF8Encoding]::new($false)
)
Write-Host '=== SUMMARY ==='
$summary | Format-List
Write-Host 'RU EPG COMPRESSED CHECK: COMPLETE'
