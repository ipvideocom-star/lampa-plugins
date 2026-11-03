#requires -Version 7.0
# W2022: publish existing Managed RU/UA additions under original stable playlist URLs.
# Keeps every original UA/RU item verbatim, including EXTVLCOPT; atomic backup/rollback.
# Staged by default. -Publish explicitly enables publication and SHA HTTPS verification.
[CmdletBinding()]
param([switch]$Publish)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$pubDir='C:\IPTV-Manager\public\playlists'
$managed='C:\ReservLampac\IPTVPlus\Managed'
$root='C:\ReservLampac\IPTVPlus\GoLive'
$files=@{UA='IPTV-UA.m3u';RU='IPTV-RU-Pilot-v1.m3u';Combined='IPTV-UA-RU-Pilot-v1.m3u'}
$urls=@{UA='https://lampa.v6.army/iptv/playlists/IPTV-UA.m3u';RU='https://lampa.v6.army/iptv/playlists/IPTV-RU-Pilot-v1.m3u';Combined='https://lampa.v6.army/iptv/playlists/IPTV-UA-RU-Pilot-v1.m3u'}
$baseline=@{UA=84;RU=47;Combined=131}
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash}
function Key([string]$x){
  $x=$x.Normalize([Text.NormalizationForm]::FormKC).Replace('Ё','Е').Replace('ё','е').ToLowerInvariant()
  $x=[regex]::Replace($x,'(?i)\s*(?:\(?\b(?:4k|uhd|fhd|hd|sd|1080p|720p|2160p)\b\)?)$','')
  ([regex]::Replace($x,'[^\p{L}\p{Nd}+\-]+',' ')).Trim()
}
function ReadList([string]$path){
  $lines=[IO.File]::ReadAllLines($path,[Text.Encoding]::UTF8)
  if($lines.Count -lt 2 -or -not $lines[0].TrimStart([char]0xFEFF).StartsWith('#EXTM3U')){
    throw "Invalid M3U: $path"
  }
  $items=[Collections.Generic.List[object]]::new()
  $pending=[Collections.Generic.List[string]]::new()
  $active=$false
  foreach($raw in $lines){
    $line=$raw.Trim()
    if($line.StartsWith('#EXTINF:')){
      if($active){throw "Unpaired EXTINF: $path"}
      $pending.Clear();$pending.Add($raw);$active=$true
      continue
    }
    if(-not $active -or -not $line){continue}
    if($line.StartsWith('#')){$pending.Add($raw);continue}
    $uri=$null
    if(-not [Uri]::TryCreate($line,[UriKind]::Absolute,[ref]$uri) -or
        $uri.Scheme -notin @('http','https') -or
        -not [string]::IsNullOrWhiteSpace($uri.UserInfo) -or
        $uri.AbsoluteUri.Length -gt 4096){
      throw "Invalid URL in $path"
    }
    $head=$pending[0]
    $pos=$head.LastIndexOf(',')
    if($pos -lt 0){throw "Missing channel name in $path"}
    $name=$head.Substring($pos+1).Trim()
    if(-not $name){throw "Empty channel name in $path"}
    $items.Add([pscustomobject]@{
      Name=$name;Key=(Key $name);Url=$uri.AbsoluteUri
      Block=@($pending.ToArray())+@($raw)
    })
    $pending.Clear();$active=$false
  }
  if($active){throw "Incomplete M3U in $path"}
  return $items.ToArray()
}
function WriteList([string]$target,[object[]]$items){
  $lines=[Collections.Generic.List[string]]::new();$lines.Add('#EXTM3U')
  foreach($item in $items){foreach($l in $item.Block){$lines.Add([string]$l)}}
  $crlf=[string][char]13+[string][char]10
  [IO.File]::WriteAllText($target,($lines -join $crlf)+$crlf,[Text.UTF8Encoding]::new($false))
}
function HttpMatches([string]$path,[string]$url){
  $tmp=Join-Path $root ('.http-'+[guid]::NewGuid().ToString('N')+'.tmp')
  try{
    & curl.exe -fLsS --connect-timeout 8 --max-time 35 --max-filesize 3000000 -H 'Accept-Encoding: identity' -H 'Cache-Control: no-cache' -o $tmp ($url+'?verify='+[guid]::NewGuid().ToString('N'))
    return ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tmp -PathType Leaf) -and (Hash $path) -eq (Hash $tmp))
  }finally{if(Test-Path -LiteralPath $tmp -PathType Leaf){Remove-Item -LiteralPath $tmp -Force}}
}
if((Get-CimInstance Win32_OperatingSystem).Caption -notmatch '2022'){throw 'Windows Server 2022 required'}
New-Item -ItemType Directory -Path $root -Force | Out-Null
$orig=@{};$source=@{}
foreach($name in @('UA','RU','Combined')){
  $p=Join-Path $pubDir $files[$name]
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing existing $name"}
  $orig[$name]=@(ReadList $p)
  if($orig[$name].Count -ne $baseline[$name]){throw "Changed baseline $name; no publication"}
}
foreach($name in @('UA','RU')){
  $p=Join-Path $managed ($name+'.m3u')
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){throw "Managed input missing: $p"}
  $source[$name]=@(ReadList $p)
}
$usedUrls=@{}
foreach($name in @('UA','RU')){foreach($item in $orig[$name]){$usedUrls[$item.Url]=$item.Key}}
$output=@{};$summary=@{};$q=[Collections.Generic.List[object]]::new()
foreach($name in @('UA','RU')){
  $items=[Collections.Generic.List[object]]::new()
  $keys=@{}
  foreach($item in $orig[$name]){$items.Add($item);$keys[$item.Key]=$true}
  $added=0;$duplicate=0;$quarantined=0
  foreach($item in @($source[$name] | Sort-Object Name,Url)){
    if($keys.ContainsKey($item.Key)){$duplicate++;continue}
    if($usedUrls.ContainsKey($item.Url) -and $usedUrls[$item.Url] -ne $item.Key){
      $quarantined++
      $q.Add([pscustomobject]@{Region=$name;Channel=$item.Name;Reason='SHARED_STREAM_WITH_OTHER_NAME'})
      continue
    }
    $items.Add($item);$keys[$item.Key]=$true;$usedUrls[$item.Url]=$item.Key;$added++
  }
  $output[$name]=$items.ToArray()
  $summary[$name]=[ordered]@{Before=$orig[$name].Count;Managed=$source[$name].Count;Added=$added;Overlap=$duplicate;Quarantine=$quarantined;After=$items.Count}
}
# Preserve the original combined playlist exactly; append only genuinely new entries.
# Rebuilding combined from two regional files might otherwise rewrite 131 established entries.
$combined=[Collections.Generic.List[object]]::new()
$combinedKeys=@{}
$combinedUrls=@{}
foreach($item in $orig['Combined']){
  $combined.Add($item)
  $combinedKeys[$item.Key]=$true
  $combinedUrls[$item.Url]=$true
}
foreach($name in @('UA','RU')){
  for($i=$orig[$name].Count;$i -lt $output[$name].Count;$i++){
    $item=$output[$name][$i]
    if($combinedKeys.ContainsKey($item.Key) -or $combinedUrls.ContainsKey($item.Url)){continue}
    $combined.Add($item)
    $combinedKeys[$item.Key]=$true
    $combinedUrls[$item.Url]=$true
  }
}
$output['Combined']=$combined.ToArray()
Write-Host '=== EXPANSION PREFLIGHT (BEFORE PUBLISH) ==='
Write-Host ("RU: existing={0}, source={1}, new={2}, final={3}" -f $summary['RU'].Before,$summary['RU'].Managed,$summary['RU'].Added,$summary['RU'].After)
Write-Host ("UA: existing={0}, source={1}, new={2}, final={3}" -f $summary['UA'].Before,$summary['UA'].Managed,$summary['UA'].Added,$summary['UA'].After)
Write-Host ("Combined: existing={0}, expanded={1}" -f $orig['Combined'].Count,$output['Combined'].Count)
if($output['Combined'].Count -le $orig['Combined'].Count){
  throw 'No new unique channels; refusing pointless publication. Existing playlists untouched.'
}
$stage=@{};$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')
foreach($name in @('UA','RU','Combined')){
  $tmp=Join-Path $root ('.stage-'+$name+'.m3u')
  WriteList $tmp $output[$name]
  $check=@(ReadList $tmp)
  if($check.Count -ne $output[$name].Count){throw "Stage count mismatch: $name"}
  for($i=0;$i -lt $orig[$name].Count;$i++){
    if(($orig[$name][$i].Block -join [char]10) -cne ($check[$i].Block -join [char]10)){
      throw "Original $name entry changed: $i"
    }
  }
  $stage[$name]=$tmp
}
$published='NO';$backups=@{};$changed=[Collections.Generic.List[string]]::new()
$backupDir=''
if($Publish){
  $backupDir=Join-Path $root ('PublishedBackups\'+$stamp)
  New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
  foreach($name in @('UA','RU','Combined')){
    $live=Join-Path $pubDir $files[$name]
    $backup=Join-Path $backupDir $files[$name]
    Copy-Item -LiteralPath $live -Destination $backup -ErrorAction Stop
    if((Hash $live) -ne (Hash $backup)){throw "Backup check failed: $name"}
    $backups[$name]=$backup
  }
  try{
    foreach($name in @('UA','RU','Combined')){
      $live=Join-Path $pubDir $files[$name]
      if((Hash $live) -eq (Hash $stage[$name])){continue}
      $tmp=Join-Path $pubDir ('.replace-'+$name+'.tmp')
      Copy-Item -LiteralPath $stage[$name] -Destination $tmp -ErrorAction Stop
      if((Hash $tmp) -ne (Hash $stage[$name])){throw "Temp checksum mismatch: $name"}
      $replacedBackup=Join-Path $backupDir ('replaced-'+$files[$name])
      [IO.File]::Replace($tmp,$live,$replacedBackup)
      $changed.Add($name)
      if((Hash $live) -ne (Hash $stage[$name])){throw "Post-replace checksum mismatch: $name"}
    }
    foreach($name in @('UA','RU','Combined')){
      $live=Join-Path $pubDir $files[$name]
      if(-not (HttpMatches $live $urls[$name])){throw "HTTPS mismatch for $name"}
    }
    $published='HTTPS_VERIFIED'
  }catch{
    $reason=$_.Exception.Message
    foreach($name in $changed){
      $live=Join-Path $pubDir $files[$name]
      $tmp=Join-Path $pubDir ('.rollback-'+$name+'.tmp')
      Copy-Item -LiteralPath $backups[$name] -Destination $tmp -ErrorAction Stop
      $rollbackBackup=Join-Path $backupDir ('failed-version-'+$files[$name])
      [IO.File]::Replace($tmp,$live,$rollbackBackup)
      if((Hash $live) -ne (Hash $backups[$name])){throw "Rollback checksum mismatch for $name"}
    }
    throw "Publication rolled back: $reason"
  }
}
$report=[ordered]@{
  UpdatedUtc=[DateTime]::UtcNow.ToString('o');Computer=$env:COMPUTERNAME
  RU=$summary['RU'];UA=$summary['UA'];Combined=$output['Combined'].Count
  Published=$published;OriginalChannelsPreserved=$true
  W2019P3Bulk184Imported=$false
  NetworkReverified=$false;PlaybackVerified=$false;StreamingRightsVerified=$false
  Backup=$backupDir;Changed=@($changed.ToArray());Quarantine=@($q.ToArray());URL=$urls
}
[IO.File]::WriteAllText((Join-Path $root 'latest-expansion.json'),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
foreach($tmp in $stage.Values){if(Test-Path -LiteralPath $tmp -PathType Leaf){Remove-Item -LiteralPath $tmp -Force}}
Write-Host '=== IPTV EXPANSION V2 RESULT ==='
Write-Host ("RU: {0} + {1} = {2}" -f $summary['RU'].Before,$summary['RU'].Added,$summary['RU'].After)
Write-Host ("UA: {0} + {1} = {2}" -f $summary['UA'].Before,$summary['UA'].Added,$summary['UA'].After)
Write-Host "CombinedChannels: $($output['Combined'].Count)"
Write-Host "Published: $published"
Write-Host "Backup: $backupDir"
Write-Host 'W2019P3Bulk184Imported: FALSE'
Write-Host 'PlaybackVerified: FALSE'
Write-Host "ChromePlaylist: $($urls['Combined'])"
