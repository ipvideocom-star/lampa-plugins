#requires -Version 5.1
# W2019S read-only 3proxy service configuration discovery + local HTTP/CONNECT check.
# Does not print usernames/passwords, ACL IP addresses, proxy URLs or config lines.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

Write-Host '=== W2019S 3PROXY: CONFIG LOCATION + LOCAL HTTP PROTOCOL ==='
$svc=Get-CimInstance Win32_Service | Where-Object { $_.Name -ieq '3proxy' -or $_.DisplayName -ieq '3proxy' } | Select-Object -First 1
if(-not $svc){throw 'Service 3proxy not registered'}
Write-Host ('Service: {0}; state={1}; PID={2}' -f $svc.Name,$svc.State,$svc.ProcessId)
if($svc.State -ne 'Running'){throw 'Service is not running; no network probes'}
$proxyPid=[int]$svc.ProcessId
$process=Get-CimInstance Win32_Process -Filter ("ProcessId="+$proxyPid)
if(-not $process){throw 'Running process metadata unavailable'}
$command=[string]$process.CommandLine
$serviceCommand=[string]$svc.PathName
$exe=[string]$process.ExecutablePath
if(-not $exe){
 $sourceText=if($command){$command}else{$serviceCommand}
 $m=[regex]::Match($sourceText,'(?i)^\s*"(?<exe>[^"]+3proxy(?:64)?\.exe)"')
 if(-not $m.Success){$m=[regex]::Match($sourceText,'(?i)^\s*(?<exe>[A-Za-z]:\\.*?3proxy(?:64)?\.exe)')}
 if($m.Success){$exe=$m.Groups['exe'].Value}
}
$folder=if($exe){Split-Path -Parent $exe}else{''}
Write-Host ('Executable directory: {0}' -f $(if($folder){$folder}else{'NOT_IDENTIFIED'}))

$paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
function AddCandidate([string]$path){
 if(-not $path){return}
 $candidate=[Environment]::ExpandEnvironmentVariables($path.Trim('"').Trim())
 if(-not [IO.Path]::IsPathRooted($candidate) -and $folder){
  $candidate=Join-Path $folder $candidate
 }
 if([IO.Path]::IsPathRooted($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)){
  [void]$paths.Add([IO.Path]::GetFullPath($candidate))
 }
}
foreach($text in @($command,$serviceCommand)){
 $matches=[regex]::Matches($text,'(?i)(?:"(?<quoted>[^"]+\.(?:cfg|conf|ini))"|(?<!\S)(?<plain>\S+\.(?:cfg|conf|ini)))(?=\s|$)')
 foreach($match in $matches){
  $value=if($match.Groups['quoted'].Success){$match.Groups['quoted'].Value}else{$match.Groups['plain'].Value}
  AddCandidate $value
 }
}
$dirs=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($d in @($folder,'C:\3proxy','C:\3proxy\cfg','C:\3proxy\config',
                  'C:\Program Files\3proxy','C:\Program Files (x86)\3proxy')){
 if($d -and (Test-Path -LiteralPath $d -PathType Container)){[void]$dirs.Add($d)}
}
# Include only immediate subfolders of these known small roots; do NOT crawl C:\.
foreach($root in @($folder,'C:\3proxy','C:\Program Files\3proxy')){
 if($root -and (Test-Path -LiteralPath $root -PathType Container)){
  foreach($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)){
   if($d.Name -match '(?i)^(?:cfg|config|conf|bin|etc)$'){[void]$dirs.Add($d.FullName)}
  }
 }
}
foreach($d in $dirs){
 foreach($pattern in @('3proxy.cfg','3proxy.conf','*.cfg','*.conf','*.ini')){
  foreach($file in @(Get-ChildItem -LiteralPath $d -Filter $pattern -File -ErrorAction SilentlyContinue)){
   if($file.Length -le 2097152){[void]$paths.Add($file.FullName)}
  }
 }
}
Write-Host ('Candidate config files found: {0}' -f $paths.Count)
foreach($path in (@($paths)|Sort-Object)){
 $file=Get-Item -LiteralPath $path
 $lines=@(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)
 $commands=@($lines | ForEach-Object{([string]$_).Trim()} |
   Where-Object{$_ -and -not $_.StartsWith('#') -and -not $_.StartsWith(';')})
 $counts=@{}
 foreach($key in @('auth','users','allow','deny','proxy','socks','parent','flush','internal','external','log')){
  $counts[$key]=@($commands|Where-Object{$_ -match ('(?i)^'+$key+'(?:\s|$)')}).Count
 }
 $mode=@($commands|Where-Object{$_ -match '(?i)^auth\s+'} |
   ForEach-Object{($_ -split '\s+')[1]}|Select-Object -Unique)
 $ports=@($commands|Where-Object{$_ -match '(?i)^proxy(?:\s|$)'} |
   ForEach-Object{if($_ -match '(?i)(?:^|\s)-p(\d+)(?:\s|$)'){$Matches[1]}} |
   Select-Object -Unique)
 Write-Host ('CONFIG_PATH: {0}' -f $path)
 Write-Host ('CONFIG_SIZE: {0} bytes; LAST_WRITE: {1}' -f $file.Length,$file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
 Write-Host ('AUTH: {0}; USERS_LINES={1}; ALLOW={2}; DENY={3}; PARENT={4}' -f
   $(if($mode.Count){$mode -join ','}else{'NOT_LISTED'}),$counts.users,$counts.allow,$counts.deny,$counts.parent)
 Write-Host ('PROXY_RULES={0}; SOCKS_RULES={1}; PROXY_PORTS={2}; FLUSH={3}; LOG_LINES={4}' -f
   $counts.proxy,$counts.socks,$(if($ports.Count){$ports -join ','}else{'NOT_EXPLICIT'}),$counts.flush,$counts.log)
}
if($paths.Count -eq 0){
 Write-Host 'Config still not located. The service may use a non-standard path or extension.'
}
# Confirm the listener and compare HTTP vs HTTPS CONNECT WITHOUT passing credentials.
$listeners=@(Get-NetTCPConnection -State Listen -LocalPort 33128 -ErrorAction SilentlyContinue |
   Where-Object { $_.OwningProcess -eq $proxyPid })
if($listeners.Count -eq 0){throw 'Expected 3proxy listener on port 33128 is now missing'}
foreach($l in $listeners){
 Write-Host ('LISTENER: {0}:{1}; process 3proxy' -f $l.LocalAddress,$l.LocalPort)
}
$ip='192.168.88.34'
if(@($listeners|Where-Object { $_.LocalAddress -eq $ip -or $_.LocalAddress -eq '0.0.0.0' }).Count -eq 0){
 Write-Host 'Local tests skipped: 3proxy does not bind expected 192.168.88.34 address'
}else{
 if(-not(Get-Command curl.exe -ErrorAction SilentlyContinue)){
  Write-Host 'curl.exe unavailable; HTTP/CONNECT checks skipped'
 }else{
  foreach($t in @(@('HTTP','http://example.com/'),@('HTTPS_CONNECT','https://example.com/'))){
   $args=@('--silent','--noproxy','localhost','--proxy',('http://'+$ip+':33128'),
      '--connect-timeout','3','--max-time','9','--output','NUL',
      '--write-out','STAT|%{http_code}|%{http_connect}|%{time_total}',[string]$t[1])
   $result=@(& curl.exe @args 2>$null);$exit=$LASTEXITCODE
   $stat=@($result|Where-Object{[string]$_ -like 'STAT|*'}|Select-Object -Last 1)
   $parts=if($stat.Count){([string]$stat[0])-split '\|'}else{@()}
   $http=if($parts.Count -ge 4){$parts[1]}else{'000'}
   $connect=if($parts.Count -ge 4){$parts[2]}else{'000'}
   Write-Host ('LOCAL_{0}: HTTP={1}; CONNECT={2}; CURL_EXIT={3}' -f $t[0],$http,$connect,$exit)
  }
 }
}
Write-Host 'CONCLUSION: local requests may be denied by ACL that intentionally permits other client IPs.'
Write-Host 'For a definitive W2022 diagnosis, compare its actual proxy endpoint and network path separately.'
Write-Host '3PROXY / FIREWALL / ROUTER / CADDY / IPTV: NO CHANGES'
