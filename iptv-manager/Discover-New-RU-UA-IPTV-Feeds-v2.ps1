#requires -Version 7.0
# IPTV Manager v2 - bounded discovery of public/free RU-UA-RUS IPTV M3U feed candidates.
# MAIN W2022 ONLY. Fetches only 5 public playlist text files; does NOT fetch stream media.
# Never modifies production M3U, Agent, 3proxy, Caddy, Lampac or scheduled jobs.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
if(-not $IsWindows -or $PSVersionTable.PSVersion.Major -lt 7){throw 'PowerShell 7 on W2022 required'}
$os=(Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption
if($os -notmatch '2022'){throw "Wrong host OS: $os"}
$root='C:\IPTV-Manager'
$catalog=Join-Path $root 'data\catalog-raw.m3u'
$export=Join-Path $root 'data\IPTV-verified-814-20261031-092455-769.json'
$pilot=Join-Path $root 'public\playlists\IPTV-UA-RU-Pilot-v1.m3u'
$outdir='C:\ReservLampac\IPTVPlus\Discovery'
$expectedCatalog='4FBEE8A643CDE432EFBE927C3F6C1714134BA6F3D1E9F51105857848819ACA36'
$expectedExport='82ACF6A103C6D7BE6B91332A0FA04E14425A0187E2A64D55A68AE48499BDCF59'
$expectedPilot='A2F9B549425FF8D6B925E0CFD0E8B515B78ED5F2DC83C130986259D24AFFB875'
$feeds=@(
  [pscustomobject]@{Id='NGRCH-RU';Scope='CURATED_RU';Url='https://raw.githubusercontent.com/ngrch/iptv/main/ru.m3u'},
  [pscustomobject]@{Id='NGRCH-MUSIC';Scope='CURATED_RU';Url='https://raw.githubusercontent.com/ngrch/iptv/main/music.m3u'},
  [pscustomobject]@{Id='DENXVO-FULL';Scope='CURATED_RU_UA';Url='https://raw.githubusercontent.com/denxvofficial/IPTV/main/iptv.m3u'},
  [pscustomobject]@{Id='FREE-TV-GLOBAL';Scope='FILTER_BY_METADATA';Url='https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8'},
  [pscustomobject]@{Id='FREECAST-GLOBAL';Scope='FILTER_BY_METADATA';Url='https://raw.githubusercontent.com/freecasthub/public-iptv/main/playlist.m3u'}
)
function HashFull([string]$s){
  [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($s)))
}
function Hash16([string]$s){(HashFull $s).Substring(0,16)}
function MetaAttr([string]$line,[string]$key){
  $m=[regex]::Match($line,'(?i)(?:^|\s)'+[regex]::Escape($key)+'="([^"]*)"')
  if($m.Success){return $m.Groups[1].Value}
  return ''
}
function Get-ChannelName([string]$meta){
  $quoted=$false
  for($i=0;$i -lt $meta.Length;$i++){
    if($meta[$i] -eq '"'){$quoted=-not $quoted}
    elseif($meta[$i] -eq ',' -and -not $quoted){
      return $meta.Substring($i+1).Trim()
    }
  }
  return ''
}
function NameKey([string]$s){
  $n=$s.Replace('Ⓢ','').Replace('Ⓖ','').Replace('Ⓨ','').Normalize([Text.NormalizationForm]::FormKC)
  $n=[regex]::Replace($n,'(?i)\s*(?:\[[^\]]*\]|\((?:\d{3,4}\s*[pi]|4k|hd|sd)\))\s*$','')
  $n=$n.Replace('ё','е').Replace('Ё','Е')
  ([regex]::Replace($n.ToLowerInvariant(),'[^\p{L}\p{Nd}]+',' ')).Trim()
}
function ParseM3U([string]$text,[string]$source){
  $entries=[Collections.Generic.List[object]]::new()
  $header=$null;$agent='';$referrer=''
  foreach($raw in ($text -split '\r?\n')){
    $line=$raw.Trim()
    if($line.StartsWith('#EXTINF:')){$header=$line;$agent='';$referrer='';continue}
    if($null -eq $header -or -not $line){continue}
    if($line -match '(?i)^#EXTVLCOPT:http-user-agent=(.*)$'){$agent=$Matches[1];continue}
    if($line -match '(?i)^#EXTVLCOPT:http-referrer=(.*)$'){$referrer=$Matches[1];continue}
    if($line.StartsWith('#')){continue}
    $uri=$null
    $valid=[Uri]::TryCreate($line,[UriKind]::Absolute,[ref]$uri)
    if($valid -and $uri.Scheme -in @('http','https') -and -not $uri.UserInfo -and
       -not ($uri.DnsSafeHost -match '(?i)(^localhost$|^127\.|^10\.|^192\.168\.|\.local$)')){
      $name=Get-ChannelName $header
      if($name -and $name.Length -le 220 -and $header.Length -le 16384 -and $line.Length -le 4096){
        $id=MetaAttr $header 'tvg-id'
        $country=MetaAttr $header 'tvg-country'
        $language=MetaAttr $header 'tvg-language'
        $group=MetaAttr $header 'group-title'
        $entries.Add([pscustomobject]@{
          Feed=$source;Channel=$name;NameKey=(NameKey $name)
          TvgID=$id;Country=$country;Language=$language;Group=$group
          URL=$line;URLKey=(Hash16 $line);UserAgent=$agent;Referrer=$referrer
        })
      }
    }
    $header=$null
  }
  return $entries.ToArray()
}
function Is-Relevant($x,[string]$scope){
  $content=($x.Channel+' '+$x.Group+' '+$x.Country+' '+$x.Language+' '+$x.TvgID)
  if($content -match '(?i)\b(adult|porn|xxx|18\+|erotic|sexcam|casino|betting|gambling)\b'){return $false}
  $path=$null
  try{$path=([Uri]$x.URL).AbsolutePath}catch{return $false}
  if($path -match '(?i)\.(?:mp4|mkv|mov|avi|mp3|aac|flv|webm)$'){return $false}
  if($scope -eq 'FILTER_BY_METADATA'){
    return ($content -match '(?i)(russia|russian|ukraine|ukrainian|belarus|kazakh|moldova|рус|росси|укра|белар|казах|молдов|(?:^|[.@ ,;])(?:ru|rus|ua|ukr)(?:$|[.@ ,;]))')
  }
  return $true
}
function FetchFeed($url){
  $uri=[Uri]$url
  if($uri.Scheme -cne 'https' -or $uri.DnsSafeHost -cne 'raw.githubusercontent.com' -or
     $uri.UserInfo -or $uri.Port -ne 443){throw 'Unexpected discovery feed endpoint'}
  $handler=[Net.Http.HttpClientHandler]::new()
  $handler.AllowAutoRedirect=$false
  $handler.UseProxy=$false
  $handler.UseCookies=$false
  $client=[Net.Http.HttpClient]::new($handler)
  $client.Timeout=[TimeSpan]::FromSeconds(35)
  $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,$uri)
  $response=$null;$stream=$null;$memory=$null
  try{
    $request.Headers.UserAgent.ParseAdd('IPTV-Manager-SourceDiscovery/1.0')
    $response=$client.SendAsync($request,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    if([int]$response.StatusCode -ne 200){throw "FEED_HTTP_$([int]$response.StatusCode)"}
    if($response.Content.Headers.ContentLength -and
       [long]$response.Content.Headers.ContentLength -gt 8388608){throw 'FEED_TOO_LARGE'}
    $stream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $memory=[IO.MemoryStream]::new()
    $buffer=[byte[]]::new(32768)
    while($true){
      $n=$stream.Read($buffer,0,$buffer.Length)
      if($n -le 0){break}
      if($memory.Length+$n -gt 8388608){throw 'FEED_TOO_LARGE'}
      $memory.Write($buffer,0,$n)
    }
    $text=[Text.Encoding]::UTF8.GetString($memory.ToArray()).TrimStart([char]0xFEFF)
    if(-not $text.StartsWith('#EXTM3U')){throw 'NOT_AN_M3U_PLAYLIST'}
    return $text
  }finally{
    if($null -ne $memory){$memory.Dispose()}
    if($null -ne $stream){$stream.Dispose()}
    if($null -ne $response){$response.Dispose()}
    $request.Dispose();$client.Dispose();$handler.Dispose()
  }
}
foreach($f in @($catalog,$export,$pilot)){
  if(-not(Test-Path -LiteralPath $f -PathType Leaf)){throw "Missing production reference: $f"}
}
if((Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash -cne $expectedCatalog -or
   (Get-FileHash -LiteralPath $export -Algorithm SHA256).Hash -cne $expectedExport -or
   (Get-FileHash -LiteralPath $pilot -Algorithm SHA256).Hash -cne $expectedPilot){
  throw 'Known baseline checksum mismatch. Existing files NOT altered.'
}
$oldJson=Get-Content -LiteralPath $export -Raw -Encoding UTF8|ConvertFrom-Json -AsHashtable
if($oldJson.schemaVersion -ne 1 -or $oldJson.node -cne 'W2019S' -or
   $oldJson.verifiedCount -ne 814 -or $oldJson.confirmedCount -ne 347){
  throw 'Unexpected W2019S export reference'
}
$oldConfirmed=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($r in $oldJson.records){
  if($r.confirmed){[void]$oldConfirmed.Add([string]$r.urlKey)}
}
$oldEntries=@(ParseM3U ([IO.File]::ReadAllText($catalog,[Text.Encoding]::UTF8)) 'ORIGINAL_814')
$pilotEntries=@(ParseM3U ([IO.File]::ReadAllText($pilot,[Text.Encoding]::UTF8)) 'PUBLISHED_PILOT_131')
$oldUrls=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$pilotUrls=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$knownNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$knownIDs=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($e in $oldEntries){
  [void]$oldUrls.Add($e.URLKey)
  if($e.NameKey){[void]$knownNames.Add($e.NameKey)}
  if($e.TvgID){[void]$knownIDs.Add($e.TvgID)}
}
foreach($e in $pilotEntries){
  [void]$pilotUrls.Add($e.URLKey)
  if($e.NameKey){[void]$knownNames.Add($e.NameKey)}
  if($e.TvgID){[void]$knownIDs.Add($e.TvgID)}
}
if($oldUrls.Count -ne 814 -or $oldConfirmed.Count -ne 347 -or
   $pilotEntries.Count -ne 131){throw 'Catalog 814, W2019S 347 or pilot 131 integrity mismatch'}
Write-Host '=== DISCOVER ADDITIONAL RU / UA / RUS IPTV FEEDS ==='
Write-Host 'Baseline: 814 historical URLs; 347 confirmed on W2019S; pilot: 131 entries'
Write-Host 'Only downloading bounded M3U TEXT from five public GitHub feeds; no video-stream requests'
$collected=[Collections.Generic.List[object]]::new()
$sourceStats=[Collections.Generic.List[object]]::new()
$seenAcrossFeeds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$feedSucceeded=0
foreach($feed in $feeds){
  $status='OK';$entries=@();$eligible=@();$novel=0;$existing=0;$duplicates=0;$errorType=''
  try{
    $content=FetchFeed $feed.Url
    $entries=@(ParseM3U $content $feed.Id)
    $eligible=@($entries|Where-Object {Is-Relevant $_ $feed.Scope})
    $feedSHA=HashFull $content
    foreach($e in $eligible){
      if(-not $seenAcrossFeeds.Add($e.URLKey)){$duplicates++;continue}
      if($oldUrls.Contains($e.URLKey) -or $pilotUrls.Contains($e.URLKey)){
        $existing++;continue
      }
      $match=if($e.TvgID -and $knownIDs.Contains($e.TvgID)){'ALTERNATIVE_EXISTING_TVGID'}
        elseif($e.NameKey -and $knownNames.Contains($e.NameKey)){'ALTERNATIVE_EXISTING_NAME'}
        else{'POTENTIAL_NEW_CHANNEL_NAME'}
      $collected.Add([pscustomobject]@{
        Feed=$feed.Id;RegionHint=$feed.Scope
        Channel=$e.Channel;NameKey=$e.NameKey;TvgID=$e.TvgID
        Group=$e.Group;Country=$e.Country;Language=$e.Language
        URLKey=$e.URLKey;URL=$e.URL
        UserAgent=$e.UserAgent;Referrer=$e.Referrer
        Classification=$match
      })
      $novel++
    }
    $feedSucceeded++
    $sourceStats.Add([pscustomobject]@{
      Source=$feed.Id;Status='OK';Parsed=$entries.Count;Eligible=$eligible.Count
      SeenInOurHistory=$existing;CrossFeedDuplicate=$duplicates
      NewURLs=$novel;FeedSHA256=$feedSHA;Error=''
    })
    Write-Host "$($feed.Id): parsed=$($entries.Count), relevant=$($eligible.Count), NEW URLs=$novel"
  }catch{
    $msg=$_.Exception.Message
    if($msg.Length -gt 100){$msg=$msg.Substring(0,100)}
    $sourceStats.Add([pscustomobject]@{
      Source=$feed.Id;Status='ERROR';Parsed=0;Eligible=0;SeenInOurHistory=0
      CrossFeedDuplicate=0;NewURLs=0;FeedSHA256='';Error=$msg
    })
    Write-Host "$($feed.Id): unavailable ($msg)"
  }
}
if($feedSucceeded -eq 0){throw 'All feed downloads failed; no discovery report created'}
foreach($p in @($catalog,$export,$pilot)){
  $expected=if($p -eq $catalog){$expectedCatalog}elseif($p -eq $export){$expectedExport}else{$expectedPilot}
  if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -cne $expected){
    throw "Production reference changed during discovery: $p"
  }
}
if(-not(Test-Path -LiteralPath $outdir -PathType Container)){
  [void](New-Item -ItemType Directory -Path $outdir -ErrorAction Stop)
}
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$dest=Join-Path $outdir ("source-discovery-$stamp.json")
$newNames=@($collected|Where-Object {$_.Classification -eq 'POTENTIAL_NEW_CHANNEL_NAME'})
$uniqueNewNames=@($newNames|Where-Object {$_.NameKey}|Select-Object -ExpandProperty NameKey -Unique)
$manifest=[ordered]@{
  SchemaVersion=1;CreatedUtc=[DateTime]::UtcNow.ToString('o')
  State='CANDIDATES_NOT_NETWORK_OR_CONTENT_VERIFIED'
  Node=$env:COMPUTERNAME;Sources=@($sourceStats.ToArray())
  HistoricalCatalogSha256=$expectedCatalog;HistoricalW2019SReportSha256=$expectedExport
  PublishedPilotSha256=$expectedPilot
  FeedsSuccessful=$feedSucceeded
  NewURLCandidates=$collected.Count
  NewNameSourceURLCandidates=$newNames.Count
  UniqueNewChannelNames=$uniqueNewNames.Count
  Records=@($collected.ToArray())
  Safety='Local private staging only. No video downloaded and no production M3U publication.'
}
$json=ConvertTo-Json -InputObject $manifest -Depth 10
$bytes=[Text.UTF8Encoding]::new($false).GetBytes($json)
$handle=[IO.File]::Open($dest,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$handle.Write($bytes,0,$bytes.Length);$handle.Flush()}finally{$handle.Dispose()}
$verify=Get-Content -LiteralPath $dest -Raw -Encoding UTF8|ConvertFrom-Json
if(@($verify.Records).Count -ne $collected.Count){throw 'Staging report round-trip row count mismatch'}
Write-Host '=== IPTV ADDITIONAL SOURCE DISCOVERY SUMMARY ==='
[pscustomobject]@{
  FeedsOK=$feedSucceeded
  FeedsTotal=$feeds.Count
  NewSourceURLCandidates=$collected.Count
  NewNameSourceURLCandidates=$newNames.Count
  UniqueNewChannelNames=$uniqueNewNames.Count
  ExistingChannelAlternatives=($collected.Count-$newNames.Count)
  StageReport=$dest
  SHA256=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
  StreamNetworkProbes=0
  ProductionChanges='NONE'
} | Format-List
Write-Host '=== FIRST 25 POTENTIAL NEW CHANNEL NAMES (NO URL DISPLAY) ==='
$newNames|Select-Object -First 25 Feed,Channel,URLKey|Format-Table -AutoSize
Write-Host 'Do NOT publish or share staged JSON: original URLs may have tokens.'
