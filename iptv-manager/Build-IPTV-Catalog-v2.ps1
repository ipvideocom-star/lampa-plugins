#requires -Version 7.0
# IPTV Manager v2 M1: read-only RU source catalog.
# Join stable iptv-org API IDs, raw RU entries and Free-TV entries.
# No live playlist, plugin, EPG or Task Scheduler writes.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$ruFile='C:\IPTV-Manager\public\playlists\IPTV-RU-Pilot-v1.m3u'
$root='C:\ReservLampac\IPTVPlus\CatalogV2'
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$dir=Join-Path $root ('catalog-'+$stamp)
$urls=@(
    [pscustomobject]@{Name='channels';URL='https://iptv-org.github.io/api/channels.json';File='channels.json';Required=$true}
    [pscustomobject]@{Name='streams';URL='https://iptv-org.github.io/api/streams.json';File='streams.json';Required=$true}
    [pscustomobject]@{Name='raw-ru';URL='https://iptv-org.github.io/iptv/raw/ru.m3u';File='raw-ru.m3u';Required=$false}
    [pscustomobject]@{Name='freetv';URL='https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8';File='freetv.m3u8';Required=$false}
)
function CanonicalId([string]$id) {
    if(-not $id){return ''}
    return ($id -split '@')[0].Trim()
}
function ShortHash([string]$s) {
    $b=[Text.Encoding]::UTF8.GetBytes($s)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b)).Substring(0,12)
}
function Parse-Entries([string]$path) {
    $entries=[Collections.Generic.List[object]]::new()
    $header=''
    foreach($raw in [IO.File]::ReadLines($path,[Text.Encoding]::UTF8)) {
        $line=$raw.Trim()
        if($line.StartsWith('#EXTINF:')){$header=$line;continue}
        if(-not $header -or -not $line -or $line.StartsWith('#')){continue}
        $uri=$null
        if([Uri]::TryCreate($line,[UriKind]::Absolute,[ref]$uri) -and
            $uri.Scheme -in @('http','https')){
            $id=[regex]::Match($header,'(?i)tvg-id="([^"]*)"')
            $entries.Add([pscustomobject]@{
                Id=if($id.Success){CanonicalId $id.Groups[1].Value}else{''}
                Name=$header.Substring($header.LastIndexOf(',')+1).Trim()
                URL=$line
                Host=$uri.DnsSafeHost.ToLowerInvariant()
            })
        }
        $header=''
    }
    return ,$entries
}
function Is-SuspectHost([string]$hostName) {
    foreach($bad in @('cinerama.uz','skygo.mn')){
        if($hostName -eq $bad -or $hostName.EndsWith('.'+$bad)){return $true}
    }
    return $false
}
if(-not (Test-Path -LiteralPath $ruFile -PathType Leaf)){throw "RU M3U missing: $ruFile"}
$before=(Get-FileHash -LiteralPath $ruFile -Algorithm SHA256).Hash
$original=(Parse-Entries $ruFile).ToArray()
if($original.Count -ne 47){throw "Expected 47 current RU channels, found $($original.Count)"}
$lookup=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($item in $original){
    if($item.Id -and -not $lookup.ContainsKey($item.Id)){
        $lookup[$item.Id]=[Collections.Generic.List[object]]::new()
    }
}
if($lookup.Count -lt 30){throw 'Insufficient stable channel IDs for trustworthy matching'}
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$downloadReport=[Collections.Generic.List[object]]::new()
Write-Host '=== DOWNLOAD IPTV MANAGER V2 SOURCE CATALOGS ==='
foreach($source in $urls){
    $target=Join-Path $dir $source.File
    & curl.exe -fLsS --connect-timeout 10 --max-time 90 --max-filesize 40000000 -o $target $source.URL
    $exitCode=$LASTEXITCODE
    $good=$exitCode -eq 0 -and (Test-Path -LiteralPath $target -PathType Leaf)
    $bytes=if($good){(Get-Item -LiteralPath $target).Length}else{0}
    $good=$good -and $bytes -ge 100
    if(-not $good -and $source.Required){throw "Required source $($source.Name) unavailable (curl $exitCode)"}
    if(-not $good){Write-Warning "Optional source $($source.Name) unavailable"}
    $downloadReport.Add([pscustomobject]@{Name=$source.Name;Available=$good;Bytes=$bytes})
    Write-Host "$($source.Name): $bytes bytes"
}
$knownChannels=Get-Content -LiteralPath (Join-Path $dir 'channels.json') -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
$apiStreams=Get-Content -LiteralPath (Join-Path $dir 'streams.json') -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
$meta=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($item in $knownChannels){
    if(-not $item.id -or $item.is_nsfw -eq $true -or $item.closed){continue}
    $meta[[string]$item.id]=$item
}
$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
function Add-Candidate {
    param([string]$Id,[string]$URL,[string]$Source,[string]$Quality,
          [string]$Agent,[string]$Referrer)
    if(-not $Id -or -not $lookup.ContainsKey($Id) -or -not $meta.ContainsKey($Id)){return}
    $uri=$null
    if(-not [Uri]::TryCreate($URL,[UriKind]::Absolute,[ref]$uri) -or
        $uri.Scheme -notin @('http','https') -or $uri.UserInfo){return}
    $hostName=$uri.DnsSafeHost.ToLowerInvariant()
    if(Is-SuspectHost $hostName){return}
    if($hostName -notmatch '\.'){return}
    $key=$Id+'|'+$URL
    if(-not $seen.Add($key)){return}
    $lookup[$Id].Add([pscustomobject]@{
        Id=$Id;Source=$Source;URL=$URL;URLHash=(ShortHash $URL)
        Host=$hostName;Quality=$Quality
        UserAgent=$Agent;Referrer=$Referrer
        HlsTested=$false;ContentVerified=$false
    })
}
Write-Host '=== INDEX CANONICAL IPTV-ORG STREAMS ==='
$matched=0
foreach($stream in $apiStreams){
    $id=CanonicalId ([string]$stream.channel)
    if(-not $id -or -not $lookup.ContainsKey($id)){continue}
    $matched++
    Add-Candidate -Id $id -URL ([string]$stream.url) -Source 'iptv-org/api' -Quality ([string]$stream.quality) -Agent ([string]$stream.user_agent) -Referrer ([string]$stream.referrer)
}
Write-Host "API stream entries matched to existing channel IDs: $matched"
foreach($spec in @(
    [pscustomobject]@{File='raw-ru.m3u';Source='iptv-org/raw/ru'}
    [pscustomobject]@{File='freetv.m3u8';Source='Free-TV'}
)){
    $path=Join-Path $dir $spec.File
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){continue}
    $entries=(Parse-Entries $path).ToArray()
    $count=0
    foreach($item in $entries){
        if(-not $item.Id -or -not $lookup.ContainsKey($item.Id)){continue}
        $count++
        Add-Candidate -Id $item.Id -URL $item.URL -Source $spec.Source -Quality '' -Agent '' -Referrer ''
    }
    Write-Host "$($spec.Source): $count matching entries"
}
$catalog=[Collections.Generic.List[object]]::new()
$summary=[Collections.Generic.List[object]]::new()
foreach($channel in $original){
    $alternatives=@()
    if($channel.Id -and $lookup.ContainsKey($channel.Id)){
        $alternatives=@($lookup[$channel.Id].ToArray() | Where-Object {$_.URL -cne $channel.URL})
    }
    $independent=@($alternatives | Where-Object {$_.Host -cne $channel.Host})
    $details=$null
    if($channel.Id -and $meta.ContainsKey($channel.Id)){$details=$meta[$channel.Id]}
    $catalog.Add([pscustomobject]@{
        Id=$channel.Id;Name=$channel.Name
        CurrentHost=$channel.Host;CurrentURLHash=(ShortHash $channel.URL)
        Country=if($details){$details.country}else{''}
        Aliases=if($details){@($details.alt_names)}else{@()}
        Alternatives=$alternatives
    })
    $summary.Add([pscustomobject]@{
        Channel=$channel.Name;CurrentHost=$channel.Host
        AlternativeURLs=$alternatives.Count
        IndependentProviders=@($independent.Host | Sort-Object -Unique).Count
    })
}
if((Get-FileHash -LiteralPath $ruFile -Algorithm SHA256).Hash -ne $before){
    throw 'Live RU M3U changed during catalog processing'
}
$catalogPath=Join-Path $dir 'channel-catalog.json'
$reportPath=Join-Path $dir 'report.json'
[IO.File]::WriteAllText($catalogPath,($catalog | ConvertTo-Json -Depth 9),[Text.UTF8Encoding]::new($false))
$available=@($summary | Where-Object {$_.AlternativeURLs -gt 0})
$stats=[ordered]@{
    Status='READ_ONLY_CATALOG'
    BaselineRU=47
    BaselineSha256=$before
    ExactBaselineIds=$lookup.Count
    ApiMatchedStreams=$matched
    ChannelsWithAlternativeURLs=$available.Count
    ChannelsWithIndependentProviders=@($summary | Where-Object {$_.IndependentProviders -gt 0}).Count
    TotalAlternativeURLs=($summary | Measure-Object AlternativeURLs -Sum).Sum
    Sources=@($downloadReport)
    CatalogPath=$catalogPath
    PublishedPlaylist='UNCHANGED'
}
[IO.File]::WriteAllText($reportPath,($stats|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Host '=== RU CHANNELS WITH MOST ALTERNATIVE URLS ==='
$summary | Sort-Object AlternativeURLs -Descending | Select-Object -First 20 Channel,AlternativeURLs,IndependentProviders,CurrentHost | Format-Table -AutoSize
Write-Host '=== CATALOG SUMMARY ==='
[pscustomobject]@{
    RUChannels=47
    ChannelsWithAlternatives=$available.Count
    IndependentProviderCoverage=@($summary | Where-Object {$_.IndependentProviders -gt 0}).Count
    TotalAlternativeURLs=($summary | Measure-Object AlternativeURLs -Sum).Sum
    Report=$reportPath;Catalog=$catalogPath
    Publication='NONE'
} | Format-List
Write-Host 'IPTV MANAGER V2: CANONICAL CATALOG BUILT (NOT PUBLISHED)'
