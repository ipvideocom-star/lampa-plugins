#requires -Version 7.0
# Read-only Saturday source selection using IPTV Manager's EXISTING local discovery.
# Full HLS media segments are discarded to NUL. No changes to live services or playlists.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$PSNativeCommandUseErrorActionPreference = $false
$pilot = 'C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\IPTV-UA-RU-Relay-v02-257-STAGING-NOT-PUBLISHED.m3u'
$stagePath = 'C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\First-Expansion-20261105-215516-d198e6bb\RU-Relay-Candidates-FIRST-STAGING.json'
$catalogPath = 'C:\ReservLampac\IPTVPlus\Discovery\source-discovery-20261103-174853-693718c1.json'
$reportDir = 'C:\ReservLampac\IPTVPlus\RU-Network-Diagnostics'
foreach($p in @($pilot,$stagePath,$catalogPath)) {
 if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Required existing inventory missing: $p"}
}
if(-not(Get-Command curl.exe -ErrorAction SilentlyContinue)){throw 'curl.exe missing'}
$pilotNames=[Collections.Generic.List[string]]::new()
foreach($line in [IO.File]::ReadAllLines($pilot,[Text.Encoding]::UTF8)) {
 if($line.StartsWith('#EXTINF:')){$pilotNames.Add($line.Substring($line.LastIndexOf(',')+1).Trim())}
}
if($pilotNames.Count -ne 257 -or $pilotNames[234] -cne 'Суббота') {
 throw 'Current playlist channel position 235 is not the expected Saturday'
}
$stage=Get-Content -LiteralPath $stagePath -Encoding UTF8 -Raw|ConvertFrom-Json
$catalog=Get-Content -LiteralPath $catalogPath -Encoding UTF8 -Raw|ConvertFrom-Json
if($stage.Mode -ne 'STAGING_ONLY' -or @($stage.Candidates).Count -ne 65 -or
   @($catalog.Records).Count -ne 1949) {throw 'Inventory baseline has changed'}
function Is-Saturday([string]$name) {
 $n=$name.Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant().Trim()
 $n=$n -replace '\s*(?:\(|\[)?(?:hd|fhd|sd|uhd|4k|1080p|720p)(?:\)|\])?\s*$',''
 $n=$n -replace '\s+',' '
 return ($n -match '^суббота!?$')
}
$items=[Collections.Generic.List[object]]::new()
$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
function Register-Source([string]$url,[string]$label,[string]$agent,[string]$referer) {
 $uri=$null
 if(-not[Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or
    $uri.Scheme -notin @('http','https') -or $uri.UserInfo -or
    $uri.DnsSafeHost -notmatch '\.' -or $uri.HostNameType -eq 'IPv6') {return}
 if($uri.DnsSafeHost -match '(?i)(^localhost$|\.local$|\.internal$)'){return}
 if(-not $seen.Add($uri.AbsoluteUri)){return}
 $key=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($url))).Substring(0,16)
 $items.Add([pscustomobject]@{Url=$url;Host=$uri.DnsSafeHost.ToLowerInvariant();Label=$label;Key=$key;Agent=$agent;Referer=$referer})
}
$staged=@($stage.Candidates|Where-Object{[int]$_.Index -eq 111 -and $_.Route -eq 'DIRECT_W2022'})
for($i=0;$i -lt $staged.Count;$i++){
 Register-Source ([string]$staged[$i].URL) ("RELAY_CANDIDATE_"+$i) '' ''
}
$knownCount=$items.Count
$other=[Collections.Generic.List[object]]::new()
foreach($r in $catalog.Records){
 if(-not(Is-Saturday ([string]$r.Channel))){continue}
 $uri=$null
 if(-not [Uri]::TryCreate([string]$r.URL,[UriKind]::Absolute,[ref]$uri) -or
   $uri.Scheme -notin @('http','https') -or $uri.UserInfo){continue}
 $other.Add($r)
}
# Favor truly different origin hosts, not ten links to the same overloaded CDN.
$usedHosts=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($c in $items){[void]$usedHosts.Add($c.Host)}
foreach($r in $other){
 if($items.Count -ge 10){break}
 $u=[Uri]$r.URL
 if($usedHosts.Contains($u.DnsSafeHost)){continue}
 $prev=$items.Count
 Register-Source ([string]$r.URL) 'INDEPENDENT_DISCOVERY' ([string]$r.UserAgent) ([string]$r.Referrer)
 if($items.Count -gt $prev){[void]$usedHosts.Add($u.DnsSafeHost)}
}
foreach($r in $other){
 if($items.Count -ge 10){break}
 Register-Source ([string]$r.URL) 'OTHER_DISCOVERY' ([string]$r.UserAgent) ([string]$r.Referrer)
}
if($items.Count -eq 0){throw 'No Saturday sources in existing inventory'}
$tag=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
New-Item -ItemType Directory -Path $reportDir -Force|Out-Null
$csv=Join-Path $reportDir ("RU-Saturday-Full-Source-Selection-"+$tag+".csv")
$summary=Join-Path $reportDir ("RU-Saturday-Source-Summary-"+$tag+".txt")
$results=[Collections.Generic.List[object]]::new()
function Curl-Measure([string]$url,[bool]$media,[object]$source){
 $file=Join-Path $env:TEMP ('sat-hls-'+[guid]::NewGuid().ToString('N')+'.tmp')
 $args=@('--silent','--globoff','--location','--max-redirs','2','--proto-redir','=http,https',
    '--noproxy','*','--connect-timeout','4','--max-time',$(if($media){'24'}else{'10'}),
    '--max-filesize',$(if($media){'16777216'}else{'262144'}),
    '--output',$(if($media){'NUL'}else{$file}),
    '--write-out','RESULT|%{http_code}|%{time_starttransfer}|%{time_total}|%{size_download}|%{url_effective}')
 if($source.Agent){$args+=@('--user-agent',[string]$source.Agent)}
 if($source.Referer){$args+=@('--referer',[string]$source.Referer)}
 $args+=$url
 try{
  $lines=@(& curl.exe @args 2>$null)
  $exitCode=$LASTEXITCODE
  $match=@($lines|Where-Object{[string]$_ -like 'RESULT|*'}|Select-Object -Last 1)
  if($match.Count -eq 0){return [pscustomobject]@{OK=$false;HTTP='000';Exit=$exitCode;Time=0;Bytes=0;Text='';Final=$url}}
  $v=([string]$match[0])-split '\|',6
  if($v.Count -ne 6){throw 'Malformed curl result'}
  $ci=[Globalization.CultureInfo]::InvariantCulture
  $seconds=[double]::Parse($v[3],$ci)
  $bytes=[double]::Parse($v[4],$ci)
  $body=''
  $ok=$exitCode -eq 0 -and $v[1] -eq '200' -and $bytes -gt 0
  if(-not $media -and $ok){
   $body=[IO.File]::ReadAllText($file)
   if(-not $body.TrimStart([char]0xFEFF).StartsWith('#EXTM3U')){$ok=$false}
  }
  return [pscustomobject]@{OK=$ok;HTTP=$v[1];Exit=$exitCode;Time=$seconds;Bytes=[int64]$bytes;Text=$body;Final=$v[5]}
 }finally{Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue}
}
function Get-Segments([object]$source){
 $url=$source.Url
 for($level=0;$level -lt 3;$level++){
  $m=Curl-Measure $url $false $source
  if(-not $m.OK){return [pscustomobject]@{OK=$false;Error=("MANIFEST_HTTP_"+$m.HTTP+"_EXIT_"+$m.Exit);Segments=@()}}
  $lines=@($m.Text -split '\r?\n')
  $variants=[Collections.Generic.List[string]]::new()
  $segments=[Collections.Generic.List[object]]::new()
  $encrypted=$false
  $byteRange=$false
  for($i=0;$i -lt $lines.Count;$i++){
   $line=$lines[$i].Trim()
   if($line.StartsWith('#EXT-X-KEY:METHOD=') -and $line -notmatch 'METHOD=NONE'){$encrypted=$true}
   if($line.StartsWith('#EXT-X-BYTERANGE:')){$byteRange=$true}
   if($line.StartsWith('#EXT-X-STREAM-INF:') -and $i+1 -lt $lines.Count){
    $variant=$lines[$i+1].Trim()
    if($variant -and -not $variant.StartsWith('#')){$variants.Add($variant)}
   }
   if($line.StartsWith('#EXTINF:') -and $i+1 -lt $lines.Count){
    $durationRaw=($line.Substring(8)-split ',')[0]
    $duration=0.0
    [void][double]::TryParse($durationRaw,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$duration)
    $part=$lines[$i+1].Trim()
    if($part -and -not $part.StartsWith('#')){
     $full=[Uri]::new([Uri]$m.Final,$part)
     if($full.Scheme -notin @('http','https')){continue}
     $segments.Add([pscustomobject]@{URL=$full.AbsoluteUri;Duration=$duration})
    }
   }
  }
  if($encrypted){return [pscustomobject]@{OK=$false;Error='ENCRYPTED_STREAM_NOT_EVALUATED';Segments=@()}}
  if($byteRange){return [pscustomobject]@{OK=$false;Error='BYTERANGE_STREAM_NOT_EVALUATED';Segments=@()}}
  if($segments.Count -ge 2){
   # Use segments behind the live edge; test two distinct full segments.
   $select=@($segments[[Math]::Max(0,$segments.Count-3)],$segments[$segments.Count-2])
   return [pscustomobject]@{OK=$true;Error='';Segments=$select}
  }
  if($segments.Count -eq 1){return [pscustomobject]@{OK=$true;Error='ONLY_ONE_SEGMENT';Segments=@($segments[0])}}
  if($variants.Count -eq 0){return [pscustomobject]@{OK=$false;Error='NO_MEDIA_SEGMENTS';Segments=@()}}
  $url=([Uri]::new([Uri]$m.Final,$variants[0])).AbsoluteUri
 }
 return [pscustomobject]@{OK=$false;Error='TOO_MANY_MASTER_LEVELS';Segments=@()}
}
Write-Host '=== SATURDAY: EXISTING ALTERNATIVE SOURCES, FULL SEGMENTS ==='
Write-Host ("Candidates: {0} (existing Relay sources: {1}; independent-discovery names: {2})" -f $items.Count,$knownCount,$other.Count)
Write-Host 'No publication or service modifications. No video saved.'
foreach($source in $items){
 $manifest=Get-Segments $source
 $passes=0;$rates=[Collections.Generic.List[double]]::new()
 $statuses=[Collections.Generic.List[string]]::new()
 $i=0
 if($manifest.OK){
  foreach($seg in $manifest.Segments){
   $i++
   $download=Curl-Measure $seg.URL $true $source
   $ratio=if($download.OK -and $download.Time -gt 0 -and $seg.Duration -gt 0){$seg.Duration/$download.Time}else{0}
   if($download.OK -and $ratio -ge 1.5){$passes++;$rates.Add($ratio)}
   $statuses.Add(("segment{0}:HTTP{1}/exit{2}/{3:N1}s" -f $i,$download.HTTP,$download.Exit,$download.Time))
   $results.Add([pscustomobject]@{
    Candidate=$source.Label;Host=$source.Host;URLKey=$source.Key;Segment=$i
    HLSHTTP='200';SegmentHTTP=$download.HTTP;CurlExit=$download.Exit
    Bytes=$download.Bytes;DownloadSeconds=[Math]::Round($download.Time,2)
    MediaDurationSeconds=[Math]::Round($seg.Duration,2);RealTimeSpeedRatio=[Math]::Round($ratio,2)
    Accept=($download.OK -and $ratio -ge 1.5);Reason=''
   })
  }
 }else{
  $statuses.Add($manifest.Error)
  $results.Add([pscustomobject]@{
   Candidate=$source.Label;Host=$source.Host;URLKey=$source.Key;Segment=0
   HLSHTTP='FAILED';SegmentHTTP='NOT_TESTED';CurlExit=-1;Bytes=0
   DownloadSeconds=0;MediaDurationSeconds=0;RealTimeSpeedRatio=0
   Accept=$false;Reason=$manifest.Error
  })
 }
 Write-Host ('{0,-23} {1,-25} reliable {2}/2 | {3}' -f $source.Label,$source.Host,$passes,($statuses -join '; '))
}
$results|Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
$success=@($results|Group-Object URLKey|Where-Object{
 @($_.Group|Where-Object Accept).Count -eq 2 -and @($_.Group).Count -eq 2
})
$alternatives=@($success|Where-Object{$_.Group[0].Candidate -ne 'RELAY_CANDIDATE_0'})
$report=[Collections.Generic.List[string]]::new()
$report.Add('SATURDAY SOURCE SELECTION - FULL HLS SEGMENTS (W2022 DIRECT)')
$report.Add('HTTP 200 alone is not a pass. Two complete, distinct segments each >=1.5x real time required.')
$report.Add('Technical network verification only; broadcast identity and Samsung playback not proven.')
$report.Add('')
$report.Add("Sources tested: $($items.Count); passing 2/2: $($success.Count); passing alternatives: $($alternatives.Count)")
foreach($g in $alternatives){
 $r=$g.Group[0]
 $minRatio=($g.Group|Measure-Object RealTimeSpeedRatio -Minimum).Minimum
 $report.Add(('POTENTIAL: {0} | {1} | URLKey {2} | minimum real-time ratio {3}' -f $r.Candidate,$r.Host,$r.URLKey,$minRatio))
}
if($alternatives.Count -eq 0){$report.Add('NO_CONFIRMED_REPLACEMENT: existing inventory did not yield two fast full segments. Do not switch Samsung.')}
$report.Add('')
$report.Add('CADDY / RELAY 9144+9145 / 3PROXY / PLAYLISTS: UNCHANGED')
$report.Add("CSV: $csv")
[IO.File]::WriteAllLines($summary,$report,[Text.UTF8Encoding]::new($true))
Write-Host ''
Write-Host '=== SATURDAY SOURCE SELECTION FINISHED ==='
$report|Where-Object{$_ -match '^(Sources tested:|POTENTIAL:|NO_CONFIRMED_REPLACEMENT:)'}|ForEach-Object{Write-Host $_}
Write-Host "SUMMARY: $summary"
Write-Host "DETAILS: $csv"
Write-Host 'NO PRODUCTION CHANGES'
