#requires -Version 7.0
# IPTV Manager: OFFLINE comparison of the historical 347 W2019S-confirmed URLs
# with the CURRENT published 131-channel RU/UA pilot playlist.
# No network access, output files, playlist modifications or service changes.
[CmdletBinding()]
param([ValidateRange(5,60)][int]$ShowNew=30)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
if(-not $IsWindows -or $PSVersionTable.PSVersion.Major -lt 7){
  throw 'Windows Server 2022 with PowerShell 7 required'
}
$os=(Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption
if($os -notmatch '2022'){throw "Wrong server: $os"}
$root='C:\IPTV-Manager'
$catalog=Join-Path $root 'data\catalog-raw.m3u'
$export=Join-Path $root 'data\IPTV-verified-814-20261031-092455-769.json'
$pilot=Join-Path $root 'public\playlists\IPTV-UA-RU-Pilot-v1.m3u'
$catalogSHA='4FBEE8A643CDE432EFBE927C3F6C1714134BA6F3D1E9F51105857848819ACA36'
$exportSHA='82ACF6A103C6D7BE6B91332A0FA04E14425A0187E2A64D55A68AE48499BDCF59'
foreach($p in @($catalog,$export,$pilot)){
  if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Input missing: $p"}
}
if((Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash -cne $catalogSHA){
  throw 'Original 814-source catalog differs from previously approved SHA256'
}
if((Get-FileHash -LiteralPath $export -Algorithm SHA256).Hash -cne $exportSHA){
  throw 'W2019S verification export differs from previously approved SHA256'
}
$pilotHashBefore=(Get-FileHash -LiteralPath $pilot -Algorithm SHA256).Hash
$verified=Get-Content -LiteralPath $export -Raw -Encoding UTF8|ConvertFrom-Json -AsHashtable
if($verified.schemaVersion -ne 1 -or $verified.node -cne 'W2019S' -or
  $verified.catalogCount -ne 814 -or $verified.verifiedCount -ne 814 -or
  $verified.confirmedCount -ne 347 -or @($verified.records).Count -ne 814){
  throw 'Unexpected old verification schema or counts'
}
function Hash16([string]$s){
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
    [Text.Encoding]::UTF8.GetBytes($s))).Substring(0,16)
}
function Attribute([string]$line,[string]$attr){
  $m=[regex]::Match($line,'(?i)(?:^|\s)'+[regex]::Escape($attr)+'="([^"]*)"')
  if($m.Success){return $m.Groups[1].Value}
  return ''
}
function Channel-Name([string]$line){
  $inside=$false
  for($i=0;$i -lt $line.Length;$i++){
    if($line[$i] -eq '"'){$inside=-not $inside}
    elseif($line[$i] -eq ',' -and -not $inside){
      $result=$line.Substring($i+1).Trim()
      if($result){return $result}
      break
    }
  }
  throw 'Invalid channel name in EXTINF metadata'
}
function Name-Key([string]$name){
  $n=$name.Normalize([Text.NormalizationForm]::FormKC)
  $n=[regex]::Replace($n,'\s+\[[^\]]+\]$','')
  $n=[regex]::Replace($n,'(?i)\s*\((?:\d{3,4}\s*[pi]|4k)\)\s*$','')
  $n=$n.Replace('Ⓢ','').Replace('Ⓖ','').Replace('ё','е').Replace('Ё','Е')
  return ([regex]::Replace($n.ToLowerInvariant(),'[^\p{L}\p{Nd}]+',' ')).Trim()
}
function Region([string]$meta){
  $id=Attribute $meta 'tvg-id'
  $country=Attribute $meta 'tvg-country'
  $language=Attribute $meta 'tvg-language'
  $group=Attribute $meta 'group-title'
  if($id -match '(?i)\.ua(?:@[^\s"]*)?$' -or
     $country -match '(?i)(?:^|[;,\s])(?:ua|ukr|ukraine)(?:$|[;,\s])' -or
     $group -match '(?i)^(?:ukraine|україна|украина|ukrainian)$'){return 'UA'}
  if($id -match '(?i)\.ru(?:@[^\s"]*)?$' -or
     $country -match '(?i)(?:^|[;,\s])(?:ru|rus|russia)(?:$|[;,\s])' -or
     $group -match '(?i)^(?:russia|россия|російські|russian)$'){return 'RU'}
  if($language -match '(?i)(?:^|[;,\s])(?:rus|russian|русский|російська)(?:$|[;,\s])' -or
     $group -match '(?i)^(?:russian-language|русскоязычные|russophone)$'){return 'RUS_LANG'}
  return 'OTHER'
}
function Parse-Playlist([string]$p){
  $list=[Collections.Generic.List[object]]::new()
  $meta=$null
  foreach($raw in [IO.File]::ReadLines($p,[Text.Encoding]::UTF8)){
    $line=$raw.Trim()
    if($line.StartsWith('#EXTINF:')){$meta=$line;continue}
    if($null -eq $meta -or -not $line -or $line.StartsWith('#')){continue}
    $uri=$null
    if(-not [Uri]::TryCreate($line,[UriKind]::Absolute,[ref]$uri) -or
       $uri.Scheme -notin @('http','https') -or $uri.UserInfo){
      throw "Invalid channel stream URI in: $p"
    }
    $name=Channel-Name $meta
    $list.Add([pscustomobject]@{
      Name=$name;Norm=(Name-Key $name);TvgID=(Attribute $meta 'tvg-id')
      Key=(Hash16 $line);Region=(Region $meta)
    })
    $meta=$null
  }
  return $list.ToArray()
}
$historical=[Collections.Generic.Dictionary[string,bool]]::new([StringComparer]::Ordinal)
foreach($r in $verified.records){
  $key=[string]$r.urlKey
  if($key -cnotmatch '^[A-F0-9]{16}$' -or $historical.ContainsKey($key) -or
     $r.confirmed -isnot [bool]){throw 'Invalid or duplicate historical record'}
  $historical.Add($key,[bool]$r.confirmed)
}
$catalogEntries=@(Parse-Playlist $catalog)
$pilotEntries=@(Parse-Playlist $pilot)
if($pilotEntries.Count -ne 131){throw "Published pilot contains $($pilotEntries.Count) instead of 131 entries"}
$catalogUnique=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$confirmed=[Collections.Generic.List[object]]::new()
foreach($e in $catalogEntries){
  if(-not $catalogUnique.Add($e.Key)){continue}
  if(-not $historical.ContainsKey($e.Key)){throw 'Catalog URL missing from W2019S verified export'}
  if($historical[$e.Key]){$confirmed.Add($e)}
}
if($catalogUnique.Count -ne 814 -or $confirmed.Count -ne 347){
  throw "Catalog export mismatch: unique=$($catalogUnique.Count), confirmed=$($confirmed.Count)"
}
$pilotURL=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$pilotIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$pilotNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($e in $pilotEntries){
  [void]$pilotURL.Add($e.Key)
  if($e.TvgID){[void]$pilotIds.Add($e.TvgID)}
  if($e.Norm){[void]$pilotNames.Add($e.Norm)}
}
$classified=[Collections.Generic.List[object]]::new()
foreach($e in $confirmed){
  $kind=if($pilotURL.Contains($e.Key)){'EXACT_URL_ALREADY_IN_PILOT'}
    elseif($e.TvgID -and $pilotIds.Contains($e.TvgID)){'ALTERNATIVE_SAME_TVG_ID'}
    elseif($e.Norm -and $pilotNames.Contains($e.Norm)){'ALTERNATIVE_SAME_NAME'}
    else{'POTENTIAL_NEW_CHANNEL'}
  $classified.Add([pscustomobject]@{
    Channel=$e.Name;Region=$e.Region;Class=$kind;TvgID=$e.TvgID
    URLKey=$e.Key;Norm=$e.Norm
  })
}
if((Get-FileHash -LiteralPath $pilot -Algorithm SHA256).Hash -cne $pilotHashBefore){
  throw 'Published pilot changed while comparison was running'
}
$relevant=@($classified|Where-Object {$_.Region -in @('UA','RU','RUS_LANG')})
$new=@($relevant|Where-Object {$_.Class -eq 'POTENTIAL_NEW_CHANNEL'})
$uniqueNames=@($new|Where-Object {$_.Norm}|Select-Object -ExpandProperty Norm -Unique)
Write-Host '=== IPTV VERIFIED 347 vs PUBLISHED PILOT 131 ==='
[pscustomobject]@{
  MainServer=$env:COMPUTERNAME
  OriginalCatalogUniqueURLs=$catalogUnique.Count
  HistoricalW2019SConfirmedURLs=$confirmed.Count
  PublishedPilotEntries=$pilotEntries.Count
  RelevantConfirmedSources=$relevant.Count
  PotentialNewSources=$new.Count
  PotentialNewDistinctNames=$uniqueNames.Count
  PilotSHA256=$pilotHashBefore
  NetworkRequests=0
  ProductionChanges='NONE'
} | Format-List
Write-Host '=== REGION AND OVERLAP COUNTS (SOURCE URLs, NOT UNIQUE CHANNELS) ==='
$classified | Group-Object Region,Class | Sort-Object Name |
  Select-Object @{n='RegionAndClass';e={$_.Name}},Count | Format-Table -AutoSize
Write-Host "=== FIRST $ShowNew POTENTIALLY NEW CHANNELS (NOT CONTENT VERIFIED) ==="
$new | Sort-Object Region,Channel | Select-Object -First $ShowNew Region,Channel,TvgID,URLKey |
  Format-Table -AutoSize
Write-Host '=== NOTES ==='
Write-Host 'TvgID and normalized name matches identify possible alternatives, not proven identical broadcasts.'
Write-Host 'Other/unknown-region sources are preserved for later metadata review, not counted as relevant new channels.'
Write-Host 'No files written; no sources fetched; no published IPTV or running services changed.'
