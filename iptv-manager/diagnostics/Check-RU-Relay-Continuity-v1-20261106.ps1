#requires -Version 7.0
# Read-only comparison of consecutive HLS segments: W2022 upstream vs Caddy Relay.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$PSNativeCommandUseErrorActionPreference=$false
$pilot='C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\IPTV-UA-RU-Relay-v02-257-STAGING-NOT-PUBLISHED.m3u'
$json='C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\First-Expansion-20261105-215516-d198e6bb\RU-Relay-Candidates-FIRST-STAGING.json'
$dest='C:\ReservLampac\IPTVPlus\RU-Network-Diagnostics'
foreach($file in @($pilot,$json)){if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw "Missing file: $file"}}
if(-not(Get-Command curl.exe -ErrorAction SilentlyContinue)){throw 'curl.exe unavailable'}
$entries=[Collections.Generic.List[object]]::new()
$pending=$null
foreach($raw in [IO.File]::ReadAllLines($pilot,[Text.Encoding]::UTF8)){
 $line=$raw.Trim()
 if($line.StartsWith('#EXTINF:')){$pending=$line.Substring($line.LastIndexOf(',')+1).Trim();continue}
 if($null -ne $pending -and $line -match '^https?://'){
  $entries.Add([pscustomobject]@{I=$entries.Count+1;N=$pending;U=$line});$pending=$null
 }
}
if($entries.Count -ne 257){throw 'Expected 257 channels in pilot'}
$data=Get-Content -LiteralPath $json -Raw -Encoding UTF8 | ConvertFrom-Json
if($data.Mode -ne 'STAGING_ONLY' -or @($data.Candidates).Count -ne 65){throw 'Unexpected Relay staging'}
$tests=[Collections.Generic.List[object]]::new()
foreach($p in @(@(206,82,'Первый'),@(235,111,'Суббота'))){
 $c=$entries[[int]$p[0]-1]
 if($c.N -cne [string]$p[2]){throw "Unexpected channel title at $($p[0])"}
 $uri=[Uri]$c.U
 if($uri.Scheme -ne 'https' -or $uri.DnsSafeHost -cne 'lampa.v6.army' -or
    $uri.AbsolutePath -notmatch ('^/iptv-relay/p/[0-9a-f]{64}/channel/'+[string]$p[1]+'\.m3u8$') -or $uri.Query){
    throw "Protected Relay URL mismatch for channel $($p[0])"
 }
 $choices=@($data.Candidates|Where-Object{[int]$_.Index -eq [int]$p[1]})
 if($choices.Count -lt 1 -or $choices[0].Route -ne 'DIRECT_W2022'){throw "No direct candidate for channel $($p[0])"}
 $tests.Add([pscustomobject]@{I=[int]$p[0];N=$c.N;Route='UPSTREAM';U=[string]$choices[0].URL})
 $tests.Add([pscustomobject]@{I=[int]$p[0];N=$c.N;Route='RELAY';U=$c.U})
}
$tag=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
New-Item -ItemType Directory -Path $dest -Force|Out-Null
$tmp=Join-Path $dest ('.temporary-continuity-'+$tag)
New-Item -ItemType Directory -Path $tmp -Force|Out-Null
$csv=Join-Path $dest "RU-Continuity-Timings-$tag.csv"
$txt=Join-Path $dest "RU-Continuity-Summary-$tag.txt"
$results=[Collections.Generic.List[object]]::new()
function CurlProbe([string]$url,[string]$route,[bool]$segment){
 $file=Join-Path $tmp ([guid]::NewGuid().ToString('N')+'.part')
 $args=@('--silent','--globoff','--location','--max-redirs','3','--connect-timeout','4',
   '--max-time',$(if($segment){'20'}else{'12'}),
   '--max-filesize',$(if($segment){'6291456'}else{'262144'}),
   '--noproxy','*','--output',$file,
   '--write-out','STAT|%{http_code}|%{time_starttransfer}|%{time_total}|%{size_download}|%{url_effective}')
 if($route -eq 'RELAY'){$args+=@('--resolve','lampa.v6.army:443:127.0.0.1')}
 if($segment){$args+=@('--range','0-524287')}
 $args+=$url
 try{
  $output=@(& curl.exe @args 2>$null)
  $exitCode=$LASTEXITCODE
  $last=@($output|Where-Object{[string]$_ -like 'STAT|*'}|Select-Object -Last 1)
  if($last.Count -lt 1){return [pscustomobject]@{OK=$false;HTTP='000';Exit=$exitCode;TTFB=0;Seconds=0;Bytes=0;Body='';Final=$url}}
  $v=([string]$last[0]) -split '\|',6
  if($v.Count -lt 6){throw 'Invalid curl measurement format'}
  $ci=[Globalization.CultureInfo]::InvariantCulture
  $first=[double]::Parse($v[2],$ci);$time=[double]::Parse($v[3],$ci);$bytes=[double]::Parse($v[4],$ci)
  $ok=($exitCode -eq 0 -and $v[1] -in @('200','206') -and $bytes -gt 0)
  $body=''
  if($ok -and -not $segment -and (Test-Path -LiteralPath $file)){$body=[IO.File]::ReadAllText($file)}
  if(-not $segment -and -not $body.TrimStart([char]0xFEFF).StartsWith('#EXTM3U')){$ok=$false}
  return [pscustomobject]@{OK=$ok;HTTP=$v[1];Exit=$exitCode;TTFB=$first;Seconds=$time;Bytes=[int64]$bytes;Body=$body;Final=$v[5]}
 }finally{Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue}
}
function FindLatest([string]$url,[string]$route){
 $current=$url
 for($d=0;$d -lt 3;$d++){
  $r=CurlProbe $current $route $false
  if(-not $r.OK){return [pscustomobject]@{OK=$false;M=$r;Seg='';ID=''}}
  $lines=@($r.Body -split '\r?\n')
  $variants=[Collections.Generic.List[string]]::new()
  $segments=[Collections.Generic.List[string]]::new()
  for($i=0;$i -lt $lines.Count-1;$i++){
   if($lines[$i].Trim().StartsWith('#EXT-X-STREAM-INF:') -and $lines[$i+1].Trim() -notmatch '^#'){$variants.Add($lines[$i+1].Trim())}
   if($lines[$i].Trim().StartsWith('#EXTINF:') -and $lines[$i+1].Trim() -notmatch '^#'){$segments.Add($lines[$i+1].Trim())}
  }
  if($segments.Count -gt 0){
   $link=([Uri]::new([Uri]$r.Final,$segments[-1])).AbsoluteUri
   if($route -eq 'RELAY' -and ([Uri]$link).DnsSafeHost -cne 'lampa.v6.army'){throw 'Relay segment URL exited local host'}
   $id=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($link))).Substring(0,12)
   return [pscustomobject]@{OK=$true;M=$r;Seg=$link;ID=$id}
  }
  if($variants.Count -eq 0){return [pscustomobject]@{OK=$false;M=$r;Seg='';ID=''}}
  $current=([Uri]::new([Uri]$r.Final,$variants[0])).AbsoluteUri
  if($route -eq 'RELAY' -and ([Uri]$current).DnsSafeHost -cne 'lampa.v6.army'){throw 'Relay variant URL exited local host'}
 }
 return [pscustomobject]@{OK=$false;M=$null;Seg='';ID=''}
}
Write-Host '=== RU IPTV HLS CONTINUITY: READ-ONLY ==='
Write-Host 'Channels 206 First and 235 Saturday; 5 rounds; 2 routes each.'
Write-Host 'Comparing segment requests, not only first manifest bytes.'
Write-Host ''
try {
 for($round=1;$round -le 5;$round++){
  foreach($test in $tests){
   $m=FindLatest $test.U $test.Route
   $s=$null
   if($m.OK){$s=CurlProbe $m.Seg $test.Route $true}
   $ok=($m.OK -and $null -ne $s -and $s.OK)
   $results.Add([pscustomobject]@{
    Channel=$test.N;Index=$test.I;Route=$test.Route;Round=$round;Status=if($ok){'OK'}else{'FAIL'}
    ManifestHTTP=if($m.M){$m.M.HTTP}else{'000'}
    SegmentHTTP=if($s){$s.HTTP}else{'NOT_TESTED'}
    SegmentExit=if($s){$s.Exit}else{-1}
    SegmentTTFB=if($s){[Math]::Round($s.TTFB,3)}else{0}
    SegmentSeconds=if($s){[Math]::Round($s.Seconds,3)}else{0}
    SegmentBytes=if($s){$s.Bytes}else{0}
    SegmentId=$m.ID
   })
   Write-Host ('{0,-8} {1,-8} round {2} | manifest {3} | segment {4} | TTFB {5:N2}s | total {6:N2}s | bytes {7}' -f $test.N,$test.Route,$round,$(if($m.M){$m.M.HTTP}else{'000'}),$(if($s){$s.HTTP}else{'-'}),$(if($s){$s.TTFB}else{0}),$(if($s){$s.Seconds}else{0}),$(if($s){$s.Bytes}else{0}))
  }
  if($round -lt 5){Start-Sleep -Seconds 10}
 }
}finally{
 $results|Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
 Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
$report=[Collections.Generic.List[string]]::new()
$report.Add('RU HLS CONTINUITY - READ ONLY')
$report.Add('5 rounds / 2 channels / upstream versus existing HTTPS Relay')
$report.Add('Each segment request asks for first 512 KiB; source may send more.')
$report.Add('W2022-local HTTPS results do not measure Samsung playback, LAN or decoder.')
$report.Add('')
foreach($group in ($results|Group-Object Channel,Route)){
 $g=@($group.Group)
 $ok=@($g|Where-Object Status -eq 'OK')
 $mean=if($ok.Count){[Math]::Round(($ok|Measure-Object -Property SegmentSeconds -Average).Average,2)}else{0}
 $fresh=@($g|Where-Object SegmentId|Select-Object -ExpandProperty SegmentId -Unique).Count
 $report.Add(('{0} {1}: OK {2}/{3}, distinct segments={4}, mean transfer={5}s' -f $g[0].Channel,$g[0].Route,$ok.Count,$g.Count,$fresh,$mean))
}
$report.Add('')
$report.Add('3PROXY, CADDY, RELAYS, MAIN AND PILOT M3U: UNCHANGED')
$report.Add("CSV: $csv")
[IO.File]::WriteAllLines($txt,$report,[Text.UTF8Encoding]::new($true))
Write-Host ''
Write-Host '=== HLS CONTINUITY COMPLETE ==='
$report|Where-Object{$_ -match '^Первый |^Суббота '}|ForEach-Object{Write-Host $_}
Write-Host "SUMMARY: $txt"
Write-Host "TIMINGS: $csv"
Write-Host 'NO CONFIGURATION CHANGES'
