#requires -Version 5.1
# Read-only ordered 3proxy ACL audit. Redacted output: no IPs, domains, or secrets.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$path='C:\AladinProxy\aladin-proxy.cfg'
if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Expected config file not found'}
$before=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
$lines=@(Get-Content -LiteralPath $path -Encoding Default)
Write-Host '=== W2019S 3PROXY ACL STRUCTURE (REDACTED) ==='
Write-Host 'First matching ACL wins; all addresses, hostnames, credentials hidden.'
Write-Host '3proxy ACL: allow/deny <users> <source IP> <target> <port> <operation>.'
Write-Host ''
function Shape([string]$value,[string]$kind){
 if(-not $value -or $value -eq '*'){return 'ANY'}
 $elems=@($value -split ',')
 if($kind -eq 'SRC'){
  $single=@($elems | Where-Object {$_ -match '^\d{1,3}(?:\.\d{1,3}){3}$'}).Count
  $cidr=@($elems | Where-Object {$_ -match '^\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}$'}).Count
  return ('RESTRICTED items={0},IPs={1},CIDRs={2}' -f $elems.Count,$single,$cidr)
 }
 if($kind -eq 'DST'){
  $ips=@($elems | Where-Object {$_ -match '^\d{1,3}(?:\.\d{1,3}){3}(?:/\d{1,2})?$'}).Count
  $wild=@($elems | Where-Object {$_.Contains('*')}).Count
  return ('RESTRICTED items={0},IPranges={1},wildcards={2}' -f $elems.Count,$ips,$wild)
 }
 if($kind -eq 'PORT'){
  return ('RESTRICTED items={0},mentions80={1},mentions443={2}' -f
    $elems.Count,($value -match '(^|,)80(,|$)'),($value -match '(^|,)443(,|$)'))
 }
 if($kind -eq 'OP'){
  $http=($elems -contains 'HTTP' -or $elems -contains 'HTTP_GET')
  $https=($elems -contains 'HTTPS' -or $elems -contains 'HTTP_CONNECT')
  return ('RESTRICTED items={0},HTTPGET={1},CONNECT={2}' -f $elems.Count,$http,$https)
 }
 return ('RESTRICTED items={0}' -f $elems.Count)
}
$rules=[Collections.Generic.List[object]]::new()
$includes=$false
for($i=0;$i -lt $lines.Count;$i++){
 $line=([string]$lines[$i]).Trim()
 if(-not $line -or $line.StartsWith('#') -or $line.StartsWith(';')){continue}
 $tokens=@($line -split '\s+')
 $cmd=$tokens[0].ToLowerInvariant()
 if($line.Contains('$')){$includes=$true}
 if($cmd -in @('allow','deny')){
  $user=if($tokens.Count -gt 1){$tokens[1]}else{'*'}
  $src=if($tokens.Count -gt 2){$tokens[2]}else{'*'}
  $dst=if($tokens.Count -gt 3){$tokens[3]}else{'*'}
  $port=if($tokens.Count -gt 4){$tokens[4]}else{'*'}
  $ops=if($tokens.Count -gt 5){$tokens[5]}else{'*'}
  $obj=[pscustomobject]@{
   Line=$i+1;Action=$cmd.ToUpperInvariant()
   Users=(Shape $user 'USR')
   Source=(Shape $src 'SRC')
   Target=(Shape $dst 'DST')
   Ports=(Shape $port 'PORT')
   Operations=(Shape $ops 'OP')
  }
  $rules.Add($obj)
  Write-Host ('ACL LINE={0} ACTION={1}' -f $obj.Line,$obj.Action)
  Write-Host ('  USERS={0} SOURCE={1}' -f $obj.Users,$obj.Source)
  Write-Host ('  TARGET={0} PORTS={1} OPERATIONS={2}' -f $obj.Target,$obj.Ports,$obj.Operations)
 }elseif($cmd -in @('auth','proxy','socks','parent','flush','internal','external','include','log')){
  if($cmd -eq 'auth'){
   $mode=if($tokens.Count -gt 1){$tokens[1]}else{'UNSPECIFIED'}
   Write-Host ('DIRECTIVE LINE={0} AUTH={1}' -f ($i+1),$mode)
  }elseif($cmd -eq 'proxy'){
   $port=if($line -match '(?:^|\s)-p(\d+)(?:\s|$)'){$Matches[1]}else{'DEFAULT'}
   Write-Host ('DIRECTIVE LINE={0} PROXY_PORT={1}' -f ($i+1),$port)
  }else{
   Write-Host ('DIRECTIVE LINE={0} TYPE={1} arguments=REDACTED' -f ($i+1),$cmd.ToUpperInvariant())
  }
 }
}
$after=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
if($before -cne $after){throw 'Config changed during read: cannot trust this snapshot'}
$allows=@($rules|Where-Object Action -eq 'ALLOW')
$dest=@($allows|Where-Object Target -ne 'ANY')
$src=@($allows|Where-Object Source -ne 'ANY')
$ops=@($allows|Where-Object Operations -ne 'ANY')
Write-Host ''
Write-Host ('RULES: {0}; ALLOW={1}; DEST_RESTRICTED={2}; SOURCE_RESTRICTED={3}; OP_RESTRICTED={4}' -f
 $rules.Count,$allows.Count,$dest.Count,$src.Count,$ops.Count)
if($includes){Write-Host 'CAUTION: includes/macros or variable substitutions may change effective ACL'}
Write-Host 'No actual client IP matching or end-to-end proxy request is performed.'
Write-Host 'Existing Aladin configuration remains untouched.'
Write-Host '3PROXY / NETWORK / IPTV: NO CHANGES'
