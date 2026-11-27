#Requires -Version 7.0
<#
Independent StreamGate v1 pilot; localhost only.
Uses already-staged private provider M3Us and config created by v0.1.
NO production changes; NO channel scan; NO provider URLs printed.
#>
[CmdletBinding()]
param(
  [ValidateSet('SelfTest','Start','Status','Stop')][string]$Action='SelfTest',
  [string]$Root='C:\IPTV-Manager\data\supertelevidenie\staging\SuperTV-NEW-LaunchPilot-20261128',
  [string]$StreamGateExe='C:\IPTV-Manager\Tools\StreamGate-Pilot\streamgate.exe'
)
$ErrorActionPreference='Stop'
$base='http://127.0.0.1:9187'
$state=Join-Path $Root 'Pilot-v02-PIDs-PRIVATE.json'
$config=Join-Path $Root 'Pilot-StreamGate.yaml'
$manifest=Join-Path $Root 'Manifest.json'
function Assert-Staging {
  $m=Get-Content -LiteralPath $manifest -Raw -Encoding utf8 | ConvertFrom-Json
  $expected=@{
    'Provider-Primary-PRIVATE.m3u'=1895
    'Provider-Reserve-PRIVATE.m3u'=1349
  }
  foreach($name in $expected.Keys) {
    $file=Join-Path $Root $name
    if(!(Test-Path -LiteralPath $file -PathType Leaf)){throw "MISSING: $name"}
    $key="$name SHA256"
    if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne [string]$m.$key){throw "HASH_MISMATCH: $name"}
    $n=([regex]::Matches([IO.File]::ReadAllText($file),'(?m)^#EXTINF:')).Count
    if($n -ne $expected[$name]){throw "INPUT_COUNT_MISMATCH: $name"}
  }
  if(!(Test-Path -LiteralPath $config -PathType Leaf)){throw 'YAML_NOT_FOUND_FROM_V01'}
  $yaml=Get-Content -LiteralPath $config -Raw -Encoding utf8
  foreach($token in @('127.0.0.1:9187','127.0.0.1:9191','/primary.m3u','/reserve.m3u')){
    if(!$yaml.Contains($token)){throw 'PILOT_YAML_UNEXPECTED'}
  }
  if(!(Test-Path -LiteralPath $StreamGateExe -PathType Leaf)){throw 'STREAMGATE_EXE_MISSING'}
  Write-Host 'STAGING: 1895 PRIMARY + 1349 RESERVE; HASHES VERIFIED'
}
function Get-M3UString($response) {
  $content=$response.Content
  if($content -is [byte[]]){return [Text.Encoding]::UTF8.GetString($content)}
  if($content -is [string]){return $content}
  throw 'UNSUPPORTED_RESPONSE_CONTENT_TYPE'
}
function Get-PilotHealth {
  $health=Invoke-RestMethod -Uri "$base/healthz" -TimeoutSec 4 -ErrorAction Stop
  $body=Invoke-WebRequest -Uri "$base/playlist.m3u" -TimeoutSec 4 -ErrorAction Stop
  $playlist=Get-M3UString $body
  $playlistCount=([regex]::Matches($playlist,'(?m)^#EXTINF:')).Count
  $api=Invoke-RestMethod -Uri "$base/api/v1/channels" -TimeoutSec 4 -ErrorAction Stop
  $apiCount=-1
  if($api -is [array]){$apiCount=$api.Count}
  elseif($null -ne $api.channels -and $api.channels -is [array]){$apiCount=$api.channels.Count}
  elseif($null -ne $api.count){$apiCount=[int]$api.count}
  [pscustomobject]@{
    HealthStatus=[string]$health.status
    HealthChannels=[int]$health.channels
    Providers=[int]$health.providers
    HealthyProviders=[int]$health.healthy_providers
    Sources=[int]$health.sources
    PlaylistChannels=$playlistCount
    APIChannels=$apiCount
    Version=[string]$health.version
    PlaylistText=$playlist
  }
}
function Show-Counts($h) {
  Write-Host "VERSION: $($h.Version)"
  Write-Host "HEALTH: $($h.HealthStatus) CHANNELS=$($h.HealthChannels) PROVIDERS=$($h.HealthyProviders)/$($h.Providers) SOURCES=$($h.Sources)"
  Write-Host "PLAYLIST_CHANNELS: $($h.PlaylistChannels) API_CHANNELS: $($h.APIChannels)"
}
function Assert-Free {
  foreach($port in @(9187,9191)) {
    if(@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue).Count -gt 0){
      throw "PILOT_PORT_BUSY: $port"
    }
  }
}
function Stop-Saved {
  if(!(Test-Path -LiteralPath $state -PathType Leaf)){Write-Host 'NO_TRACKED_PROCESSES';return}
  $s=Get-Content -LiteralPath $state -Raw -Encoding utf8 | ConvertFrom-Json
  foreach($item in @(
    @{Pid=[int]$s.GatePid;Match='Pilot-StreamGate.yaml'},
    @{Pid=[int]$s.ProviderPid;Match='Serve-Local-Providers.ps1'}
  )){
    if($item.Pid -le 0){continue}
    $proc=Get-CimInstance Win32_Process -Filter "ProcessId=$($item.Pid)" -ErrorAction SilentlyContinue
    if($proc) {
      if(!([string]$proc.CommandLine).Contains([string]$item.Match,[StringComparison]::OrdinalIgnoreCase)){
        throw 'PID_NOT_OWNED_BY_PILOT; NOT_STOPPED'
      }
      Stop-Process -Id $item.Pid -Force
    }
  }
  Remove-Item -LiteralPath $state -Force
  Write-Host 'PILOT_STOPPED; PRODUCTION_UNCHANGED'
}
Write-Host "=== NEW SUPERTV ISOLATED PILOT v0.2: $Action ==="
Write-Host 'PUBLIC_FILES_CHANGED: NO | CADDY_CHANGED: NO | NSSM_CHANGED: NO | MASS_SCAN: NO'
if($Action -eq 'SelfTest'){Assert-Staging;Write-Host 'RESULT: SELFTEST_PASS';return}
if($Action -eq 'Stop'){Stop-Saved;return}
if($Action -eq 'Status'){
  try{$h=Get-PilotHealth;Show-Counts $h}catch{Write-Host 'PILOT_OFFLINE_OR_INACCESSIBLE'}
  Write-Host 'RESULT: READ_ONLY';return
}
Assert-Staging
if(Test-Path -LiteralPath $state){throw 'PILOT_ALREADY_TRACKED'}
Assert-Free
$pwsh=(Get-Command pwsh.exe -ErrorAction Stop).Source
$provider=$null
$gate=$null
$ready=$false
try {
  $serve=Join-Path $Root 'Serve-Local-Providers.ps1'
  if(!(Test-Path -LiteralPath $serve -PathType Leaf)){throw 'PROVIDER_SERVER_SCRIPT_MISSING'}
  $provider=Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile','-NonInteractive','-File',('"{0}"' -f $serve),'-Root',('"{0}"' -f $Root)) -PassThru -WindowStyle Hidden
  $served=$false
  for($i=0;$i -lt 24;$i++){
    try {
      $resp=Invoke-WebRequest -Uri 'http://127.0.0.1:9191/primary.m3u' -TimeoutSec 3
      if(([regex]::Matches((Get-M3UString $resp),'(?m)^#EXTINF:')).Count -eq 1895){$served=$true;break}
    }catch{}
    if($provider.HasExited){break}
    Start-Sleep -Milliseconds 500
  }
  if(!$served){throw 'LOCAL_PROVIDER_HTTP_NOT_READY'}
  Write-Host 'LOCAL_PROVIDER: READY; 1895 EXTINF'
  $out=Join-Path $Root 'Pilot-v02-STDOUT-PRIVATE.log'
  $err=Join-Path $Root 'Pilot-v02-STDERR-PRIVATE.log'
  $gate=Start-Process -FilePath $StreamGateExe -ArgumentList @('-config',('"{0}"' -f $config)) -WorkingDirectory $Root -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
  for($i=0;$i -lt 60;$i++){
    if($gate.HasExited){break}
    try {
      $h=Get-PilotHealth
      if($h.HealthChannels -eq 1895 -and $h.Providers -eq 2 -and $h.HealthyProviders -eq 2 -and $h.PlaylistChannels -eq 1895 -and ($h.APIChannels -lt 0 -or $h.APIChannels -eq 1895)){
        $ready=$true
        break
      }
    }catch{}
    Start-Sleep -Seconds 1
  }
  if(!$ready) {
    try{$h=Get-PilotHealth;Show-Counts $h}catch{Write-Host 'PILOT_HTTP_NOT_READY'}
    Write-Host 'PRIVATE_DIAGNOSTICS: Pilot-v02-STDERR-PRIVATE.log, Pilot-v02-STDOUT-PRIVATE.log'
    throw 'PILOT_NOT_READY; NO_PRODUCTION_CHANGES'
  }
  Show-Counts $h
  [IO.File]::WriteAllText((Join-Path $Root 'Pilot-v02-Generated-PRIVATE.m3u'),$h.PlaylistText,[Text.UTF8Encoding]::new($false))
  @{GatePid=[int]$gate.Id;ProviderPid=[int]$provider.Id} | ConvertTo-Json | Set-Content -LiteralPath $state -Encoding utf8
  Write-Host 'RESULT: PILOT_READY; PRODUCTION_UNCHANGED'
} finally {
  if(!$ready) {
    if($gate -and !$gate.HasExited){Stop-Process -Id $gate.Id -Force -ErrorAction SilentlyContinue}
    if($provider -and !$provider.HasExited){Stop-Process -Id $provider.Id -Force -ErrorAction SilentlyContinue}
  }
}
