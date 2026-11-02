#requires -Version 7.0
# IPTV source-selection stage: independent RU/UA sources before automation.
# READ-ONLY against ALL published playlists, scheduler, IPTV+, and Lampac.
# Fetches catalogs and stages small HLS test lists in C:\ReservLampac.
[CmdletBinding()]
param(
  [ValidateRange(10,150)][int]$MaxNewPerCountry=60,
  [ValidateRange(1,5)][int]$MaxAlternativesPerChannel=2
)
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$root='C:\ReservLampac\IPTVPlus\SourceSelection'
$published='C:\IPTV-Manager\public\playlists'
$ruFile=Join-Path $published 'IPTV-RU-Pilot-v1.m3u'
$uaFile=Join-Path $published 'IPTV-UA.m3u'
$bothFile=Join-Path $published 'IPTV-UA-RU-Pilot-v1.m3u'
$timestamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$dir=Join-Path $root ('selection-'+$timestamp)
$sources=@(
  [pscustomobject]@{Name='IPTVORG-RU';Region='RU';URL='https://iptv-org.github.io/iptv/countries/ru.m3u';File='iptvorg-ru.m3u'}
  [pscustomobject]@{Name='IPTVORG-UA';Region='UA';URL='https://iptv-org.github.io/iptv/countries/ua.m3u';File='iptvorg-ua.m3u'}
  [pscustomobject]@{Name='IPTVORG-RUS';Region='RU';URL='https://iptv-org.github.io/iptv/languages/rus.m3u';File='iptvorg-rus.m3u'}
  [pscustomobject]@{Name='IPTVORG-UKR';Region='UA';URL='https://iptv-org.github.io/iptv/languages/ukr.m3u';File='iptvorg-ukr.m3u'}
  [pscustomobject]@{Name='NGRCH-RU';Region='RU';URL='https://ngrch.github.io/iptv/ru.m3u';File='ngrch-ru.m3u'}
  [pscustomobject]@{Name='DEARBULUT-RU';Region='RU';URL='https://dearbulut.github.io/iptv/playlists/country/ru.m3u';File='dearbulut-ru.m3u'}
  [pscustomobject]@{Name='DEARBULUT-UA';Region='UA';URL='https://dearbulut.github.io/iptv/playlists/country/ua.m3u';File='dearbulut-ua.m3u'}
  [pscustomobject]@{Name='FREE-TV';Region='ALL';URL='https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8';File='freetv.m3u8'}
  [pscustomobject]@{Name='ADAM-ZS';Region='RUUA';URL='https://raw.githubusercontent.com/Adam-ZS/iptv-ru-ua/main/playlist.m3u';File='adam-ru-ua.m3u'}
  [pscustomobject]@{Name='IPTVORG-API';Region='RUUA';URL='https://iptv-org.github.io/api/streams.json';File='iptvorg-streams.json'}
)
function Canonical([string]$s){
  if(-not $s){return ''}
  return (($s -split '@')[0]).Trim()
}
function CleanName([string]$s){
  $s=$s.ToLowerInvariant()
  $s=$s -replace '(?i)\s*\[(?:not 24/7|geo.blocked|hd|sd|fhd|4k|576p|720p|1080p|2160p)\]',''
  $s=$s -replace '(?i)\s*\((?:576[i|p]|720p|1080p|2160p|4k|hd|sd)\)',''
  return ($s -replace '[^\p{L}\p{Nd}]','').Trim()
}
function ShortHash([string]$s){
  return [Convert]::ToHexString(
    [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($s))
  ).Substring(0,16)
}
function Is-Restricted([string]$title,[string]$group){
  $s=$title+' '+$group
  return ($s -match '(?i)(adult|xxx|porn|erotic|18\+|casino|gambl|betting|эрот|порно|казино|ставки|для взрослых)')
}
function Is-Quarantined([string]$hostname){
  foreach($hostSuffix in @('cinerama.uz','skygo.mn')){
    if($hostname -eq $hostSuffix -or
       $hostname.EndsWith('.'+$hostSuffix)){return $true}
  }
  return $false
}
function Kind([string]$url,[string]$hostName){
  if($hostName -match '(^|\.)youtube\.com$|(^|\.)youtu\.be$'){return 'YOUTUBE'}
  if($url -match '(?i)\.m3u8(?:\?|$)' -or
     $url -match '(?i)(/hls/|[?&]hls(?:=|&|$))'){return 'HLS'}
  return 'OTHER'
}
function New-Entry([string]$id,[string]$name,[string]$url,
  [string]$region,[string]$source,[string]$group,[string]$agent,[string]$referer){
  $uri=$null
  if(-not [Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri)){return $null}
  if($uri.Scheme -notin @('http','https') -or $uri.UserInfo){return $null}
  $hostname=$uri.DnsSafeHost.ToLowerInvariant()
  if(-not $hostname -or Is-Restricted $name $group){return $null}
  return [pscustomobject]@{
    Id=(Canonical $id)
    Name=$name
    Url=$url
    UrlHash=(ShortHash $url)
    Host=$hostname
    Region=$region
    Source=$source
    Group=$group
    Kind=(Kind $url $hostname)
    UserAgent=$agent
    Referrer=$referer
    Quarantined=(Is-Quarantined $hostname)
  }
}
function Read-M3U([string]$path,[string]$region,[string]$source){
  $out=[Collections.Generic.List[object]]::new()
  $header=''
  $agent=''
  $referer=''
  foreach($raw in [IO.File]::ReadLines($path,[Text.Encoding]::UTF8)){
    $line=$raw.Trim()
    if($line.StartsWith('#EXTINF:')){
      $header=$line;$agent='';$referer=''
      continue
    }
    if(-not $header -or -not $line){continue}
    if($line -match '(?i)^#EXTVLCOPT:http-user-agent=(.*)$'){
      $agent=$Matches[1];continue
    }
    if($line -match '(?i)^#EXTVLCOPT:http-referrer=(.*)$'){
      $referer=$Matches[1];continue
    }
    if($line.StartsWith('#')){continue}
    $idMatch=[regex]::Match($header,'(?i)tvg-id="([^"]*)"')
    $groupMatch=[regex]::Match($header,'(?i)group-title="([^"]*)"')
    $name=$header.Substring($header.LastIndexOf(',')+1).Trim()
    $id=if($idMatch.Success){$idMatch.Groups[1].Value}else{''}
    $group=if($groupMatch.Success){$groupMatch.Groups[1].Value}else{''}
    $entry=New-Entry $id $name $line $region $source $group $agent $referer
    if($null -ne $entry){$out.Add($entry)}
    $header=''
  }
  return ,$out
}
function Write-ReviewM3U([string]$path,[object[]]$items){
  $lines=[Collections.Generic.List[string]]::new()
  $lines.Add('#EXTM3U')
  foreach($c in $items){
    if($c.Kind -ne 'HLS' -or $c.Quarantined){continue}
    $display=($c.Name -replace '[\r\n,]',' ')
    $grp='IPTV / TEST / '+$c.Region
    $id=($c.Id -replace '"','')
    $lines.Add('#EXTINF:-1 tvg-id="'+$id+'" group-title="'+$grp+'",'+$display+' ['+$c.Source+']')
    if($c.UserAgent){$lines.Add('#EXTVLCOPT:http-user-agent='+($c.UserAgent -replace '[\r\n]',''))}
    if($c.Referrer){$lines.Add('#EXTVLCOPT:http-referrer='+($c.Referrer -replace '[\r\n]',''))}
    $lines.Add($c.Url)
  }
  [IO.File]::WriteAllText($path,
    ($lines.ToArray() -join [Environment]::NewLine)+[Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))
}
$hashes=[ordered]@{}
foreach($path in @($ruFile,$uaFile,$bothFile)){
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing production M3U: $path"}
  $hashes[$path]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
$ru=(Read-M3U $ruFile 'RU' 'PUBLISHED-RU').ToArray()
$ua=(Read-M3U $uaFile 'UA' 'PUBLISHED-UA').ToArray()
$both=(Read-M3U $bothFile 'RUUA' 'PUBLISHED-COMBINED').ToArray()
if($ru.Count -ne 47 -or $ua.Count -ne 84 -or $both.Count -ne 131){
  throw "Unexpected published channel counts: RU=$($ru.Count), UA=$($ua.Count), BOTH=$($both.Count)"
}
$baseline=[Collections.Generic.List[object]]::new()
foreach($entry in $ru){$baseline.Add($entry)}
foreach($entry in $ua){$baseline.Add($entry)}
$baseIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$baseNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($entry in $baseline){
  if($entry.Id){[void]$baseIds.Add($entry.Id)}
  [void]$baseNames.Add((CleanName $entry.Name))
}
New-Item -ItemType Directory -Path $dir -Force | Out-Null
Write-Host '=== IPTV SOURCE SELECTION: DOWNLOAD INDEPENDENT CATALOGS ==='
Write-Host 'Production RU=47 UA=84; nothing will be published or replaced'
$downloads=[Collections.Generic.List[object]]::new()
$entries=[Collections.Generic.List[object]]::new()
foreach($src in $sources){
  $file=Join-Path $dir $src.File
  & curl.exe -fLsS --connect-timeout 12 --max-time 90 --max-filesize 40000000 -o $file $src.URL
  $code=$LASTEXITCODE
  $available=($code -eq 0 -and
    (Test-Path -LiteralPath $file -PathType Leaf) -and
    (Get-Item -LiteralPath $file).Length -gt 50)
  $size=if($available){(Get-Item -LiteralPath $file).Length}else{0}
  $count=0
  $errorText=''
  if($available){
    try {
      if($src.Name -eq 'IPTVORG-API'){
        $api=Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        foreach($stream in $api){
          $id=Canonical ([string]$stream.channel)
          if(-not $id){continue}
          $region=if($id -match '(?i)\.ru$'){'RU'}elseif($id -match '(?i)\.ua$'){'UA'}else{'OTHER'}
          if($region -eq 'OTHER' -and -not $baseIds.Contains($id)){continue}
          $entry=New-Entry $id ([string]$stream.title) ([string]$stream.url) $region $src.Name '' ([string]$stream.user_agent) ([string]$stream.referrer)
          if($null -ne $entry){$entries.Add($entry);$count++}
        }
      }else{
        $items=Read-M3U $file $src.Region $src.Name
        foreach($entry in $items.ToArray()){$entries.Add($entry);$count++}
      }
    }catch{
      $errorText=$_.Exception.Message
      $available=$false
      Write-Warning "$($src.Name): parse failed: $errorText"
    }
  }else{$errorText="curl exit $code"}
  $downloads.Add([pscustomobject]@{
    Source=$src.Name;Available=$available;Bytes=$size;ParsedEntries=$count
    Error=$errorText;IndexUrl=$src.URL
  })
  Write-Host "$($src.Name): $(if($available){"$count parsed"}else{"UNAVAILABLE"})"
}
$clean=[Collections.Generic.List[object]]::new()
$excluded=0
$youtube=0
foreach($entry in $entries){
  if($entry.Quarantined){$excluded++;continue}
  if($entry.Kind -eq 'YOUTUBE'){$youtube++;continue}
  if($entry.Kind -ne 'HLS'){continue}
  $clean.Add($entry)
}
$matched=[Collections.Generic.List[object]]::new()
$unmatched=[Collections.Generic.List[object]]::new()
$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($item in $clean){
  $targets=@()
  $matchType=''
  if($item.Id){
    $targets=@($baseline | Where-Object {$_.Id -and $_.Id -eq $item.Id})
    if($targets.Count -gt 0){$matchType='EXACT_ID'}
  }
  if($targets.Count -eq 0){
    $norm=CleanName $item.Name
    if($norm.Length -ge 5){
      $targets=@($baseline | Where-Object {(CleanName $_.Name) -eq $norm})
      if($targets.Count -gt 0){$matchType='NAME_REVIEW'}
    }
  }
  if($targets.Count -gt 0){
    foreach($target in $targets){
      if($item.Url -eq $target.Url){continue}
      $key=$target.Region+'|'+$target.Name+'|'+(ShortHash $target.Url)+'|'+$item.UrlHash
      if(-not $seen.Add($key)){continue}
      $matched.Add([pscustomobject]@{
        Target=$target.Name;TargetId=$target.Id;Region=$target.Region
        CurrentHost=$target.Host
        CandidateName=$item.Name
        CandidateId=$item.Id
        CandidateHost=$item.Host
        Source=$item.Source;Kind=$item.Kind
        Url=$item.Url;UrlHash=$item.UrlHash
        UserAgent=$item.UserAgent;Referrer=$item.Referrer
        Match=$matchType
        IndependentHost=($item.Host -ne $target.Host)
        ContentVerified=$false
        NetworkVerified=$false
      })
    }
  }else{
    $country=if($item.Region -eq 'RU' -or $item.Region -eq 'UA'){$item.Region}else{''}
    if(-not $country -and $item.Id -match '(?i)\.(ru|ua)$'){$country=$Matches[1].ToUpperInvariant()}
    if($country -in @('RU','UA')){
      $unmatched.Add([pscustomobject]@{
        Name=$item.Name;Id=$item.Id;Region=$country
        Source=$item.Source;Host=$item.Host;Kind=$item.Kind
        Url=$item.Url;UrlHash=$item.UrlHash
        UserAgent=$item.UserAgent;Referrer=$item.Referrer
        Quarantined=$false
        ContentVerified=$false;NetworkVerified=$false
      })
    }
  }
}
# A candidate listed in several source indexes is still ONE upstream URL.
$matchedAll=@($matched | Where-Object {$_.IndependentHost})
$perChannel=[Collections.Generic.List[object]]::new()
$testCandidates=[Collections.Generic.List[object]]::new()
foreach($group in ($matchedAll | Group-Object Region,Target)){
  $cands=@($group.Group | Sort-Object Source,CandidateHost)
  $hosts=@($cands | ForEach-Object {$_.CandidateHost} | Sort-Object -Unique)
  $exact=@($cands | Where-Object {$_.Match -eq 'EXACT_ID'})
  $perChannel.Add([pscustomobject]@{
    Channel=$cands[0].Target;Region=$cands[0].Region
    CurrentHost=$cands[0].CurrentHost
    Candidates=$cands.Count;IndependentHosts=$hosts.Count
    ExactIdCandidates=$exact.Count
    Sources=@($cands | ForEach-Object {$_.Source} | Sort-Object -Unique)
  })
  $usedHost=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach($c in ($cands | Sort-Object @{Expression={if($_.Match -eq 'EXACT_ID'){0}else{1}}},Source)){
    if($usedHost.Add($c.CandidateHost)){
      $testCandidates.Add([pscustomobject]@{
        Name=$c.Target;Id=$c.TargetId;Region=$c.Region
        Source=$c.Source;Host=$c.CandidateHost;Kind=$c.Kind
        Url=$c.Url;UrlHash=$c.UrlHash
        UserAgent=$c.UserAgent;Referrer=$c.Referrer;Quarantined=$false
        Match=$c.Match
      })
    }
    if($usedHost.Count -ge $MaxAlternativesPerChannel){break}
  }
}
$new=[Collections.Generic.List[object]]::new()
foreach($region in @('RU','UA')){
  $used=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $ordered=@($unmatched | Where-Object {$_.Region -eq $region} |
    Sort-Object @{Expression={switch -Regex ($_.Source) {
      '^FREE-TV$' {0;break}
      '^DEARBULUT' {1;break}
      '^NGRCH' {2;break}
      '^ADAM' {3;break}
      default {4}
    }}},Name)
  foreach($item in $ordered){
    $name=CleanName $item.Name
    if($name.Length -lt 5){continue}
    $key=if($item.Id){'ID:'+ $item.Id}else{'NAME:'+ $name}
    if(-not $used.Add($key)){continue}
    $new.Add($item)
    if($used.Count -ge $MaxNewPerCountry){break}
  }
}
foreach($p in $hashes.Keys){
  if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $hashes[$p]){
    throw "Published M3U changed during source discovery: $p"
  }
}
$matchFile=Join-Path $dir 'alternatives-for-131.json'
$newFile=Join-Path $dir 'new-channels-for-review.json'
$reviewRu=Join-Path $dir 'RU-EXTERNAL-SOURCES-TEST-NOT-PUBLISHED.m3u'
$reviewUa=Join-Path $dir 'UA-EXTERNAL-SOURCES-TEST-NOT-PUBLISHED.m3u'
$newRu=Join-Path $dir 'RU-NEW-TEST-NOT-PUBLISHED.m3u'
$newUa=Join-Path $dir 'UA-NEW-TEST-NOT-PUBLISHED.m3u'
$reportFile=Join-Path $dir 'report.json'
[IO.File]::WriteAllText($matchFile,($matched|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($newFile,($new|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-ReviewM3U $reviewRu @($testCandidates | Where-Object {$_.Region -eq 'RU'})
Write-ReviewM3U $reviewUa @($testCandidates | Where-Object {$_.Region -eq 'UA'})
Write-ReviewM3U $newRu @($new | Where-Object {$_.Region -eq 'RU'})
Write-ReviewM3U $newUa @($new | Where-Object {$_.Region -eq 'UA'})
$report=[ordered]@{
  Status='STAGED_SOURCE_INVENTORY_NO_PUBLICATION'
  TimeUTC=[DateTime]::UtcNow.ToString('o')
  PublishedRU=47;PublishedUA=84;PublishedCombined=131
  AllIndexed=$entries.Count
  HlsAfterQuarantine=$clean.Count
  QuarantinedEntries=$excluded
  YouTubeLinksHeldSeparately=$youtube
  AlternativeURLsForPublished=@($matched).Count
  IndependentHostAlternatives=@($matchedAll).Count
  ChannelsWithIndependentAlternatives=$perChannel.Count
  ReviewedTestCandidates=$testCandidates.Count
  NewRUCandidates=@($new | Where-Object {$_.Region -eq 'RU'}).Count
  NewUACandidates=@($new | Where-Object {$_.Region -eq 'UA'}).Count
  SourceReports=@($downloads)
  ChannelCoverage=@($perChannel)
  TestRu=$reviewRu;TestUa=$reviewUa
  NewRu=$newRu;NewUa=$newUa
  ExistingCandidatesJson=$matchFile;NewCandidatesJson=$newFile
  PublishedHashes=$hashes
  NetworkTested=$false
  RealBroadcastVerified=$false
  ProductionChanged=$false
}
[IO.File]::WriteAllText($reportFile,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Host '=== INDEPENDENT SOURCE COVERAGE OF EXISTING CHANNELS ==='
$perChannel | Sort-Object Region,Channel |
  Select-Object Region,Channel,IndependentHosts,ExactIdCandidates |
  Format-Table -AutoSize
Write-Host '=== SOURCE-POOL SUMMARY ==='
[pscustomobject]@{
  Catalogs=$sources.Count
  WorkingCatalogDownloads=@($downloads | Where-Object {$_.Available}).Count
  Indexed=$entries.Count
  Quarantined=$excluded
  ExistingChannelsWithAlternativeHosts=$perChannel.Count
  IndependentURLCandidates=@($matchedAll).Count
  NewRU=@($new | Where-Object {$_.Region -eq 'RU'}).Count
  NewUA=@($new | Where-Object {$_.Region -eq 'UA'}).Count
  Report=$reportFile
  TestRU=$reviewRu
  TestUA=$reviewUa
  Publication='NONE'
} | Format-List
Write-Host 'IPTV SOURCE SELECTION: COMPLETE (UNTESTED PREVIEW ONLY)'
