#requires -Version 7.0
# IPTV Manager: stage 124-channel review playlist, without publishing.
# Only the seven distinct channel entries proven to share the exact same
# Cinerama media HLS URL/body are parked in a separate review playlist.
# Preserves 84 UA entries, 40 other RU entries and all per-channel M3U options.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$playlistRoot='C:\IPTV-Manager\public\playlists'
$ruFile=Join-Path $playlistRoot 'IPTV-RU-Pilot-v1.m3u'
$uaFile=Join-Path $playlistRoot 'IPTV-UA.m3u'
$allFile=Join-Path $playlistRoot 'IPTV-UA-RU-Pilot-v1.m3u'
$reportFile='C:\ReservLampac\IPTVPlus\Cinerama-Diagnostics\routes-20261102-184701-01ecb91b\report.json'
$outputRoot='C:\ReservLampac\IPTVPlus\Cinerama-Diagnostics'
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$outputDir=Join-Path $outputRoot ('quarantine-preview-'+$runId)
$expectedNames=@(
    'Ohotnik i rybolov (576i)'
    'Tochka otryva (576p)'
    'Trace Sport Stars Russia (720p)'
    'Priklyucheniya (576p)'
    'TV Centr International (576p)'
    'V gostyakh u skazki (1080p)'
    'Nashe Novoe Kino'
)
function Read-M3u([string]$path){
    $lines=[IO.File]::ReadAllLines($path,[Text.Encoding]::UTF8)
    if($lines.Count -lt 3 -or
       $lines[0].TrimStart([char]0xFEFF) -cne '#EXTM3U'){
        throw "Unexpected playlist header: $path"
    }
    $entries=[Collections.Generic.List[object]]::new()
    $block=[Collections.Generic.List[string]]::new()
    $header=''
    for($i=1;$i -lt $lines.Count;$i++){
        $line=$lines[$i].Trim()
        if(-not $line){continue}
        if($line.StartsWith('#EXTINF:')){
            if($header){throw "Multiple EXTINF lines: $path"}
            $block.Clear()
            $header=$line
            $block.Add($line)
            continue
        }
        if($line.StartsWith('#')){
            if(-not $header){throw "Unexpected line before EXTINF in $path"}
            $block.Add($line)
            continue
        }
        if(-not $header){throw "URL without EXTINF in $path"}
        $uri=$null
        if(-not [Uri]::TryCreate($line,[UriKind]::Absolute,[ref]$uri) -or
           $uri.Scheme -notin @('http','https')){
            throw "Invalid URL in $path"
        }
        $block.Add($line)
        $idMatch=[regex]::Match($header,'(?i)tvg-id="([^"]*)"')
        $groupMatch=[regex]::Match($header,'(?i)group-title="([^"]*)"')
        $name=$header.Substring($header.LastIndexOf(',')+1).Trim()
        $entries.Add([pscustomobject]@{
            Name=$name
            Id=if($idMatch.Success){$idMatch.Groups[1].Value}else{''}
            Group=if($groupMatch.Success){$groupMatch.Groups[1].Value}else{''}
            Host=$uri.DnsSafeHost.ToLowerInvariant()
            Lines=@($block.ToArray())
            Url=$line
        })
        $block.Clear()
        $header=''
    }
    if($header){throw "Trailing incomplete channel in $path"}
    return ,$entries
}
function Save-M3u([string]$path,[object[]]$entries){
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add('#EXTM3U')
    foreach($item in $entries){
        foreach($line in $item.Lines){$lines.Add([string]$line)}
    }
    $newLine=[Environment]::NewLine
    [IO.File]::WriteAllText($path,($lines -join $newLine)+$newLine,
        [Text.UTF8Encoding]::new($false))
}
function Digest([string]$path){
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
foreach($path in @($ruFile,$uaFile,$allFile,$reportFile)){
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){
        throw "Input not found: $path"
    }
}
$hashes=@{}
foreach($path in @($ruFile,$uaFile,$allFile)){
    $hashes[$path]=Digest $path
}
$source=Get-Content -LiteralPath $reportFile -Raw -Encoding UTF8 |
    ConvertFrom-Json -AsHashtable
if($source.Status -ne 'READ_ONLY_DIAGNOSTIC' -or
    [int]$source.Total -ne 22 -or [int]$source.Verified -ne 22 -or
    [string]$source.SourceSHA256 -ne $hashes[$ruFile]){
    throw 'Source route audit is incomplete or RU playlist changed since audit'
}
$groups=@($source.SharedFeedGroups)
if($groups.Count -ne 1 -or
   [int]$groups[0].Count -ne 7 -or
   [string]$groups[0].MediaUrlHash -ne 'AA9C634AF72E'){
    throw 'Shared Cinerama feed grouping does not match verified diagnostic'
}
$reportNames=@($groups[0].Channels | Sort-Object)
$expectedSorted=@($expectedNames | Sort-Object)
if(($reportNames -join [char]10) -cne ($expectedSorted -join [char]10)){
    throw 'Unexpected channel membership in shared feed group'
}
$proof=@($source.Results | Where-Object {
    $_.MediaUrlHash -eq 'AA9C634AF72E' -and
    $_.MediaBodyHash -eq 'C9544A31E093' -and
    $_.Status -eq 'MEDIA_MANIFEST'
})
if($proof.Count -ne 7){
    throw 'Seven shared endpoints do not all share the same media body fingerprint'
}
$ua=(Read-M3u $uaFile).ToArray()
$ru=(Read-M3u $ruFile).ToArray()
$all=(Read-M3u $allFile).ToArray()
if($ua.Count -ne 84 -or $ru.Count -ne 47 -or $all.Count -ne 131){
    throw "Unexpected published counts: UA=$($ua.Count) RU=$($ru.Count) combined=$($all.Count)"
}
$expected=@($ua)+@($ru)
for($i=0;$i -lt 131;$i++){
    if(($all[$i].Lines -join [char]10) -cne
       ($expected[$i].Lines -join [char]10)){
        throw "Combined M3U differs from UA followed by RU at channel $i"
    }
}
$names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($name in $expectedNames){[void]$names.Add($name)}
$keep=[Collections.Generic.List[object]]::new()
$quarantine=[Collections.Generic.List[object]]::new()
foreach($channel in $ru){
    if($names.Contains($channel.Name)){
        if($channel.Host -ne 'stream8.cinerama.uz'){
            throw "Shared-feed host changed for $($channel.Name)"
        }
        $quarantine.Add($channel)
    }else{
        $keep.Add($channel)
    }
}
if($keep.Count -ne 40 -or $quarantine.Count -ne 7){
    throw "Unexpected split: keep=$($keep.Count); quarantine=$($quarantine.Count)"
}
$preview=@($ua)+@($keep.ToArray())
if($preview.Count -ne 124){throw 'Combined preview count is not 124'}
$uaOptions=@($ua | ForEach-Object {$_.Lines} |
    Where-Object {$_ -match '^#EXTVLCOPT:'}).Count
if($uaOptions -ne 35){throw "Expected 35 UA HTTP options, found $uaOptions"}
foreach($path in $hashes.Keys){
    if((Digest $path) -ne $hashes[$path]){
        throw "Published M3U changed during staging: $path"
    }
}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$ruPreview=Join-Path $outputDir 'RU-40-PREVIEW.m3u'
$combinedPreview=Join-Path $outputDir 'UA-RU-124-PREVIEW.m3u'
$quarantineFile=Join-Path $outputDir 'RU-7-SHARED-FEED-REVIEW.m3u'
Save-M3u $ruPreview $keep.ToArray()
Save-M3u $combinedPreview $preview
Save-M3u $quarantineFile $quarantine.ToArray()
$metadata=[ordered]@{
    Status='PREVIEW_ONLY_NO_PUBLICATION'
    ProducedUtc=[DateTime]::UtcNow.ToString('o')
    OriginReport=$reportFile
    SharedMediaUrlHash='AA9C634AF72E'
    SharedMediaBodyHash='C9544A31E093'
    OriginalCounts=@{UA=84;RU=47;Combined=131}
    CandidateCounts=@{UA=84;RU=40;Combined=124;Quarantine=7}
    UA_HTTP_Options_Preserved=$uaOptions
    LiveSha256=$hashes
    Files=@{
        RU=$ruPreview;Combined=$combinedPreview;Quarantine=$quarantineFile
    }
    ReviewChannels=@($quarantine | Select-Object Name,Id,Host)
}
$previewReport=Join-Path $outputDir 'report.json'
[IO.File]::WriteAllText($previewReport,
    ($metadata|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
foreach($path in $hashes.Keys){
    if((Digest $path) -ne $hashes[$path]){
        throw "Live playlist changed during staging: $path"
    }
}
Write-Host '=== CONFIRMED SHARED-FEED CHANNELS (PARKED IN PREVIEW ONLY) ==='
$quarantine | Select-Object Name,Host | Format-Table -AutoSize
Write-Host '=== STAGED PREVIEW (NOT PUBLISHED) ==='
[pscustomobject]@{
    OriginalUA=84
    OriginalRU=47
    OriginalCombined=131
    CandidateRU=40
    CandidateCombined=124
    SharedFeedReview=7
    UAHttpOptionsPreserved=35
    PreviewFolder=$outputDir
    Report=$previewReport
    Publication='NONE'
    LivePlaylists='UNCHANGED'
    LiveEPG='UNCHANGED'
} | Format-List
Write-Host 'CINERAMA SHARED-FEED PREVIEW: COMPLETE'
