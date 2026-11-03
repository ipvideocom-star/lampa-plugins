#requires -Version 5.1
# Offline explanation of two P1 URI-policy rejects on W2019S.
# Reads only approved P1 CSV. Does not perform DNS, HTTP, or filesystem writes.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -cne 'W2019S'){throw 'Run on W2019S'}
$file='C:\IPTV-Agent\state\P1-REMOTE-RECHECK-10.csv'
$sha='9427A0995BD033F8FEE325B58DF3C902C7BC6716D5E079A298E36B6E7B019B98'
if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -cne $sha){throw 'P1 CSV SHA256 mismatch'}
$rows=@(Import-Csv -LiteralPath $file -Encoding UTF8)
if($rows.Count -ne 10){throw 'Unexpected P1 CSV row count'}
$targets=@('CA89360B01F3C0F5','46D4A65B7B5274A3')
$found=0
Write-Host '=== WHY TWO P1 URLS WERE REJECTED (OFFLINE) ==='
foreach($r in $rows){
  if([string]$r.URLKey -cnotin $targets){continue}
  $found++
  $uri=$null
  $errors=New-Object 'System.Collections.Generic.List[string]'
  if(-not [Uri]::TryCreate([string]$r.URL,[UriKind]::Absolute,[ref]$uri)){
    $errors.Add('NOT_ABSOLUTE_URI')
    $scheme='';$host='';$port='';$pathExt=''
  }else{
    $scheme=$uri.Scheme
    $host=$uri.DnsSafeHost
    $port=$uri.Port
    $pathExt=[IO.Path]::GetExtension($uri.AbsolutePath)
    if($uri.Scheme -notin @('http','https')){$errors.Add('SCHEME_NOT_HTTP_OR_HTTPS')}
    if($uri.UserInfo){$errors.Add('EMBEDDED_USER_INFO')}
    if($uri.Host -match '(?i)(^localhost$|\.(local|lan|internal|home|test|invalid|onion)$)'){$errors.Add('HOSTNAME_RESTRICTED')}
    if($uri.Host -notmatch '^[a-zA-Z0-9.-]+$'){$errors.Add('NON_ASCII_OR_SPECIAL_HOSTNAME')}
    if($uri.Port -notin @(80,443,8080)){$errors.Add('PORT_NOT_80_443_8080')}
  }
  if($errors.Count -eq 0){$errors.Add('NO_URI_POLICY_VIOLATION_FOUND_CHECK_NESTED_HLS')}
  [pscustomobject]@{
    Channel=[string]$r.Channel
    UrlKey=[string]$r.URLKey
    Scheme=$scheme
    Host=$host
    Port=$port
    PathExtension=$pathExt
    Result=($errors -join '; ')
  } | Format-List
}
if($found -ne 2){throw "Expected 2 target rows, found $found"}
Write-Host 'OFFLINE URI DIAGNOSTIC COMPLETE; NO NETWORK OR WRITES'
