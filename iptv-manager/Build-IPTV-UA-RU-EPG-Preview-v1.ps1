#requires -Version 7.0
# IPTV Manager: merge published UA EPG with exact RU pilot channel mappings.
# Staging only: NO publication, NO plugin/scheduler changes, NO source download.
$ErrorActionPreference='Stop'
$uaGuide='C:\IPTV-Manager\public\playlists\IPTV-UA-EPG-Merged-test.xml'
$ruPlaylist='C:\IPTV-Manager\public\playlists\IPTV-RU-Pilot-v1.m3u'
$ruRoot='C:\ReservLampac\IPTVPlus\RU-EPG'
$stageRoot='C:\ReservLampac\IPTVPlus\RU-EPG-Merge'
$map=[ordered]@{
    'ПОБЕДА.ru'='Pobeda.ru@SD'
    'СТСLove.ru'='STSLove.ru@SD'
    'Телекафе.ru'='Telecafe.ru@SD'
    'Точкаотрыва.ru'='Tochkaotryva.ru@SD'
    'Вгостяхусказки.ru'='Vgostyakhuskazki.ru@SD'
    'Время:далекоеиблизкое.ru'='Vremya.ru@SD'
}
function Convert-XmltvUtc([string]$value) {
    if ($value -notmatch '^([0-9]{14}|[0-9]{12})(?:\s*([+-][0-9]{4}))?') {
        return $null
    }
    $stamp=$Matches[1];$zone=$Matches[2]
    if($stamp.Length -eq 12){$stamp+='00'}
    try {
        $dt=[DateTime]::ParseExact($stamp,'yyyyMMddHHmmss',[Globalization.CultureInfo]::InvariantCulture)
        $minutes=0
        if($zone) {
            $sign=if($zone.StartsWith('-')){-1}else{1}
            $minutes=$sign*([int]$zone.Substring(1,2)*60+[int]$zone.Substring(3,2))
        }
        return ([DateTimeOffset]::new($dt,[TimeSpan]::FromMinutes($minutes))).UtcDateTime
    }catch{return $null}
}
function Test-Programme([Xml.XmlElement]$node) {
    $n=$node.SelectSingleNode('title')
    $title=if($n){$n.InnerText.Trim()}else{''}
    if(-not $title -or $title -match '(?i)^(no data|no epg|unknown|tba|n/?a|нет данных|немає даних|програма відсутня|программа отсутствует|no program information)\.?\s*$'){
        return $false
    }
    $desc=$node.SelectSingleNode('desc')
    if($desc -and $desc.InnerText -match 'iptv-epg\.org/help'){return $false}
    return $true
}
foreach($file in @($uaGuide,$ruPlaylist)){
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw "Missing input: $file"}
}
$archive=Get-ChildItem -LiteralPath $ruRoot -Recurse -File -Filter 'epg-ru.xml.gz' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if(-not $archive){throw "RU source .xml.gz not found in $ruRoot"}
if($archive.Length -lt 100000){throw 'RU source archive suspiciously small'}
$ruIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($m in [regex]::Matches([IO.File]::ReadAllText($ruPlaylist,[Text.Encoding]::UTF8),'(?im)^#EXTINF:[^\r\n]*tvg-id="([^"]+)"')){
    [void]$ruIds.Add($m.Groups[1].Value)
}
if($ruIds.Count -ne 14){throw "Expected 14 RU channel IDs, got $($ruIds.Count)"}
foreach($id in $map.Values){
    if(-not $ruIds.Contains($id)){throw "RU pilot channel ID missing: $id"}
}
$now=[DateTime]::UtcNow
$from=$now.AddHours(-24)
$until=$now.AddHours(48)
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$runDir=Join-Path $stageRoot ('preview-'+$runId)
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$baselineHash=(Get-FileHash -LiteralPath $uaGuide -Algorithm SHA256).Hash
$baselineCopy=Join-Path $runDir 'UA-published-before-merge.xml'
Copy-Item -LiteralPath $uaGuide -Destination $baselineCopy -ErrorAction Stop

$settings=[Xml.XmlReaderSettings]::new()
$settings.DtdProcessing=[Xml.DtdProcessing]::Ignore
$settings.XmlResolver=$null
$baseReader=[Xml.XmlReader]::Create($baselineCopy,$settings)
try {
    $combined=[Xml.XmlDocument]::new()
    $combined.XmlResolver=$null
    $combined.Load($baseReader)
}finally{$baseReader.Dispose()}
if($combined.DocumentElement.LocalName -ne 'tv'){throw 'UA source not XMLTV'}
$root=$combined.DocumentElement
$baselineChannels=@($combined.SelectNodes('/tv/channel'))
$baselineProgrammes=@($combined.SelectNodes('/tv/programme'))
$existing=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($ch in $baselineChannels){[void]$existing.Add($ch.GetAttribute('id'))}
foreach($id in $map.Values){
    if($existing.Contains($id)){throw "RU channel ID already present in UA EPG: $id"}
}
if($baselineChannels.Count -lt 20 -or $baselineProgrammes.Count -lt 100){
    throw 'UA baseline below content thresholds'
}
$sourceChannels=@{}
$programmes=@{}
$dedup=@{}
foreach($epgId in $map.Keys){
    $programmes[$epgId]=[Collections.Generic.List[object]]::new()
    $dedup[$epgId]=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
}
Write-Host '=== EXISTING UA EPG ==='
Write-Host "Channels: $($baselineChannels.Count); programmes: $($baselineProgrammes.Count)"
Write-Host "Baseline SHA256: $baselineHash"
Write-Host "RU archive: $($archive.FullName)"
Write-Host '=== EXTRACT SIX EXACT RU CHANNELS ==='
$fs=$null;$gz=$null;$xr=$null
try{
    $fs=[IO.File]::OpenRead($archive.FullName)
    $magic=[byte[]]::new(3)
    $n=$fs.Read($magic,0,3);$fs.Position=0
    if($n -ne 3 -or $magic[0] -ne 31 -or $magic[1] -ne 139 -or $magic[2] -ne 8){
        throw 'RU EPG archive is not GZIP'
    }
    $gz=[IO.Compression.GZipStream]::new($fs,[IO.Compression.CompressionMode]::Decompress)
    $xr=[Xml.XmlReader]::Create($gz,$settings)
    while(-not $xr.EOF){
        if($xr.NodeType -eq [Xml.XmlNodeType]::Element -and $xr.LocalName -eq 'channel'){
            $id=$xr.GetAttribute('id')
            if($id -and $map.Contains($id)){
                $outer=$xr.ReadOuterXml()
                $doc=[Xml.XmlDocument]::new();$doc.XmlResolver=$null;$doc.LoadXml($outer)
                $sourceChannels[$id]=$doc.DocumentElement
            }else{$xr.Skip()}
            continue
        }
        if($xr.NodeType -eq [Xml.XmlNodeType]::Element -and $xr.LocalName -eq 'programme'){
            $id=$xr.GetAttribute('channel')
            if($id -and $map.Contains($id)){
                $outer=$xr.ReadOuterXml()
                $doc=[Xml.XmlDocument]::new();$doc.XmlResolver=$null;$doc.LoadXml($outer)
                $p=$doc.DocumentElement
                if(-not (Test-Programme $p)){continue}
                $start=Convert-XmltvUtc $p.GetAttribute('start')
                $stop=Convert-XmltvUtc $p.GetAttribute('stop')
                if($null -eq $start -or $null -eq $stop -or $stop -le $start -or
                    $stop -le $from -or $start -ge $until){continue}
                $title=$p.SelectSingleNode('title').InnerText.Trim()
                $key="$($start.Ticks)|$($stop.Ticks)|$title"
                if($dedup[$id].Add($key)){
                    $programmes[$id].Add([pscustomobject]@{
                        Start=$start;Stop=$stop;Node=$p;Title=$title
                    })
                }
            }else{$xr.Skip()}
            continue
        }
        if(-not $xr.Read()){break}
    }
}finally{
    if($xr){$xr.Dispose()}
    if($gz){$gz.Dispose()}
    if($fs){$fs.Dispose()}
}
$rows=[Collections.Generic.List[object]]::new()
$added=0
$channelCount=0
foreach($epgId in $map.Keys){
    $id=$map[$epgId]
    $items=@($programmes[$epgId].ToArray() | Sort-Object Start)
    $live=@($items | Where-Object {$_.Start -le $now -and $_.Stop -gt $now}).Count -gt 0
    $next24=@($items | Where-Object {$_.Stop -gt $now -and $_.Start -lt $now.AddHours(24)}).Count
    $next48=@($items | Where-Object {$_.Stop -gt $now -and $_.Start -lt $until}).Count
    $rows.Add([pscustomobject]@{
        Channel=$id;SourceId=$epgId;Programmes=$items.Count
        Next24=$next24;Next48=$next48;LiveNow=$live
        First=if($items.Count){$items[0].Title}else{''}
    })
    if($items.Count -eq 0){continue}
    if($sourceChannels.ContainsKey($epgId)){
        $channel=$combined.ImportNode($sourceChannels[$epgId],$true)
        $channel.SetAttribute('id',$id)
    }else{
        $channel=$combined.CreateElement('channel')
        $channel.SetAttribute('id',$id)
        $d=$combined.CreateElement('display-name')
        $d.InnerText=$id
        [void]$channel.AppendChild($d)
    }
    # Insert channels before programme nodes; preserve standard XMLTV order.
    $firstProgramme=$root.SelectSingleNode('programme')
    if($firstProgramme){[void]$root.InsertBefore($channel,$firstProgramme)}
    else{[void]$root.AppendChild($channel)}
    $channelCount++
    foreach($item in $items){
        $copy=$combined.ImportNode($item.Node,$true)
        $copy.SetAttribute('channel',$id)
        [void]$root.AppendChild($copy)
        $added++
    }
}
$preview=Join-Path $runDir 'IPTV-UA-RU-EPG-preview.xml'
$combined.Save($preview)
if((Get-FileHash -LiteralPath $uaGuide -Algorithm SHA256).Hash -ne $baselineHash){
    throw 'Active UA EPG changed during staging: preview requires recheck'
}
$check=[Xml.XmlDocument]::new();$check.XmlResolver=$null
$check.Load($preview)
$allCh=@($check.SelectNodes('/tv/channel')).Count
$allProg=@($check.SelectNodes('/tv/programme')).Count
if($allCh -ne ($baselineChannels.Count+$channelCount) -or
    $allProg -ne ($baselineProgrammes.Count+$added)){throw 'Merged XMLTV count mismatch'}
$report=[ordered]@{
    status='STAGED_NOT_PUBLISHED'
    generatedUtc=$now.ToString('o')
    uaChannels=$baselineChannels.Count
    uaProgrammes=$baselineProgrammes.Count
    ruChannelsWithGuide=$channelCount
    ruPrograms=$added
    totalChannels=$allCh
    totalProgrammes=$allProg
    ruLiveNow=@($rows | Where-Object {$_.LiveNow}).Count
    ruChannelsNext24=@($rows | Where-Object {$_.Next24 -gt 0}).Count
    uaBaselineHash=$baselineHash
    previewHash=(Get-FileHash -LiteralPath $preview -Algorithm SHA256).Hash
    ruArchive=$archive.FullName
    preview=$preview
    details=@($rows)
}
$reportFile=Join-Path $runDir 'report.json'
[IO.File]::WriteAllText($reportFile,($report | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Host '=== RU EPG BY CHANNEL ==='
$rows | Format-Table Channel,Programmes,Next24,Next48,LiveNow,First -AutoSize
Write-Host '=== MERGED PREVIEW SUMMARY ==='
[pscustomobject]@{
    UAChannels=$baselineChannels.Count
    RUChannelsWithGuide=$channelCount
    RUPrograms=$added
    RUChannelsNext24=$report.ruChannelsNext24
    RULiveNow=$report.ruLiveNow
    TotalChannels=$allCh
    TotalProgrammes=$allProg
    Preview=$preview
    Report=$reportFile
    Publication='NONE'
} | Format-List
Write-Host 'UA+RU EPG PREVIEW: COMPLETE (NOT PUBLISHED)'
