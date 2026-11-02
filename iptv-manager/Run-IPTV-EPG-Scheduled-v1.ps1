#requires -Version 7.0
# IPTV Manager / scheduled UA EPG v1.
# Runs the existing quality-gated publisher and logs every execution.
# Retention applies ONLY to purpose-specific EPG-Staging preview-*,
# EPG-Backups/IPTV-UA-EPG-before-*.xml, EPG-Logs/EPG-Run-*.log.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$stage = 'C:\ReservLampac\IPTVPlus\EPG-Staging'
$backupDir = 'C:\ReservLampac\IPTVPlus\EPG-Backups'
$logDir = 'C:\ReservLampac\IPTVPlus\EPG-Logs'
$publisher = Join-Path $stage 'Update-IPTV-EPG-Gated-v2.ps1'
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$log = Join-Path $logDir "EPG-Run-$runId.log"
$transcribing = $false
$exitCode = 1

try {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    Start-Transcript -Path $log -ErrorAction Stop | Out-Null
    $transcribing = $true
    Write-Host "=== SCHEDULED IPTV EPG | $runId ==="
    Write-Host "Time: $(Get-Date -Format o)"
    Write-Host "Identity: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Host "Log: $log"

    if (-not (Test-Path -LiteralPath $publisher -PathType Leaf)) {
        throw "Missing publisher: $publisher"
    }
    & $publisher -Publish
    if (-not $?) {
        throw 'EPG publisher returned an unsuccessful status'
    }
    Write-Host '=== EPG UPDATE: SUCCESS ==='
    $exitCode = 0

    # Cleanup after successful publication only; retain recent diagnostics and backups.
    # Failures of cleanup must not mark a verified EPG publication as failed.
    try {
        $limitPreview = (Get-Date).AddDays(-7)
        $limitOther = (Get-Date).AddDays(-30)
        $oldPreviews = @(Get-ChildItem -LiteralPath $stage -Directory -Filter 'preview-*' |
            Where-Object { $_.LastWriteTime -lt $limitPreview })
        foreach ($dir in $oldPreviews) {
            Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
        }

        if (Test-Path -LiteralPath $backupDir) {
            $backups = @(Get-ChildItem -LiteralPath $backupDir -File -Filter 'IPTV-UA-EPG-before-*.xml' |
                Sort-Object LastWriteTime -Descending)
            foreach ($item in @($backups | Select-Object -Skip 5)) {
                if ($item.LastWriteTime -lt $limitOther) {
                    Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                }
            }
        }

        # Do not delete the currently open transcript.
        $logs = @(Get-ChildItem -LiteralPath $logDir -File -Filter 'EPG-Run-*.log' |
            Where-Object { $_.FullName -ne $log -and $_.LastWriteTime -lt $limitOther })
        foreach ($item in $logs) {
            Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
        }
        Write-Host 'Retention: preview 7d / backups 30d (min 5) / logs 30d'
    }
    catch {
        Write-Host "RETENTION WARNING: $($_.Exception.Message)"
    }
}
catch {
    Write-Host "=== EPG UPDATE: FAILED ==="
    Write-Host $_.Exception.ToString()
}
finally {
    if ($transcribing) {
        try { Stop-Transcript | Out-Null }
        catch { Write-Host "TRANSCRIPT WARNING: $($_.Exception.Message)" }
    }
}
exit $exitCode
