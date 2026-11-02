#requires -Version 7.0
# Non-destructive IPTV Manager scheduled worker, run as SYSTEM.
# Health: check all RU streams + update incident state.
# Discovery: query public source lists and stage new verified candidates.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Health','Discovery')]
    [string]$Mode
)
$ErrorActionPreference='Stop'
$paths=@{
    Health='C:\ReservLampac\IPTVPlus\RU-Health\Audit-IPTV-RU-Health-v3.ps1'
    Discovery='C:\ReservLampac\IPTVPlus\RU-Expansion\Discover-IPTV-RU-Expansion-v3.ps1'
}
$logsDir='C:\ReservLampac\IPTVPlus\Monitor-Logs'
$path=$paths[$Mode]
if(-not (Test-Path -LiteralPath $path -PathType Leaf)){
    throw "Missing monitoring module: $path"
}
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')
$log=Join-Path $logsDir ($Mode+'-'+$stamp+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)+'.log')
$transcript=$false
$failed=$false
try {
    Start-Transcript -Path $log -ErrorAction Stop | Out-Null
    $transcript=$true
    Write-Host "=== IPTV MONITOR $Mode ==="
    if($Mode -eq 'Health'){
        & $path -TimeoutSeconds 16
    } else {
        & $path -MaxChecks 260
    }
    if(-not $?){throw "Monitoring $Mode command failed"}
    Write-Host "IPTV MONITOR $Mode : SUCCESS"
    Write-Host "Log: $log"

    # Limit routine staging/report growth. Preserve current health-state.json.
    # Only delete subdirectories with the known audit/discovery prefixes.
    try {
        $cut=[DateTime]::UtcNow.AddDays(-14)
        $bases=@(
            @{Path='C:\ReservLampac\IPTVPlus\RU-Health';Mask='audit-*'}
            @{Path='C:\ReservLampac\IPTVPlus\RU-Expansion';Mask='discovery-*'}
        )
        foreach($base in $bases) {
            if(-not (Test-Path -LiteralPath $base.Path -PathType Container)){continue}
            foreach($entry in (Get-ChildItem -LiteralPath $base.Path -Directory -Filter $base.Mask)) {
                if($entry.LastWriteTimeUtc -lt $cut) {
                    Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction Stop
                }
            }
        }
        $logCut=[DateTime]::UtcNow.AddDays(-30)
        foreach($entry in (Get-ChildItem -LiteralPath $logsDir -File -Filter '*.log')){
            if($entry.LastWriteTimeUtc -lt $logCut -and $entry.FullName -ne $log){
                Remove-Item -LiteralPath $entry.FullName -Force -ErrorAction Stop
            }
        }
        Write-Host 'Retention: audit/discovery staging 14 days; logs 30 days'
    }catch{
        Write-Warning "Nonfatal cleanup problem: $($_.Exception.Message)"
    }
}
catch {
    $failed=$true
    Write-Host "IPTV MONITOR $Mode : FAILED"
    Write-Host "Error: $($_.Exception.Message)"
}
finally {
    if($transcript){Stop-Transcript | Out-Null}
}
if($failed){exit 1}
exit 0
