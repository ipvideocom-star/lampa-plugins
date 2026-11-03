#requires -Version 7.0
# v2 OFFLINE triage of new public IPTV playlist candidates (not a network stream test).
# W2022 PowerShell 7 only. Writes ONE URL-free report into existing Discovery folder.
# Reads baseline 814/347, pilot 131, staged discovery 1949. Never edits published M3U.
[CmdletBinding()]
param(
  [ValidateRange(25,300)][int]$MaxChannels=160,
  [ValidateRange(1,3)][int]$URLsPerChannel=2
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
if(-not $IsWindows -or $PSVersionTable.PSVersion.Major -lt 7){throw 'Windows PowerShell 7 required'}
$os=(Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption
if($os -notmatch '2022'){throw "Run on main W2022, not $os"}
$stage='C:\ReservLampac\IPTVPlus\Discovery\source-discovery-20261103-174853-693718c1.json'
$stageSHA='469EBA746298333F14812D9F8CB71A5302D16859CBE5EA7C36AF0DDAB19F2AF2'
$catalog='C:\IPTV-Manager\data\catalog-raw.m3u'
$catalogSHA='4FBEE8A643CDE432EFBE927C3F6C1714134BA6F3D1E9F51105857848819ACA36'
$oldExport='C:\IPTV-Manager\data\IPTV-verified-814-20261031-092455-769.json'
$exportSHA='82ACF6A103C6D7BE6B91332A0FA04E14425A0187E2A64D55A68AE48499BDCF59'
$pilot='C:\IPTV-Manager\public\playlists\IPTV-UA-RU-Pilot-v1.m3u'
$pilotSHA='A2F9B549425FF8D6B925E0CFD0E8B515B78ED5F2DC83C130986259D24AFFB875'
$protected=@(
  [pscustomobject]@{Path=$stage;SHA256=$stageSHA}
  [pscustomobject]@{Path=$catalog;SHA256=$catalogSHA}
  [pscustomobject]@{Path=$oldExport;SHA256=$exportSHA}
  [pscustomobject]@{Path=$pilot;SHA256=$pilotSHA}
)
foreach($entry in $protected){
  $p=$entry.Path
  if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing input: $p"}
  if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -cne $entry.SHA256){
    throw "Input SHA256 changed. No output created: $p"
  }
}
function SHA16([string]$s){
  [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
    [Text.Encoding]::UTF8.GetBytes($s))).Substring(0,16)
}
function M3uName([string]$header){
  $inQuotes=$false
  for($i=0;$i -lt $header.Length;$i++){
    if($header[$i] -eq '"'){$inQuotes=-not $inQuotes}
    elseif($header[$i] -eq ',' -and -not $inQuotes){return $header.Substring($i+1).Trim()}
  }
  return ''
}
function Canonical([string]$name){
  $n=$name.Replace('Ⓢ','').Replace('Ⓖ','').Replace('Ⓨ','').Normalize([Text.NormalizationForm]::FormKC)
  # A trailing (2), (3), ... commonly denotes an alternative source, not a distinct channel.
  for($i=0;$i -lt 3;$i++){
    $n=[regex]::Replace($n,'(?i)\s*(?:\(\s*\d{1,2}\s*\)|\[\s*\d{1,2}\s*\])\s*$','')
    $n=[regex]::Replace($n,'(?i)\s*\((?:\d{3,4}\s*[pi]|4k|hd|sd)\)\s*$','')
    $n=[regex]::Replace($n,'(?i)\s*\[\s*(?:backup|alt|резерв)\s*\]\s*$','')
  }
  $n=$n.Replace('ё','е').Replace('Ё','Е').ToLowerInvariant()
  $n=([regex]::Replace($n,'[^\p{L}\p{Nd}]+',' ')).Trim()
  switch -Exact ($n){
    'первый' {return 'первый канал'}
    'пятый' {return 'пятый канал'}
    'россия к' {return 'россия культура'}
    'матч' {return 'матч тв'}
    '360 news' {return '360 новости'}
    default {return $n}
  }
}
function ReadM3uNames([string]$file,[string]$confirmedOnly,[object]$confirmedIndex){
  $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $meta=$null
  foreach($raw in [IO.File]::ReadLines($file,[Text.Encoding]::UTF8)){
    $line=$raw.Trim()
    if($line.StartsWith('#EXTINF:')){$meta=$line;continue}
    if($null -eq $meta -or -not $line -or $line.StartsWith('#')){continue}
    $name=M3uName $meta
    $key=Canonical $name
    if($key){
      if($confirmedOnly -eq 'ALL' -or $confirmedIndex.Contains((SHA16 $line))){
        [void]$names.Add($key)
      }
    }
    $meta=$null
  }
  return ,$names
}
$historical=Get-Content -LiteralPath $oldExport -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
if($historical.schemaVersion -ne 1 -or $historical.node -cne 'W2019S' -or
   $historical.verifiedCount -ne 814 -or $historical.confirmedCount -ne 347 -or
   @($historical.records).Count -ne 814){throw 'Historical W2019S verification incompatible'}
$confirmedKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($r in $historical.records){if($r.confirmed){[void]$confirmedKeys.Add([string]$r.urlKey)}}
if($confirmedKeys.Count -ne 347){throw 'Historical confirmed key count mismatch'}
$pilotNames=ReadM3uNames $pilot 'ALL' $confirmedKeys
$oldNames=ReadM3uNames $catalog 'ALL' $confirmedKeys
$confirmedNames=ReadM3uNames $catalog 'CONFIRMED' $confirmedKeys
$input=Get-Content -LiteralPath $stage -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
if($input.SchemaVersion -ne 1 -or $input.State -cne 'CANDIDATES_NOT_NETWORK_OR_CONTENT_VERIFIED' -or
   $input.NewURLCandidates -ne 1949 -or @($input.Records).Count -ne 1949 -or
   $input.FeedsSuccessful -ne 5){
  throw 'Unexpected discovery JSON schema/count; no output written'
}
$feedWeights=@{
  'NGRCH-RU'=35
  'DENXVO-FULL'=32
  'NGRCH-MUSIC'=26
  'FREE-TV-GLOBAL'=18
  'FREECAST-GLOBAL'=15
}
$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$rows=[Collections.Generic.List[object]]::new()
foreach($r in $input.Records){
  $url=[string]$r.URL
  $key=[string]$r.URLKey
  $feed=[string]$r.Feed
  $channel=[string]$r.Channel
  if(-not $feedWeights.ContainsKey($feed) -or $key -cnotmatch '^[0-9A-F]{16}$' -or
     (SHA16 $url) -cne $key -or -not $seen.Add($key)){
    throw "Untrusted/duplicate source fingerprint or feed: $feed $key"
  }
  if($channel.Length -lt 2 -or $channel.Length -gt 220){continue}
  $canonical=Canonical $channel
  if(-not $canonical){throw "Missing canonical name: $key"}
  $uri=$null
  if(-not [Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or
     $uri.Scheme -notin @('http','https') -or $uri.UserInfo){throw "Invalid URL in staged discovery: $key"}
  $meta=($channel+' '+[string]$r.Group+' '+[string]$r.Country+' '+[string]$r.Language)
  if($meta -match '(?i)\b(adult|porn|xxx|erotic|sexcam|18\+|casino|gambling|betting)\b'){
    continue
  }
  $path=$uri.AbsolutePath
  if($path -match '(?i)\.(?:mp4|mp3|mov|webm|avi|flv|mkv|aac)$'){continue}
  $class=if($pilotNames.Contains($canonical)){'PILOT_CHANNEL_ALTERNATIVE'}
    elseif($confirmedNames.Contains($canonical)){'HISTORICALLY_WORKED_NAME_NOT_IN_PILOT'}
    elseif($oldNames.Contains($canonical)){'OLD_CATALOG_NAME_NOT_IN_PILOT'}
    else{'POTENTIAL_NEW_CHANNEL_NAME'}
  $score=[int]$feedWeights[$feed]
  if($uri.Scheme -ceq 'https'){$score+=5}
  if($path -match '(?i)\.m3u8(?:$|/)'){$score+=10}
  elseif($path -match '(?i)\.mpd(?:$|/)'){$score+=1}
  if(-not [string]::IsNullOrWhiteSpace([string]$r.TvgID)){$score+=5}
  if(-not [string]::IsNullOrWhiteSpace([string]$r.Country)){$score+=3}
  if(-not [string]::IsNullOrWhiteSpace([string]$r.Language)){$score+=3}
  $rows.Add([pscustomobject]@{
    Canonical=$canonical;Channel=$channel;URLKey=$key
    Feed=$feed;TvgID=[string]$r.TvgID;Group=[string]$r.Group
    Score=$score;Class=$class
  })
}
if($seen.Count -ne 1949){throw "Unexpected unique URL count: $($seen.Count)"}
$groups=[Collections.Generic.List[object]]::new()
foreach($g in ($rows | Group-Object Canonical)){
  $variants=@($g.Group|Sort-Object @{Expression='Score';Descending=$true},@{Expression='Feed';Descending=$false},@{Expression='Channel';Descending=$false})
  $class=if(@($variants|Where-Object {$_.Class -eq 'PILOT_CHANNEL_ALTERNATIVE'}).Count -gt 0){'PILOT_CHANNEL_ALTERNATIVE'}
    elseif(@($variants|Where-Object {$_.Class -eq 'HISTORICALLY_WORKED_NAME_NOT_IN_PILOT'}).Count -gt 0){'HISTORICALLY_WORKED_NAME_NOT_IN_PILOT'}
    elseif(@($variants|Where-Object {$_.Class -eq 'OLD_CATALOG_NAME_NOT_IN_PILOT'}).Count -gt 0){'OLD_CATALOG_NAME_NOT_IN_PILOT'}
    else{'POTENTIAL_NEW_CHANNEL_NAME'}
  $rank=switch($class){
    'HISTORICALLY_WORKED_NAME_NOT_IN_PILOT'{1}
    'POTENTIAL_NEW_CHANNEL_NAME'{2}
    'OLD_CATALOG_NAME_NOT_IN_PILOT'{3}
    'PILOT_CHANNEL_ALTERNATIVE'{4}
  }
  $feeds=@($variants|Select-Object -ExpandProperty Feed -Unique)
  $groups.Add([pscustomobject]@{
    Canonical=$g.Name;DisplayName=$variants[0].Channel;Class=$class
    Rank=$rank;BestScore=$variants[0].Score
    StreamURLs=$variants.Count
    Feeds=$feeds
    URLKeys=@($variants|Select-Object -ExpandProperty URLKey)
  })
}
$ordered=@($groups|Sort-Object Rank,@{Expression='BestScore';Descending=$true},@{Expression='StreamURLs';Descending=$true},Canonical)
$shortlistGroups=@($ordered|Where-Object {$_.Rank -lt 4}|Select-Object -First $MaxChannels)
$shortlist=[Collections.Generic.List[object]]::new()
foreach($g in $shortlistGroups){
  $pool=@($rows|Where-Object {$_.Canonical -ceq $g.Canonical}|Sort-Object @{Expression='Score';Descending=$true})
  $selected=[Collections.Generic.List[object]]::new()
  $sourceSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($r in $pool){
    if($selected.Count -ge $URLsPerChannel){break}
    if($sourceSeen.Add($r.Feed)){$selected.Add($r)}
  }
  foreach($r in $pool){
    if($selected.Count -ge $URLsPerChannel){break}
    if(-not @($selected|Where-Object {$_.URLKey -ceq $r.URLKey}).Count){$selected.Add($r)}
  }
  $shortlist.Add([pscustomobject]@{
    Channel=$g.DisplayName;CanonicalName=$g.Canonical;Class=$g.Class
    KnownSourceCount=$g.StreamURLs;FeedCount=$g.Feeds.Count
    CandidateURLKeys=@($selected|Select-Object -ExpandProperty URLKey)
    SelectedFeeds=@($selected|Select-Object -ExpandProperty Feed)
    NetworkStatus='UNTESTED';ContentStatus='NOT_VERIFIED';StreamRights='NOT_VERIFIED'
  })
}
foreach($entry in $protected){
  if((Get-FileHash -LiteralPath $entry.Path -Algorithm SHA256).Hash -cne $entry.SHA256){
    throw "Input changed during triage: $($entry.Path)"
  }
}
$dest=Join-Path (Split-Path -Parent $stage) (
  'triage-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.json'
)
$shortlistURLCount=0
foreach($item in $shortlist){$shortlistURLCount+=@($item.CandidateURLKeys).Count}
$manifest=[ordered]@{
  SchemaVersion=1;CreatedUtc=[DateTime]::UtcNow.ToString('o')
  InputPath=$stage;InputSHA256=$stageSHA
  Status='OFFLINE_CANDIDATES_NOT_NETWORK_CONTENT_OR_RIGHTS_VERIFIED'
  InputUniqueURLs=$seen.Count;AcceptedURLsAfterBasicFilters=$rows.Count
  UniqueCanonicalNameGroups=$groups.Count
  GroupsByClass=@($groups|Group-Object Class|ForEach-Object {
    [ordered]@{Class=$_.Name;Groups=$_.Count}
  })
  ShortlistChannelGroups=$shortlist.Count
  ShortlistURLChecks=$shortlistURLCount
  Shortlist=@($shortlist.ToArray())
  NoOriginalURLsStored=$true;NetworkRequests=0;ProductionChanges='NONE'
}
$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($manifest|ConvertTo-Json -Depth 10))
$fs=[IO.File]::Open($dest,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$fs.Write($bytes,0,$bytes.Length);$fs.Flush()}finally{$fs.Dispose()}
Write-Host '=== IPTV DISCOVERY OFFLINE TRIAGE ==='
[pscustomobject]@{
  InputURLs=$seen.Count
  AcceptedURLs=$rows.Count
  CanonicalChannelGroups=$groups.Count
  PilotAlreadyExistsGroups=@($groups|Where-Object {$_.Class -eq 'PILOT_CHANNEL_ALTERNATIVE'}).Count
  HistoricallyWorkingNameNewToPilot=@($groups|Where-Object {$_.Class -eq 'HISTORICALLY_WORKED_NAME_NOT_IN_PILOT'}).Count
  OldCatalogNameNewToPilot=@($groups|Where-Object {$_.Class -eq 'OLD_CATALOG_NAME_NOT_IN_PILOT'}).Count
  PotentiallyNewChannelGroups=@($groups|Where-Object {$_.Class -eq 'POTENTIAL_NEW_CHANNEL_NAME'}).Count
  ShortlistChannelGroups=$shortlist.Count
  ShortlistURLChecks=$manifest.ShortlistURLChecks
  Report=$dest
  SHA256=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
  NetworkRequests=0;ProductionChanges='NONE'
} | Format-List
Write-Host '=== FIRST 35 SHORTLIST CHANNEL GROUPS ==='
$shortlist|Select-Object -First 35 Class,Channel,KnownSourceCount,FeedCount|Format-Table -AutoSize
Write-Host 'One report only, no original URLs included. No stream or content tested.'
