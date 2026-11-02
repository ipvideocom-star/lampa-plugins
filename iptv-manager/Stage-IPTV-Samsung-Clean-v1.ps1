#requires -Version 7.0
# Read-only: seven UA groups; RU suspicious-provider review; no publication.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root='C:\IPTV-Manager\public\playlists'
$uaPath=Join-Path $root 'IPTV-UA.m3u'
$ruPath=Join-Path $root 'IPTV-RU-Pilot-v1.m3u'
$allPath=Join-Path $root 'IPTV-UA-RU-Pilot-v1.m3u'
$epgPath=Join-Path $root 'IPTV-UA-RU-EPG-Pilot-v1.xml'
$stageRoot='C:\ReservLampac\IPTVPlus\Playlist-Cleanup'
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$stage=Join-Path $stageRoot ('preview-'+$runId)
$groupMap=@{
    'Украина / General'='Украина / Основные'
    'Украина / Undefined'='Украина / Основные'
    'Украина / News'='Украина / Новости'
    'Украина / Business;News'='Украина / Новости'
    'Украина / Legislative'='Украина / Новости'
    'Украина / Entertainment'='Украина / Кино и развлечения'
    'Украина / Movies'='Украина / Кино и развлечения'
    'Украина / Movies;Series'='Украина / Кино и развлечения'
    'Украина / Series'='Украина / Кино и развлечения'
    'Украина / Music'='Украина / Музыка'
    'Украина / Sports'='Украина / Спорт и активный отдых'
    'Украина / Auto'='Украина / Спорт и активный отдых'
    'Украина / Outdoor'='Украина / Спорт и активный отдых'
    'Украина / Kids'='Украина / Детям'
    'Украина / Religious'='Украина / Познавательные'
    'Украина / Lifestyle'='Украина / Познавательные'
    'Украина / Culture'='Украина / Познавательные'
    'Украина / Science'='Украина / Познавательные'
}
function Read-M3u([string]$path) {
    $content=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    if(-not $content.StartsWith('#EXTM3U')){throw "Invalid playlist header: $path"}
    $list=[Collections.Generic.List[object]]::new()
    $header=''
    foreach($raw in ($content -split '\r?\n')){
        $line=$raw.Trim()
        if(-not $line -or $line -eq '#EXTM3U'){continue}
        if($line.StartsWith('#EXTINF:')){
            if($header){throw "Two adjacent EXTINF lines in $path"}
            $header=$line;continue
        }
        if($line.StartsWith('#')){throw "Unknown stream directive in $path : $line"}
        if(-not $header){throw "URL without EXTINF: $path"}
        $uri=$null
        if(-not [Uri]::TryCreate($line,[UriKind]::Absolute,[ref]$uri)){
            throw "Invalid stream URI in $path"
        }
        $groupMatch=[regex]::Match($header,'(?i)group-title="([^"]*)"')
        $idMatch=[regex]::Match($header,'(?i)tvg-id="([^"]*)"')
        $list.Add([pscustomobject]@{
            Header=$header;Url=$line;Host=$uri.DnsSafeHost.ToLowerInvariant()
            Name=$header.Substring($header.LastIndexOf(',')+1).Trim()
            Group=if($groupMatch.Success){$groupMatch.Groups[1].Value}else{''}
            Id=if($idMatch.Success){$idMatch.Groups[1].Value}else{''}
        })
        $header=''
    }
    if($header){throw "Last EXTINF missing stream: $path"}
    return ,$list
}
function Changed-Group([object]$item,[string]$group) {
    $text=[regex]::Replace($item.Header,'(?i)\s+group-title="[^"]*"','')
    $comma=$text.LastIndexOf(',')
    if($comma -lt 0){throw "Invalid EXTINF title: $($item.Name)"}
    [pscustomobject]@{
        Header=$text.Substring(0,$comma)+' group-title="'+$group+'"'+$text.Substring($comma)
        Url=$item.Url;Name=$item.Name;Id=$item.Id;Host=$item.Host;Group=$group
    }
}
function Write-M3u([string]$path,[object[]]$items){
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add('#EXTM3U')
    foreach($item in $items){
        $lines.Add($item.Header)
        $lines.Add($item.Url)
    }
    $nl=[Environment]::NewLine
    [IO.File]::WriteAllText($path,($lines -join $nl)+$nl,[Text.UTF8Encoding]::new($false))
}
function Ru-Group([string]$name){
    if($name -match '(?i)kino|cinema|dorama|fox|bollywood|priklyucheniya|premialnoe|star family|star cinema'){
        return 'Россия / Кино и сериалы'
    }
    if($name -match '(?i)music|muzyka|songtv|viva'){
        return 'Россия / Музыка'
    }
    return 'Россия / Остальные'
}
$hashes=@{}
foreach($file in @($uaPath,$ruPath,$allPath,$epgPath)){
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw "Missing: $file"}
    $hashes[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
}
$ua=(Read-M3u $uaPath).ToArray()
$ru=(Read-M3u $ruPath).ToArray()
$all=(Read-M3u $allPath).ToArray()
if($ua.Count -ne 84 -or $ru.Count -ne 47 -or $all.Count -ne 131){
    throw "Unexpected channel counts: UA=$($ua.Count) RU=$($ru.Count) combined=$($all.Count)"
}
$expected=@($ua)+@($ru)
for($i=0;$i -lt $all.Count;$i++){
    if($expected[$i].Url -cne $all[$i].Url -or $expected[$i].Id -cne $all[$i].Id){
        throw "Combined playlist differs from UA+RU ordering at entry $i"
    }
}
$uaNew=[Collections.Generic.List[object]]::new()
foreach($item in $ua){
    if(-not $groupMap.ContainsKey($item.Group)){throw "Unknown UA group: $($item.Group)"}
    $uaNew.Add((Changed-Group $item $groupMap[$item.Group]))
}
$groups=@($uaNew | Group-Object Group)
if($groups.Count -ne 7){throw "Expected 7 UA groups, got $($groups.Count)"}
$ruNew=[Collections.Generic.List[object]]::new()
$ruReview=[Collections.Generic.List[object]]::new()
foreach($item in $ru){
    $suspect=($item.Host -eq 'cinerama.uz') -or
        $item.Host.EndsWith('.cinerama.uz') -or
        ($item.Host -eq 'cdn4.skygo.mn')
    if($suspect){
        $ruReview.Add((Changed-Group $item 'RU / Проверить источник'))
    }else{
        $ruNew.Add((Changed-Group $item (Ru-Group $item.Name)))
    }
}
if($ruNew.Count+$ruReview.Count -ne 47){throw 'RU count mismatch'}
$combinedNew=@($uaNew.ToArray())+@($ruNew.ToArray())
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$previewUA=Join-Path $stage 'UA-7-GROUPS-PREVIEW.m3u'
$previewRU=Join-Path $stage 'RU-CLEAN-CANDIDATES-PREVIEW.m3u'
$previewAll=Join-Path $stage 'UA-RU-CLEAN-PREVIEW.m3u'
$reviewFile=Join-Path $stage 'RU-SUSPECT-REVIEW.m3u'
Write-M3u $previewUA $uaNew.ToArray()
Write-M3u $previewRU $ruNew.ToArray()
Write-M3u $previewAll $combinedNew
Write-M3u $reviewFile $ruReview.ToArray()
$reportFile=Join-Path $stage 'report.json'
$report=[ordered]@{
    Status='PREVIEW_NOT_PUBLISHED';CreatedUtc=[DateTime]::UtcNow.ToString('o')
    Existing=@{UA=84;RU=47;Combined=131}
    Preview=@{UA=$uaNew.Count;RU=$ruNew.Count;Combined=$combinedNew.Count}
    RuNeedsReview=$ruReview.Count
    UAGroupCounts=@($groups | Select-Object Name,Count)
    RUReview=@($ruReview | Select-Object Name,Id,Host)
    SourceSha256=$hashes
    Files=@{UA=$previewUA;RU=$previewRU;Combined=$previewAll;Review=$reviewFile}
}
[IO.File]::WriteAllText($reportFile,($report|ConvertTo-Json -Depth 7),
    [Text.UTF8Encoding]::new($false))
foreach($file in $hashes.Keys){
    if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $hashes[$file]){
        throw "Published file changed during staging: $file"
    }
}
Write-Host '=== UA GROUPING PREVIEW ==='
$groups | Sort-Object Count -Descending | Select-Object Count,Name | Format-Table -AutoSize
Write-Host '=== RU SUSPECT HOSTS (NOT CONFIRMED BAD) ==='
$ruReview | Group-Object Host | Select-Object Count,Name | Format-Table -AutoSize
Write-Host '=== RU CLEAN-CANDIDATE GROUPS (NOT TV VERIFIED) ==='
$ruNew | Group-Object Group | Select-Object Count,Name | Format-Table -AutoSize
[pscustomobject]@{
    UAChannels=$uaNew.Count
    UAGroups=$groups.Count
    RUCandidateChannels=$ruNew.Count
    RUSuspectReview=$ruReview.Count
    CombinedPreviewChannels=$combinedNew.Count
    PreviewFolder=$stage
    Report=$reportFile
    Publication='NONE'
    Active131AndEpg='UNCHANGED'
} | Format-List
Write-Host 'IPTV CLEAN STAGING: COMPLETE (NOT PUBLISHED)'
