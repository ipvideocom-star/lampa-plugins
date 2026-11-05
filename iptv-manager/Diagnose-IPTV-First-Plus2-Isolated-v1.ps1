#requires -Version 7.0
# Read-only HTTP verification of the isolated First +2 Relay (9145).
# Starts and stops only its own child process. Live port 9144 is untouched.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root='C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\First-Expansion-20261105-215516-d198e6bb'
$starter=Join-Path $root 'Local-Test-20261105-220321-8d485f58\Start-IPTV-HLS-Relay-v02.ps1'
$json=Join-Path $root 'RU-Relay-Candidates-FIRST-STAGING.json'
$secret='C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\Private\relay-v02-token.txt'
foreach($path in @($starter,$json,$secret)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Required file missing: $path"}}
if(@(Get-NetTCPConnection -LocalPort 9145 -State Listen -ErrorAction SilentlyContinue).Count){throw '9145 is occupied; nothing stopped'}
$token=[IO.File]::ReadAllText($secret).Trim()
if($token.Length -lt 16 -or $token -notmatch '^[A-Za-z0-9_-]+$'){throw 'Token format unexpected'}
$logDir=Join-Path $root ('Diagnostic-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $logDir -Force|Out-Null
$p=$null;$client=$null;$handler=$null
function FetchLocal([Net.Http.HttpClient]$client,[string]$url,[int]$limit){
  $uri=[Uri]$url
  if($uri.Host -cne '127.0.0.1' -or $uri.Port -ne 9145 -or $uri.Scheme -cne 'http'){throw 'REFUSED_EXTERNAL_URL'}
  $cts=[Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(21))
  $response=$null;$stream=$null
  try{
    $response=$client.GetAsync($uri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$cts.Token).GetAwaiter().GetResult()
    $code=[int]$response.StatusCode
    if($code -lt 200 -or $code -ge 300){return [pscustomobject]@{Status=$code;Bytes=[byte[]]@()}}
    $stream=$response.Content.ReadAsStreamAsync($cts.Token).GetAwaiter().GetResult()
    $buf=[byte[]]::new($limit);$read=0
    while($read -lt $limit){
      $n=$stream.ReadAsync($buf,$read,$limit-$read,$cts.Token).GetAwaiter().GetResult()
      if($n -le 0){break};$read+=$n
    }
    $out=[byte[]]::new($read);[Array]::Copy($buf,$out,$read)
    return [pscustomobject]@{Status=$code;Bytes=$out}
  }finally{if($stream){$stream.Dispose()};if($response){$response.Dispose()};$cts.Dispose()}
}
function ChildUrl([string]$base,[string]$value){
  $u=[Uri]::new([Uri]$base,$value)
  if($u.Scheme -cne 'http' -or $u.Host -cne '127.0.0.1' -or $u.Port -ne 9145){throw 'NONLOCAL_CHILD_URL'}
  return $u.AbsoluteUri
}
Write-Host '=== FIRST +2 ISOLATED DEBUG ==='
try{
  $pwsh=(Get-Process -Id $PID).Path
  $p=Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile','-NonInteractive','-File',$starter,'-CandidatesPath',$json) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logDir 'stdout-private.log') -RedirectStandardError (Join-Path $logDir 'stderr-private.log')
  $started=$false
  for($i=0;$i -lt 100;$i++){
    $p.Refresh();if($p.HasExited){break}
    if(@(Get-NetTCPConnection -LocalPort 9145 -State Listen -ErrorAction SilentlyContinue).Count){$started=$true;break}
    Start-Sleep -Milliseconds 200
  }
  if(-not $started){throw 'RELAY_START_FAILED'}
  Write-Host 'ISOLATED 9145: LISTENING'
  $handler=[Net.Http.HttpClientHandler]::new();$handler.UseProxy=$false;$handler.AllowAutoRedirect=$false
  $client=[Net.Http.HttpClient]::new($handler);$client.Timeout=[TimeSpan]::FromSeconds(24)
  $url="http://127.0.0.1:9145/iptv-relay/p/$token/channel/84.m3u8"
  $step='ROOT'
  try{
    $r=FetchLocal $client $url 65536
    Write-Host "ROOT HTTP: $($r.Status); BYTES: $($r.Bytes.Length)"
    if($r.Status -ne 200){throw 'ROOT_HTTP_ERROR'}
    $body=[Text.Encoding]::UTF8.GetString($r.Bytes)
    if(-not $body.TrimStart([char]0xFEFF).StartsWith('#EXTM3U')){throw 'ROOT_NOT_HLS'}
    if($body.Contains('#EXT-X-STREAM-INF')){
      $step='VARIANT'
      $next=$false;$child=''
      foreach($line in ($body -split '\r?\n')){
        $line=$line.Trim();if($line.StartsWith('#EXT-X-STREAM-INF')){$next=$true;continue}
        if($next -and $line -and -not $line.StartsWith('#')){$child=$line;break}
      }
      if(-not $child){throw 'VARIANT_NOT_LISTED'}
      $url=ChildUrl $url $child;$r=FetchLocal $client $url 65536
      Write-Host "VARIANT HTTP: $($r.Status); BYTES: $($r.Bytes.Length)"
      if($r.Status -ne 200){throw 'VARIANT_HTTP_ERROR'}
      $body=[Text.Encoding]::UTF8.GetString($r.Bytes)
    }
    $step='SEGMENT';$next=$false;$child=''
    foreach($line in ($body -split '\r?\n')){
      $line=$line.Trim();if($line.StartsWith('#EXTINF:')){$next=$true;continue}
      if($next -and $line -and -not $line.StartsWith('#')){$child=$line;break}
    }
    if(-not $child){throw 'SEGMENT_NOT_LISTED'}
    $url=ChildUrl $url $child;$r=FetchLocal $client $url 1504
    Write-Host "SEGMENT HTTP: $($r.Status); BYTES: $($r.Bytes.Length)"
    if($r.Status -ne 200 -and $r.Status -ne 206){throw 'SEGMENT_HTTP_ERROR'}
    $sync=$false
    for($i=0;$i -lt [Math]::Min(188,$r.Bytes.Length-376);$i++){
      if($r.Bytes[$i] -eq 71 -and $r.Bytes[$i+188] -eq 71 -and $r.Bytes[$i+376] -eq 71){$sync=$true;break}
    }
    Write-Host "TS_SYNC: $sync"
  }catch{
    Write-Host "FAILED_STEP: $step"
    Write-Host "FAILURE_TYPE: $($_.Exception.GetType().Name)"
    $message=$_.Exception.Message -replace [regex]::Escape($token),'[PRIVATE]'
    $message=$message -replace 'https?://\S+','[URL]'
    Write-Host "FAILURE: $message"
  }
}finally{
  if($client){$client.Dispose()};if($handler){$handler.Dispose()}
  if($p){$p.Refresh();if(-not $p.HasExited){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue};$p.Dispose()}
  Write-Host 'TEST PROCESS: STOPPED'
  Write-Host 'LIVE RELAY 9144: NOT MODIFIED'
  Write-Host 'PRODUCTION M3U / CADDY / PLUGIN MANAGER: NOT MODIFIED'
}