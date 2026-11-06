#requires -Version 7.0
# Repair only the delivery installer; then run Check and Apply once.
# Existing production M3U, tasks, Caddy, Relay and Aladin remain unchanged.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false

$delivery='C:\ReservLampac\IPTVPlus\CatalogV2-RU133-Delivery\installer'
$original=Join-Path $delivery 'CatalogV2-RU133-SafeInstaller-v1.ps1'
$fixed=Join-Path $delivery 'CatalogV2-RU133-SafeInstaller-v2.ps1'
$expectedOriginal='2402FEBFE39C70A31BF57A9584B3C817A0EDC5C2D57DA2A4F356B571D5D363CB'
$expectedFixed='A9BEC0F0927D16DD83854FEB9A5931B551D99C559DD9E8A85FCF8FB124870B29'
$statePath='C:\ReservLampac\IPTVPlus\CatalogV2\PatchBackups\CatalogV2-RU133-v1-state.json'
$root='C:\ReservLampac\IPTVPlus\CatalogV2'

Write-Host '=== CATALOG V2 RU133 INSTALLER REPAIR ==='
if(-not(Test-Path -LiteralPath $original -PathType Leaf)){throw 'Original delivery installer not found'}
if((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -cne $expectedOriginal){
 throw 'Original installer differs from verified archive. No changes made.'
}
if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){throw 'Missing previous rollback state'}
$previous=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
if($previous.Status -cne 'ROLLED_BACK'){throw ('Previous install is not safely rolled back: '+$previous.Status)}

$oldA=@'
 $temp=Join-Path $folder ('CatalogV2-RU133-'+[guid]::NewGuid().ToString('N')+'.tmp')
 try{
'@
$newA=@'
 $temp=Join-Path $folder ('CatalogV2-RU133-'+[guid]::NewGuid().ToString('N')+'.tmp')
 $replaceBackup=Join-Path $folder ('CatalogV2-RU133-Replaced-'+[guid]::NewGuid().ToString('N')+'.bak')
 try{
'@
$oldB='  [IO.File]::Replace($temp,$target,$null)'
$newB='  [IO.File]::Replace($temp,$target,$replaceBackup)'
$oldC=' }finally{Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}'
$newC=@'
 }finally{
  Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue
 }
'@
$source=[IO.File]::ReadAllText($original,[Text.Encoding]::UTF8)
foreach($pair in @(@($oldA,$newA),@($oldB,$newB),@($oldC,$newC))){
 if($source.Split([string[]]@($pair[0]),[StringSplitOptions]::None).Count -ne 2){
  throw 'Installer patch anchor not unique; no changes made'
 }
 $source=$source.Replace([string]$pair[0],[string]$pair[1])
}
[byte[]]$bytes=[Text.UTF8Encoding]::new($false).GetBytes($source)
$actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
if($actual -cne $expectedFixed){throw 'Fixed installer SHA256 mismatch; no changes made'}
$tok=$null;$parseErrors=$null
[void][Management.Automation.Language.Parser]::ParseInput($source,[ref]$tok,[ref]$parseErrors)
if($parseErrors -and $parseErrors.Count -gt 0){throw ('Fixed installer syntax invalid: '+$parseErrors[0].Message)}
if(Test-Path -LiteralPath $fixed -PathType Leaf){
 if((Get-FileHash -LiteralPath $fixed -Algorithm SHA256).Hash -cne $expectedFixed){
  throw 'Existing fixed installer differs from approved version; refusing overwrite'
 }
}else{
 [IO.File]::WriteAllBytes($fixed,$bytes)
}
if((Get-FileHash -LiteralPath $fixed -Algorithm SHA256).Hash -cne $expectedFixed){
 throw 'Fixed installer file verification failed'
}
Write-Host 'Original installer unchanged.'
Write-Host 'Fixed installer v2 verified; 4 embedded module payloads unchanged.'
Write-Host '=== RUNNING SAFETY CHECK ==='
& $fixed -Mode Check
Write-Host '=== APPLYING VERIFIED FOUR-MODULE UPDATE ==='
& $fixed -Mode Apply

$approved=@{
 'Build-IPTV-Catalog-v2.ps1'='9258409E5652E5E4D8A6591344FD2D854511A6D09D229071BF261D5BC9716947'
 'Audit-IPTV-Catalog-v2-Candidates-v2.ps1'='73BF6483A11A0F27F1072B8D37005B454095A4E5F83007EFB7904123DBB420F0'
 'Rank-IPTV-RU-Alternatives-v1.ps1'='DDE984A7E6555A1109789E346F9E1252B90FE63F749A05E50272E4F28FEBCA8C'
 'Invoke-IPTV-Manager-v2-Nightly-v1.ps1'='D4B8E375AF24185AD96DA68A7636D91E930109DF77F022C979DCD1A677AD1F6A'
}
foreach($name in $approved.Keys){
 $found=(Get-FileHash -LiteralPath (Join-Path $root $name) -Algorithm SHA256).Hash
 if($found -cne $approved[$name]){throw ('Post-install SHA256 mismatch: '+$name)}
}
$state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
if($state.Status -cne 'APPLIED'){throw 'Installation state is not APPLIED'}
Write-Host '=== VERIFIED: ALL FOUR MODULES INSTALLED, NO PLAYLIST PUBLISHING ==='
