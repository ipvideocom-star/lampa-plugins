#requires -Version 7.0
# Isolated W2022 HLS Relay test for exact URLKey 8BC1F6B3E3DB734C (Saturday).
# No changes to production playlist, Caddy, service 3proxy, or active 9144/9145.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$PSNativeCommandUseErrorActionPreference=$false

$base='C:\IPTV-Manager\relay\iptv_hls_relay_v02'
$csPath=Join-Path $base 'IPTV-HLS-Relay-v02.cs'
$startPath=Join-Path $base 'Start-IPTV-HLS-Relay-v02.ps1'
$config='C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\RU-Relay-Candidates-20261105-084928.json'
$root='C:\ReservLampac\IPTVPlus\RU-Relay-Fixes\Saturday-Exact-W2022'
$expectedKey='8BC1F6B3E3DB734C'
foreach($p in @($csPath,$startPath,$config)){
 if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing staging prerequisite: $p"}
}
if(@(Get-NetTCPConnection -LocalPort 9144 -State Listen -ErrorAction SilentlyContinue).Count -eq 0){throw 'Active relay 9144 is not running'}
if(@(Get-NetTCPConnection -LocalPort 9146 -State Listen -ErrorAction SilentlyContinue).Count -ne 0){throw 'Isolated test port 9146 already in use'}
if(-not(Get-Command curl.exe -ErrorAction SilentlyContinue)){throw 'curl.exe unavailable'}

# Resolve the full verified URL privately from the public feed; never print a stream URL.
$feedUrl='https://raw.githubusercontent.com/denxvofficial/IPTV/main/iptv.m3u'
$feed=(Invoke-WebRequest -Uri $feedUrl -TimeoutSec 20 -UseBasicParsing).Content
$matchesFound=[Collections.Generic.List[string]]::new()
foreach($line in ([string]$feed -split '\r?\n')){
 $url=$line.Trim()
 if($url -notmatch '^https?://'){continue}
 $key=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
     [Text.Encoding]::UTF8.GetBytes($url))).Substring(0,16)
 if($key -eq $expectedKey){$matchesFound.Add($url)}
}
if($matchesFound.Count -ne 1){throw "Expected one exact URLKey in public source feed; found $($matchesFound.Count)"}
$newUrl=$matchesFound[0]
$upstream=[Uri]$newUrl
if($upstream.Scheme -ne 'http' -or $upstream.DnsSafeHost -cne 'cb163385.amazzin.pw'){
 throw 'Verified source host and scheme unexpected'
}

$data=Get-Content -LiteralPath $config -Raw -Encoding UTF8|ConvertFrom-Json
if($data.Mode -ne 'STAGING_ONLY' -or @($data.Candidates).Count -ne 57){throw 'Original isolated Relay staging inventory changed'}
$saturday=@($data.Candidates|Where-Object{[int]$_.Index -eq 111})
if($saturday.Count -lt 1 -or $saturday[0].Route -ne 'DIRECT_W2022'){
 throw 'Original Saturday first candidate route is different'
}
$saturday[0].URL=$newUrl
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$folder=Join-Path $root "Isolated-$stamp"
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$isolatedConfig=Join-Path $folder 'RU-Relay-Candidates-ISOLATED.json'
$data|ConvertTo-Json -Depth 35 | Set-Content -LiteralPath $isolatedConfig -Encoding UTF8
$recheck=Get-Content -LiteralPath $isolatedConfig -Raw -Encoding UTF8|ConvertFrom-Json
$check=@($recheck.Candidates|Where-Object{[int]$_.Index -eq 111})
if(@($recheck.Candidates).Count -ne 57 -or $check[0].URL -cne $newUrl){throw 'Isolated candidate config serialization failed'}

$nl=[string][char]10
$crlf=[string][char]13+$nl
$source=[IO.File]::ReadAllText($csPath).Replace($crlf,$nl)
function ChangeOnce([string]$content,[string]$old,[string]$replacement,[string]$context){
 if([regex]::Matches($content,[regex]::Escape($old)).Count -ne 1){throw "Unexpected Relay C# source at $context"}
 return $content.Replace($old,$replacement)
}
$source=ChangeOnce $source 'namespace IPTVRelayPilot02' 'namespace IPTVRelayPilot08' 'namespace'
$source=ChangeOnce $source 'private readonly string prefix = "http://127.0.0.1:9144/";' 'private readonly string prefix = "http://127.0.0.1:9146/";' 'listener'
$canaryCs=Join-Path $folder 'IPTV-HLS-Relay-v02.cs'
[IO.File]::WriteAllText($canaryCs,$source,[Text.UTF8Encoding]::new($false))
$starter=[IO.File]::ReadAllText($startPath).Replace($crlf,$nl)
if(-not $starter.Contains('IPTVRelayPilot02') -or -not $starter.Contains('[string]$AccessTokenFile') -or
   -not $starter.Contains('Port 9144')){throw 'Relay starter has changed unexpectedly'}
$starter=$starter.Replace('IPTVRelayPilot02','IPTVRelayPilot08').Replace('9144','9146')
$canaryStart=Join-Path $folder 'Start-IPTV-HLS-Relay-v02.ps1'
[IO.File]::WriteAllText($canaryStart,$starter,[Text.UTF8Encoding]::new($false))
Add-Type -Path $canaryCs -ErrorAction Stop

$token=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
$tokenFile=Join-Path $folder 'private-access-token.txt'
[IO.File]::WriteAllText($tokenFile,$token,[Text.UTF8Encoding]::new($false))
$pwsh=Join-Path $PSHOME 'pwsh.exe'
if(-not(Test-Path -LiteralPath $pwsh -PathType Leaf)){throw 'PowerShell 7 executable missing'}
$csv=Join-Path $folder 'Saturday-W2022-Isolated-Relay-Full-Segments.csv'
$rows=[Collections.Generic.List[object]]::new()
$proc=$null
Write-Host '=== SATURDAY W2022 EXACT WINNER: ISOLATED RELAY ==='
Write-Host 'URLKey 8BC1F6B3E3DB734C; private Relay 9146, no Caddy or Samsung modifications.'
Write-Host '3 rounds x 2 full media segments; streamed to NUL, never saved.'

function Get-M3u([string]$address){
 $path=Join-Path $folder ('hls-'+[guid]::NewGuid().ToString('N')+'.tmp')
 try{
  $args=@('--silent','--globoff','--noproxy','*','--connect-timeout','4','--max-time','15',
   '--max-filesize','262144','--output',$path,
   '--write-out','METRIC|%{http_code}|%{url_effective}', $address)
  $output=@(& curl.exe @args 2>$null);$exitCode=$LASTEXITCODE
  $result=@($output|Where-Object{[string]$_ -like 'METRIC|*'}|Select-Object -Last 1)
  if($result.Count -eq 0){return [pscustomobject]@{OK=$false;Code='000';Text='';Effective=$address}}
  $parts=([string]$result[0])-split '\|',3
  $valid=$parts.Count -eq 3 -and $parts[1] -eq '200' -and $exitCode -eq 0 -and
   (Test-Path -LiteralPath $path)
  $body=''
  if($valid){
   $body=[IO.File]::ReadAllText($path)
   if(-not $body.TrimStart([char]0xFEFF).StartsWith('#EXTM3U')){$valid=$false}
  }
  return [pscustomobject]@{OK=$valid;Code=$(if($parts.Count -ge 2){$parts[1]}else{'000'});Text=$body;Effective=$(if($parts.Count -eq 3){$parts[2]}else{$address})}
 }finally{Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}
}
function Find-Segments([string]$address){
 $current=$address
 for($depth=0;$depth -lt 3;$depth++){
  $manifest=Get-M3u $current
  if(-not $manifest.OK){return [pscustomobject]@{OK=$false;Issue=("HLS_"+$manifest.Code);Media=@()}}
  $lines=@($manifest.Text -split '\r?\n')
  $variants=[Collections.Generic.List[string]]::new()
  $segments=[Collections.Generic.List[object]]::new()
  for($i=0;$i -lt $lines.Count;$i++){
   $line=$lines[$i].Trim()
   if($line.StartsWith('#EXT-X-KEY:') -and $line -notmatch 'METHOD=NONE'){
    return [pscustomobject]@{OK=$false;Issue='ENCRYPTED';Media=@()}
   }
   if($line.StartsWith('#EXT-X-BYTERANGE:')){
    return [pscustomobject]@{OK=$false;Issue='BYTERANGE';Media=@()}
   }
   if($line.StartsWith('#EXT-X-STREAM-INF:') -and $i+1 -lt $lines.Count){
    $rel=$lines[$i+1].Trim()
    if($rel -and -not $rel.StartsWith('#')){$variants.Add($rel)}
   }
   if($line.StartsWith('#EXTINF:') -and $i+1 -lt $lines.Count){
    $rel=$lines[$i+1].Trim()
    if(-not $rel -or $rel.StartsWith('#')){continue}
    $length=0.0
    $num=($line.Substring(8)-split ',')[0]
    [void][double]::TryParse($num,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$length)
    $resolved=[Uri]::new([Uri]$manifest.Effective,$rel)
    if($resolved.DnsSafeHost -ne '127.0.0.1' -or $resolved.Port -ne 9146){
     throw 'Isolated Relay leaked an upstream media URL'
    }
    $segments.Add([pscustomobject]@{URL=$resolved.AbsoluteUri;Duration=$length})
   }
  }
  if($segments.Count -ge 2){
   $selection=@($segments[[Math]::Max(0,$segments.Count-3)],$segments[$segments.Count-2])
   return [pscustomobject]@{OK=$true;Issue='';Media=$selection}
  }
  if($variants.Count -lt 1){
   return [pscustomobject]@{OK=$false;Issue='NO_MEDIA_SEGMENTS';Media=@()}
  }
  $next=[Uri]::new([Uri]$manifest.Effective,$variants[0])
  if($next.DnsSafeHost -ne '127.0.0.1' -or $next.Port -ne 9146){throw 'Relay leaked upstream variant'}
  $current=$next.AbsoluteUri
 }
 return [pscustomobject]@{OK=$false;Issue='TOO_MANY_VARIANTS';Media=@()}
}
function DownloadSegment([string]$url){
 $args=@('--silent','--globoff','--noproxy','*','--connect-timeout','4','--max-time','28',
  '--max-filesize','16777216','--output','NUL',
  '--write-out','METRIC|%{http_code}|%{time_total}|%{size_download}', $url)
 $output=@(& curl.exe @args 2>$null);$exitCode=$LASTEXITCODE
 $result=@($output|Where-Object{[string]$_ -like 'METRIC|*'}|Select-Object -Last 1)
 if($result.Count -lt 1){return [pscustomobject]@{Ok=$false;Code='000';Time=0;Bytes=0;Exit=$exitCode}}
 $parts=([string]$result[0])-split '\|'
 if($parts.Count -ne 4){throw 'Invalid curl segment metrics'}
 $ci=[Globalization.CultureInfo]::InvariantCulture
 $secs=[double]::Parse($parts[2],$ci)
 $bytes=[double]::Parse($parts[3],$ci)
 return [pscustomobject]@{Ok=($exitCode -eq 0 -and $parts[1] -eq '200' -and $bytes -gt 0);Code=$parts[1];Time=$secs;Bytes=[int64]$bytes;Exit=$exitCode}
}
try{
 $proc=Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile','-NonInteractive','-File',$canaryStart,'-CandidatesPath',$isolatedConfig,'-AccessTokenFile',$tokenFile) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $folder 'stdout-private.log') -RedirectStandardError (Join-Path $folder 'stderr-private.log')
 $ready=$false
 for($attempt=0;$attempt -lt 80;$attempt++){
  $proc.Refresh()
  if($proc.HasExited){break}
  if(@(Get-NetTCPConnection -LocalPort 9146 -State Listen -ErrorAction SilentlyContinue).Count){$ready=$true;break}
  Start-Sleep -Milliseconds 250
 }
 if(-not $ready){throw "Isolated Relay startup failed; logs are in $folder"}
 $health=Invoke-RestMethod -Uri ('http://127.0.0.1:9146/iptv-relay/p/'+$token+'/health') -TimeoutSec 12 -NoProxy
 if($health.channels -ne 28 -or $health.candidates -ne 57){throw 'Isolated Relay health mismatch'}
 Write-Host 'Isolated Relay HEALTH: 28 channels, 57 candidates; listener ready.'
 $url='http://127.0.0.1:9146/iptv-relay/p/'+$token+'/channel/111.m3u8'
 for($round=1;$round -le 3;$round++){
  $m=Find-Segments $url
  if(-not $m.OK){
    Write-Host ('ROUND ' + $round + ': HLS error ' + $m.Issue)
   $rows.Add([pscustomobject]@{Round=$round;Segment=0;HTTP='NOT_TESTED';Exit=-1;Bytes=0;Seconds=0;Duration=0;SpeedRatio=0;Pass=$false;Issue=$m.Issue})
  }else{
   for($i=0;$i -lt 2;$i++){
    $part=$m.Media[$i]
    $t=DownloadSegment $part.URL
    $ratio=if($t.Ok -and $t.Time -gt 0 -and $part.Duration -gt 0){$part.Duration/$t.Time}else{0}
    $pass=$t.Ok -and $ratio -ge 1.5
    $rows.Add([pscustomobject]@{
     Round=$round;Segment=$i+1;HTTP=$t.Code;Exit=$t.Exit;Bytes=$t.Bytes
     Seconds=[Math]::Round($t.Time,2);Duration=[Math]::Round($part.Duration,2)
     SpeedRatio=[Math]::Round($ratio,2);Pass=$pass;Issue=''
    })
     Write-Host ('ROUND ' + $round + ' SEGMENT ' + ($i + 1) + ': HTTP=' + $t.Code + ', exit=' + $t.Exit + ', bytes=' + $t.Bytes + ', speed=' + [Math]::Round($ratio,2) + 'x, pass=' + $pass)
   }
  }
  if($round -lt 3){Start-Sleep -Seconds 6}
 }
 $rows|Export-Csv -LiteralPath $csv -Encoding UTF8 -NoTypeInformation
 $passCount=@($rows|Where-Object Pass).Count
 Write-Host ''
 Write-Host '=== ISOLATED SATURDAY FULL-SEGMENT RESULT ==='
 Write-Host ("Passing complete segments: {0}/6" -f $passCount)
 Write-Host "REPORT: $csv"
 Write-Host 'Samsung and production IPTV were not modified.'
}catch{
 Write-Host ('CANARY_ERROR: ' + $_.Exception.Message)
 Write-Host ('CANARY_ERROR_AT_LINE: ' + $_.InvocationInfo.ScriptLineNumber)
 throw
}finally{
 if($rows.Count -gt 0){$rows | Export-Csv -LiteralPath $csv -Encoding UTF8 -NoTypeInformation}
 if($proc){
  $proc.Refresh()
  if(-not $proc.HasExited){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue}
  $proc.Dispose()
 }
 Remove-Item -LiteralPath $tokenFile -Force -ErrorAction SilentlyContinue
 Write-Host 'Isolated port 9146 stopped (if started).'
 Write-Host 'CADDY / PLAYLISTS / RELAY 9144+9145 / 3PROXY: UNCHANGED'
}
