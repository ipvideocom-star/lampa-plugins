#requires -Version 7.0
# Isolated Saturday manifest-retry experiment on 127.0.0.1:9146.
# This script never modifies Caddy, playlists, service configs, 3proxy or active Relays.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$PSNativeCommandUseErrorActionPreference=$false

$base='C:\IPTV-Manager\relay\iptv_hls_relay_v02'
$csPath=Join-Path $base 'IPTV-HLS-Relay-v02.cs'
$startPath=Join-Path $base 'Start-IPTV-HLS-Relay-v02.ps1'
$config='C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\RU-Relay-Candidates-20261105-084928.json'
$pilot='C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\IPTV-UA-RU-Relay-v02-257-STAGING-NOT-PUBLISHED.m3u'
foreach($path in @($csPath,$startPath,$config,$pilot)){
 if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing input: $path"}
}
if(-not(Get-Command curl.exe -ErrorAction SilentlyContinue)){throw 'curl.exe unavailable'}
if(@(Get-NetTCPConnection -LocalPort 9144 -State Listen -ErrorAction SilentlyContinue).Count -eq 0){throw 'Relay 9144 not listening'}
if(@(Get-NetTCPConnection -LocalPort 9146 -State Listen -ErrorAction SilentlyContinue).Count -ne 0){throw 'Port 9146 already occupied'}
$data=Get-Content $config -Raw -Encoding UTF8|ConvertFrom-Json
if($data.Mode -ne 'STAGING_ONLY' -or @($data.Candidates).Count -ne 57 -or
   @($data.Candidates|Where-Object{[int]$_.Index -eq 111}).Count -lt 1){throw 'Unexpected original Relay candidate data'}
$pos=0;$name='';$url=''
foreach($raw in [IO.File]::ReadAllLines($pilot,[Text.Encoding]::UTF8)){
 $line=$raw.Trim()
 if($line.StartsWith('#EXTINF:')){$pos++;$name=$line.Substring($line.LastIndexOf(',')+1).Trim();continue}
 if($pos -eq 235 -and $line -match '^https?://'){$url=$line;break}
}
if($name -cne 'Суббота' -or -not $url){throw 'Expected Saturday at playlist position 235'}
$u=[Uri]$url
if($u.Scheme -ne 'https' -or $u.DnsSafeHost -cne 'lampa.v6.army' -or
   $u.AbsolutePath -notmatch '^/iptv-relay/p/[0-9a-f]{64}/channel/111\.m3u8$' -or $u.Query){throw 'Unexpected Saturday protected URL'}

$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$folder=Join-Path 'C:\ReservLampac\IPTVPlus\RU-Relay-Fixes\Saturday-Manifest-Retry' "Isolated-$stamp"
New-Item -ItemType Directory -Path $folder -Force|Out-Null
function ExactlyOnce([string]$src,[string]$old,[string]$new,[string]$label){
 if([regex]::Matches($src,[regex]::Escape($old)).Count -ne 1){throw "Source differs at $label"}
 return $src.Replace($old,$new)
}
$nl=[string][char]10
$crlf=[string][char]13+$nl
$source=[IO.File]::ReadAllText($csPath).Replace($crlf,$nl)
$source=ExactlyOnce $source 'namespace IPTVRelayPilot02' 'namespace IPTVRelayPilot04' 'namespace'
$source=ExactlyOnce $source 'private readonly string prefix = "http://127.0.0.1:9144/";' 'private readonly string prefix = "http://127.0.0.1:9146/";' 'listener'
$old=@'
                Tuple<HttpResponseMessage, Uri> fetched = await Fetch(target.Url, target.Remote,
                    target.Playlist ? null : range, timeout.Token).ConfigureAwait(false);
'@.Replace($crlf,$nl)
$replacement=@'
                Tuple<HttpResponseMessage, Uri> fetched = null;
                int maximumAttempts = target.Playlist ? 3 : 1;
                for (int attempt = 0; attempt < maximumAttempts; attempt++)
                {
                    fetched = await Fetch(target.Url, target.Remote,
                        target.Playlist ? null : range, timeout.Token).ConfigureAwait(false);
                    int upstreamStatus = (int)fetched.Item1.StatusCode;
                    bool transientManifest = target.Playlist &&
                        (upstreamStatus == 404 || upstreamStatus == 429 ||
                         upstreamStatus == 502 || upstreamStatus == 503 || upstreamStatus == 504);
                    if (!transientManifest || attempt + 1 == maximumAttempts) break;
                    fetched.Item1.Dispose();
                    fetched = null;
                    Console.Error.WriteLine("[relay-retry] transient manifest HTTP " + upstreamStatus);
                    await Task.Delay(250, timeout.Token).ConfigureAwait(false);
                }
'@.Replace($crlf,$nl)
$source=ExactlyOnce $source $old $replacement 'playlist retry'
$canaryCs=Join-Path $folder 'IPTV-HLS-Relay-v02.cs'
[IO.File]::WriteAllText($canaryCs,$source,[Text.UTF8Encoding]::new($false))

$starter=[IO.File]::ReadAllText($startPath).Replace($crlf,$nl)
if(-not $starter.Contains('IPTVRelayPilot02') -or -not $starter.Contains('[string]$AccessTokenFile') -or
   -not $starter.Contains('Port 9144')){throw 'Starter source differs from expected version'}
$starter=$starter.Replace('IPTVRelayPilot02','IPTVRelayPilot04').Replace('9144','9146')
$canaryStart=Join-Path $folder 'Start-IPTV-HLS-Relay-v02.ps1'
[IO.File]::WriteAllText($canaryStart,$starter,[Text.UTF8Encoding]::new($false))

# Compile staged code before starting the isolated listener.
Add-Type -Path $canaryCs -ErrorAction Stop
Write-Host '=== SATURDAY RETRY FIX: ISOLATED CANARY ==='
Write-Host 'Source compilation: PASS'
Write-Host 'Only transient manifest responses are retried (twice, 250 ms apart).'
$token=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
$tokenFile=Join-Path $folder 'private-access-token.txt'
[IO.File]::WriteAllText($tokenFile,$token,[Text.UTF8Encoding]::new($false))
$pwsh=Join-Path $PSHOME 'pwsh.exe'
if(-not(Test-Path -LiteralPath $pwsh -PathType Leaf)){throw 'PowerShell 7 executable missing'}
$proc=$null
$rows=[Collections.Generic.List[object]]::new()
$csv=Join-Path $folder 'Saturday-Retry-Comparison.csv'
function ProbeManifest([string]$address,[bool]$local){
 $out=Join-Path $folder ([guid]::NewGuid().ToString('N')+'.tmp')
 $args=@('--silent','--noproxy','*','--max-time','12','--max-filesize','262144','--output',$out,'--write-out','METRIC|%{http_code}|%{time_total}')
 if(-not $local){$args+=@('--resolve','lampa.v6.army:443:127.0.0.1')}
 $args+=$address
 try{
  $output=@(& curl.exe @args 2>$null);$exit=$LASTEXITCODE
  $value=@($output|Where-Object{[string]$_ -like 'METRIC|*'}|Select-Object -Last 1)
  if($value.Count -eq 0){return [pscustomobject]@{Code='000';Exit=$exit;Seconds=0;Valid=$false}}
  $fields=([string]$value[0]) -split '\|'
  $code=if($fields.Count -ge 3){$fields[1]}else{'000'}
  $time=if($fields.Count -ge 3){[double]::Parse($fields[2],[Globalization.CultureInfo]::InvariantCulture)}else{0}
  $valid=$false
  if($code -eq '200' -and $exit -eq 0 -and (Test-Path -LiteralPath $out)){
   $valid=[IO.File]::ReadAllText($out).TrimStart([char]0xFEFF).StartsWith('#EXTM3U')
  }
  return [pscustomobject]@{Code=$code;Exit=$exit;Seconds=$time;Valid=$valid}
 }finally{Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue}
}
try{
 $proc=Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile','-NonInteractive','-File',$canaryStart,'-CandidatesPath',$config,'-AccessTokenFile',$tokenFile) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $folder 'stdout-private.log') -RedirectStandardError (Join-Path $folder 'stderr-private.log')
 $ready=$false
 for($i=0;$i -lt 80;$i++){
  $proc.Refresh()
  if($proc.HasExited){break}
  if(@(Get-NetTCPConnection -LocalPort 9146 -State Listen -ErrorAction SilentlyContinue).Count){$ready=$true;break}
  Start-Sleep -Milliseconds 250
 }
 if(-not $ready){throw 'Isolated Relay did not start. Review private errors in the report folder.'}
 $healthUri='http://127.0.0.1:9146/iptv-relay/p/'+$token+'/health'
 $health=Invoke-RestMethod -Uri $healthUri -TimeoutSec 12 -NoProxy
 if($health.channels -ne 28 -or $health.candidates -ne 57){throw 'Isolated health mismatch'}
 Write-Host 'Isolated 9146: HEALTH 28 / 57'
 $testUrl='http://127.0.0.1:9146/iptv-relay/p/'+$token+'/channel/111.m3u8'
 for($round=1;$round -le 16;$round++){
  foreach($test in @(@('CURRENT',$url,$false),@('RETRY',$testUrl,$true))){
   $p=ProbeManifest -address ([string]$test[1]) -local ([bool]$test[2])
   $rows.Add([pscustomobject]@{Round=$round;Variant=$test[0];HTTP=$p.Code;Exit=$p.Exit;Seconds=[Math]::Round($p.Seconds,3);ValidHLS=$p.Valid})
  }
  if($round -lt 16){Start-Sleep -Milliseconds 750}
 }
 $rows|Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
 foreach($label in @('CURRENT','RETRY')){
  $subset=@($rows|Where-Object Variant -eq $label)
  $ok=@($subset|Where-Object ValidHLS)
  $avg=if($ok.Count){[Math]::Round(($ok|Measure-Object Seconds -Average).Average,3)}else{0}
  Write-Host ("{0,-7} : HLS {1}/{2} OK; mean successful response {3}s" -f $label,$ok.Count,$subset.Count,$avg)
 }
 $log=Join-Path $folder 'stderr-private.log'
 $retryCount=if(Test-Path -LiteralPath $log){@(Select-String -LiteralPath $log -SimpleMatch '[relay-retry]' -ErrorAction SilentlyContinue).Count}else{0}
 Write-Host "Retry events observed: $retryCount"
 Write-Host "REPORT: $csv"
 Write-Host 'NO CHANGE TO SAMSUNG OR LIVE RELAY'
}finally{
 if($proc){
  $proc.Refresh()
  if(-not $proc.HasExited){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue}
  $proc.Dispose()
 }
 Remove-Item -LiteralPath $tokenFile -Force -ErrorAction SilentlyContinue
 Write-Host 'Isolated port 9146 process stopped (if started).'
 Write-Host 'CADDY / PLAYLISTS / RELAY 9144+9145 / 3PROXY: UNCHANGED'
}
