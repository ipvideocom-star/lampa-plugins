#requires -Version 5.1
# Read-only local inventory of the installed 3proxy program on W2019S.
# No service, firewall, proxy, playlist or route changes. No secrets printed.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host '=== W2019S 3PROXY LOCAL LISTENER & RULE INVENTORY ==='
Write-Host 'No passwords, full command lines, proxy URLs or raw config lines are printed.'

$services = @(Get-CimInstance Win32_Service | Where-Object {
    $_.Name -match '(?i)3proxy' -or $_.DisplayName -match '(?i)3proxy' -or
    $_.PathName -match '(?i)(?:^|[\\/"\s])3proxy(?:64)?\.exe'
})
$processes = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '(?i)^3proxy(?:64)?\.exe$'
})
Write-Host ("SERVICES: {0}; RUNNING 3proxy PROCESSES: {1}" -f $services.Count,$processes.Count)
foreach($s in $services) {
    Write-Host ("SERVICE: {0} STATE={1} PID={2}" -f $s.Name,$s.State,$s.ProcessId)
}
foreach($p in $processes) {
    Write-Host ("PROCESS: PID={0} executable={1}" -f $p.ProcessId,$p.Name)
}
try {
    $tcp = @(Get-NetTCPConnection -State Listen -ErrorAction Stop)
} catch {
    throw 'Cannot read local TCP listeners; launch PowerShell with administrator permissions.'
}
$relatedPids = @($processes | ForEach-Object { [int]$_.ProcessId })
$owned = @($tcp | Where-Object { $_.OwningProcess -in $relatedPids })
foreach($l in ($owned | Sort-Object LocalPort,LocalAddress)) {
    Write-Host ("3PROXY_LISTENER: {0}:{1} PID={2}" -f $l.LocalAddress,$l.LocalPort,$l.OwningProcess)
}
if($owned.Count -eq 0) {
    Write-Host '3PROXY_LISTENERS: none attributable directly to 3proxy.exe; service wrapper may own children.'
}

# This is the port in the earlier W2022 v0.2 Relay starter, not a claim that it is still the active port.
$expectedPort = 33128
$found = @($tcp | Where-Object { $_.LocalPort -eq $expectedPort })
if($found.Count -eq 0) {
    Write-Host ("RELAY_STARTER_PORT_{0}: NOT_LISTENING" -f $expectedPort)
} else {
    foreach($l in $found){
        $owner = if($l.OwningProcess -in $relatedPids){'3PROXY'}else{'OTHER_OR_WRAPPER'}
        Write-Host ("RELAY_STARTER_PORT_{0}: LISTENING ON {1}; PID={2}; OWNER={3}" -f
            $expectedPort,$l.LocalAddress,$l.OwningProcess,$owner)
    }
}

# Locate candidate config files in known service/process directories, never search the entire drive.
$dirs = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($p in @('C:\3proxy','C:\3proxy\cfg','C:\Program Files\3proxy','C:\Program Files (x86)\3proxy')){
    if(Test-Path -LiteralPath $p -PathType Container){[void]$dirs.Add($p)}
}
foreach($p in $processes) {
    if($p.ExecutablePath){
        $parent=Split-Path -Parent ([string]$p.ExecutablePath)
        if(Test-Path -LiteralPath $parent -PathType Container){[void]$dirs.Add($parent)}
    }
}
foreach($s in $services) {
    $raw=[string]$s.PathName
    $exeMatch=[regex]::Match($raw,'(?i)(?:("[^"]+3proxy(?:64)?\.exe")|((?:[A-Z]:\\[^\r\n"]+?)3proxy(?:64)?\.exe))')
    if($exeMatch.Success){
        $path=$exeMatch.Value.Trim('"')
        $parent=Split-Path -Parent $path
        if(Test-Path -LiteralPath $parent -PathType Container){[void]$dirs.Add($parent)}
    }
}
$cfgs=[Collections.Generic.List[object]]::new()
foreach($dir in $dirs) {
    foreach($file in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Extension -in @('.cfg','.conf','.ini') -and $_.Length -lt 1048576
    })) {
        if(-not @($cfgs | Where-Object FullName -eq $file.FullName).Count){$cfgs.Add($file)}
    }
}
Write-Host ("CONFIG_FILES_IN_KNOWN_DIRECTORIES: {0}" -f $cfgs.Count)
foreach($f in $cfgs) {
    $lines=@(Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue)
    $rules=@($lines | ForEach-Object { ([string]$_).Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') -and -not $_.StartsWith(';') })
    $count=[ordered]@{}
    foreach($type in @('auth','users','allow','deny','proxy','socks','parent','internal','external','flush','service')) {
        $count[$type]=@($rules | Where-Object { $_ -match ("(?i)^"+$type+"(?:\s|$)") }).Count
    }
    $ports=@($rules | Where-Object { $_ -match '(?i)^proxy(?:\s|$)' } |
        ForEach-Object { if($_ -match '(?i)(?:^|\s)-p(\d+)(?:\s|$)'){$Matches[1]} } |
        Select-Object -Unique)
    $authTypes=@($rules | Where-Object { $_ -match '(?i)^auth\s+' } |
        ForEach-Object { (($_ -split '\s+')[1] -replace '[^A-Za-z0-9_-]','') } |
        Select-Object -Unique)
    Write-Host ("CONFIG: {0} (name only; contents redacted)" -f $f.Name)
    Write-Host ("  Auth mode(s): {0}" -f $(if($authTypes.Count){$authTypes -join ','}else{'not found'}))
    Write-Host ("  ACL counts: allow={0}, deny={1}, users={2}; parent={3}" -f $count.allow,$count.deny,$count.users,$count.parent)
    Write-Host ("  Services configured: proxy={0}, socks={1}; proxy -p ports={2}" -f
        $count.proxy,$count.socks,$(if($ports.Count){$ports -join ','}else{'none declared'}))
}

if($found.Count) {
    # A TCP-only probe avoids a potentially blocked or authenticated HTTP request.
    foreach($l in $found) {
        $hostName=if($l.LocalAddress -in @('0.0.0.0','::')){'127.0.0.1'}else{$l.LocalAddress}
        $client=[Net.Sockets.TcpClient]::new()
        try {
            $task=$client.ConnectAsync($hostName,$expectedPort)
            $connected=$task.Wait(2500) -and $client.Connected
            Write-Host ("LOCAL_TCP_PROBE_{0}: {1}" -f $expectedPort,$(if($connected){'CONNECTED'}else{'FAILED_OR_TIMEOUT'}))
        } catch {
            Write-Host ("LOCAL_TCP_PROBE_{0}: FAILED_OR_TIMEOUT" -f $expectedPort)
        } finally {$client.Dispose()}
    }
}
Write-Host ''
Write-Host 'INTERPRETATION: a missing/wrong listener indicates routing or service setup.'
Write-Host 'A listener plus W2022 HTTP 403 suggests a rule/auth/upstream response; ACL specifics need review.'
Write-Host 'Loopback TCP success does not prove W2022 external access or authorized CONNECT.'
Write-Host 'END: 3PROXY SERVICE / FIREWALL / CONFIG / IPTV: UNCHANGED'
