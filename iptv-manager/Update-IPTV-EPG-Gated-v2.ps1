#requires -Version 7.0
# IPTV Manager / UA EPG quality-gated update v2 (with recent-channel regression guard).
# Default dry-run generates a fresh preview but cannot modify the active EPG.
# -Publish atomically updates only the test XMLTV after quality checks.
[CmdletBinding()]
param([switch]$Publish)

$ErrorActionPreference = 'Stop'
$stage = 'C:\ReservLampac\IPTVPlus\EPG-Staging'
$previewScript = Join-Path $stage 'Update-IPTV-EPG-preview-v2.ps1'
$active = 'C:\IPTV-Manager\public\playlists\IPTV-UA-EPG-Merged-test.xml'
$backupDir = 'C:\ReservLampac\IPTVPlus\EPG-Backups'
$publicUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-Merged-test.xml'
$lockFile = Join-Path $stage 'IPTV-EPG-Gated-v2.lock'
$lock = $null
$tempPublished = $null

function Convert-GuideTime([string]$value) {
    if ($value -notmatch '^([0-9]{14}|[0-9]{12})(?:\s*([+-][0-9]{4}))?') { return $null }
    $stamp = $Matches[1]
    $zone = $Matches[2]
    if ($stamp.Length -eq 12) { $stamp += '00' }
    try {
        $date = [DateTime]::ParseExact($stamp, 'yyyyMMddHHmmss',
            [Globalization.CultureInfo]::InvariantCulture)
        $minutes = 0
        if ($zone) {
            $sign = if ($zone.StartsWith('-')) { -1 } else { 1 }
            $minutes = $sign * (
                [int]$zone.Substring(1,2) * 60 + [int]$zone.Substring(3,2))
        }
        return ([DateTimeOffset]::new(
            $date,[TimeSpan]::FromMinutes($minutes))).UtcDateTime
    } catch { return $null }
}

function Get-RecentGuideIds(
    [string]$file,[DateTime]$fromUtc,[DateTime]$untilUtc
) {
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Ignore
    $settings.XmlResolver = $null
    $xr = [Xml.XmlReader]::Create($file, $settings)
    try {
        $doc = [Xml.XmlDocument]::new()
        $doc.XmlResolver = $null
        $doc.Load($xr)
    } finally { $xr.Dispose() }
    if ($doc.DocumentElement.LocalName -ne 'tv') {
        throw "Invalid baseline XMLTV: $file"
    }
    $ids = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $doc.SelectNodes('/tv/programme')) {
        $start = Convert-GuideTime $p.GetAttribute('start')
        $stop = Convert-GuideTime $p.GetAttribute('stop')
        if ($null -eq $start -or $null -eq $stop) { continue }
        if ($stop -le $fromUtc -or $start -ge $untilUtc) { continue }
        $titleNode = $p.SelectSingleNode('title')
        $title = if ($titleNode) { $titleNode.InnerText.Trim() } else { '' }
        if (-not $title -or
            $title -match '(?i)^(no data|no epg|n/?a|unknown|tba|нет данных|немає даних|програма відсутня|программа отсутствует|no programme information|no program information)\.?\s*
    if (-not (Test-Path -LiteralPath $previewScript -PathType Leaf)) {
        throw "Preview generator missing: $previewScript"
    }
    if (-not (Test-Path -LiteralPath $active -PathType Leaf)) {
        throw "Active EPG missing: $active"
    }
    $lock = [IO.FileStream]::new(
        $lockFile,[IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)

    Write-Host '=== CURRENT EPG ==='
    $oldFileHash = (Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash
    Write-Host "SHA256: $oldFileHash"

    $before = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($dir in (Get-ChildItem -LiteralPath $stage -Directory -Filter 'preview-*')) {
        [void]$before.Add($dir.FullName)
    }

    Write-Host '=== RUN FRESH SOURCE PREVIEW ==='
    & $previewScript

    $newRuns = @(
        Get-ChildItem -LiteralPath $stage -Directory -Filter 'preview-*' |
            Where-Object { -not $before.Contains($_.FullName) }
    )
    if ($newRuns.Count -ne 1) {
        throw "Expected one new preview directory; got $($newRuns.Count)"
    }
    $runDir = $newRuns[0].FullName
    $reportPath = Join-Path $runDir 'report.json'
    $candidate = Join-Path $runDir 'IPTV-UA-EPG-preview.xml'
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw 'Preview/report missing'
    }
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ($report.status -ne 'STAGED_NOT_PUBLISHED' -or
        $report.m3uChannels -lt 50 -or
        $report.epgChannels -lt 7 -or
        $report.programmes -lt 100) {
        throw 'Preview status or content below safety thresholds'
    }
    if ($report.file -ne $candidate) {
        throw 'Preview report points to a different file'
    }
    $newHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
    if ($newHash -ne $report.sha256) {
        throw 'Preview checksum mismatch'
    }

    # Both coverage values were calculated in one run, using the same time window.
    $newMinutes = [double]$report.totalMinutesCoveredNext24
    $oldMinutes = [double]$report.baselineMinutesCoveredNext24
    $newNow = [int]$report.channelsWithProgrammeNow
    $oldNow = [int]$report.baselineChannelsWithProgrammeNow
    if ($oldMinutes -le 0 -or $oldNow -le 0 -or
        $null -eq $report.baselineRecentChannels) {
        throw 'Cannot establish a complete current baseline: refusing promotion'
    }

    # Keep every previously useful channel in the rolling [now-24h,now+24h] window.
    $nowUtc = [DateTime]::Parse(
        [string]$report.generatedUtc,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind
    ).ToUniversalTime()
    $baselineIds = Get-RecentGuideIds $active $nowUtc.AddHours(-24) $nowUtc.AddHours(24)
    if ($baselineIds.Count -ne [int]$report.baselineRecentChannels) {
        throw "Baseline recent ID mismatch: $($baselineIds.Count) vs $($report.baselineRecentChannels)"
    }
    $candidateIds = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $report.details) {
        if (-not $candidateIds.Add([string]$entry.Channel)) {
            throw "Duplicate candidate ID: $($entry.Channel)"
        }
    }
    if ($candidateIds.Count -ne [int]$report.epgChannels) {
        throw 'Candidate channel count mismatch'
    }
    $missing = @(
        foreach ($oldId in $baselineIds) {
            if (-not $candidateIds.Contains($oldId)) { $oldId }
        }
    )
    if ($missing.Count -gt 0) {
        throw "CHANNEL REGRESSION: $($missing -join ', ')"
    }
    $minMinutes = [Math]::Max(10800, $oldMinutes)
    $minNow = [Math]::Max(7, $oldNow)
    $minRecent = [Math]::Max(9, $baselineIds.Count)
    $passed = ($newMinutes -ge $minMinutes -and
               $newNow -ge $minNow -and
               $candidateIds.Count -ge $minRecent)

    Write-Host '=== QUALITY GATE ==='
    [pscustomobject]@{
        NewEPGChannels = $report.epgChannels
        NewProgrammes = $report.programmes
        CandidateRecentChannels = $candidateIds.Count
        BaselineRecentChannels = $baselineIds.Count
        HistoricalOnlyChannels = $report.historicalOnlyChannels
        NewCoverageNext24Hours = [Math]::Round($newMinutes / 60, 1)
        ExistingCoverageNext24Hours = [Math]::Round($oldMinutes / 60, 1)
        RequiredCoverageNext24Hours = [Math]::Round($minMinutes / 60, 1)
        NewChannelsPlayingNow = $newNow
        ExistingChannelsPlayingNow = $oldNow
        RequiredChannelsPlayingNow = $minNow
        RequiredRecentChannels = $minRecent
        LostRecentChannelIds = $missing.Count
        QualityGate = if ($passed) { 'PASS' } else { 'FAIL' }
        Mode = if ($Publish) { 'PUBLISH' } else { 'DRY_RUN' }
    } | Format-List

    if (-not $passed) {
        throw 'QUALITY GATE FAILED: existing EPG remains unchanged'
    }
    if (-not $Publish) {
        Write-Host 'EPG GATE: PASS (NO PUBLICATION)'
        Write-Host "Candidate: $candidate"
        return
    }

    if ((Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash -ne $oldFileHash) {
        throw 'Active EPG changed during preview: refusing overwrite'
    }

    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $nonce = [Guid]::NewGuid().ToString('N').Substring(0,8)
    $backup = Join-Path $backupDir "IPTV-UA-EPG-before-$stamp-$nonce.xml"
    $tempPublished = Join-Path (Split-Path -Parent $active) "IPTV-UA-EPG-$nonce.tmp"
    $httpFile = Join-Path $runDir 'published-http-check.xml'

    Copy-Item -LiteralPath $candidate -Destination $tempPublished -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $tempPublished -Algorithm SHA256).Hash -ne $newHash) {
        throw 'Temporary publication checksum mismatch'
    }
    [IO.File]::Replace($tempPublished, $active, $backup)
    $tempPublished = $null

    try {
        if ((Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash -ne $newHash) {
            throw 'Local publication checksum mismatch'
        }
        & curl.exe -fLsS --connect-timeout 8 --max-time 30 -H 'Origin: https://lampa.mx' -o $httpFile $publicUrl
        if ($LASTEXITCODE -ne 0) {
            throw "Public HTTPS verification failed: $LASTEXITCODE"
        }
        if ((Get-FileHash -LiteralPath $httpFile -Algorithm SHA256).Hash -ne $newHash) {
            throw 'Public HTTPS checksum mismatch'
        }
    }
    catch {
        $reason = $_.Exception.Message
        # Restore atomically; preserve backup as a recovery artifact.
        $rollbackTemp = Join-Path (Split-Path -Parent $active) "IPTV-UA-EPG-rollback-$nonce.tmp"
        Copy-Item -LiteralPath $backup -Destination $rollbackTemp -ErrorAction Stop
        [IO.File]::Replace($rollbackTemp, $active, $null)
        throw "Publication verification failed; previous EPG restored: $reason"
    }

    Write-Host 'EPG PUBLISHED AND VERIFIED: OK'
    Write-Host "Active: $active"
    Write-Host "Backup: $backup"
    Write-Host "Report: $reportPath"
}
finally {
    if ($lock) { $lock.Dispose() }
    if ($tempPublished -and (Test-Path -LiteralPath $tempPublished)) {
        Remove-Item -LiteralPath $tempPublished -Force -ErrorAction SilentlyContinue
    }
}
) {
            continue
        }
        $descNode = $p.SelectSingleNode('desc')
        if ($descNode -and $descNode.InnerText -match 'iptv-epg\.org/help') {
            continue
        }
        [void]$ids.Add($p.GetAttribute('channel'))
    }
    return ,$ids
}

try {
    if (-not (Test-Path -LiteralPath $previewScript -PathType Leaf)) {
        throw "Preview generator missing: $previewScript"
    }
    if (-not (Test-Path -LiteralPath $active -PathType Leaf)) {
        throw "Active EPG missing: $active"
    }
    $lock = [IO.FileStream]::new(
        $lockFile,[IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)

    Write-Host '=== CURRENT EPG ==='
    $oldFileHash = (Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash
    Write-Host "SHA256: $oldFileHash"

    $before = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($dir in (Get-ChildItem -LiteralPath $stage -Directory -Filter 'preview-*')) {
        [void]$before.Add($dir.FullName)
    }

    Write-Host '=== RUN FRESH SOURCE PREVIEW ==='
    & $previewScript

    $newRuns = @(
        Get-ChildItem -LiteralPath $stage -Directory -Filter 'preview-*' |
            Where-Object { -not $before.Contains($_.FullName) }
    )
    if ($newRuns.Count -ne 1) {
        throw "Expected one new preview directory; got $($newRuns.Count)"
    }
    $runDir = $newRuns[0].FullName
    $reportPath = Join-Path $runDir 'report.json'
    $candidate = Join-Path $runDir 'IPTV-UA-EPG-preview.xml'
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw 'Preview/report missing'
    }
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ($report.status -ne 'STAGED_NOT_PUBLISHED' -or
        $report.m3uChannels -lt 50 -or
        $report.epgChannels -lt 7 -or
        $report.programmes -lt 100) {
        throw 'Preview status or content below safety thresholds'
    }
    if ($report.file -ne $candidate) {
        throw 'Preview report points to a different file'
    }
    $newHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
    if ($newHash -ne $report.sha256) {
        throw 'Preview checksum mismatch'
    }

    # Both coverage values were calculated in one run, using the same time window.
    $newMinutes = [double]$report.totalMinutesCoveredNext24
    $oldMinutes = [double]$report.baselineMinutesCoveredNext24
    $newNow = [int]$report.channelsWithProgrammeNow
    $oldNow = [int]$report.baselineChannelsWithProgrammeNow
    if ($oldMinutes -le 0 -or $oldNow -le 0) {
        throw 'Cannot establish a current baseline: refusing promotion'
    }
    # Never replace useful EPG with lower aggregate coverage or fewer live-now channels.
    $minMinutes = [Math]::Max(10800, $oldMinutes)
    $minNow = [Math]::Max(7, $oldNow)
    $passed = ($newMinutes -ge $minMinutes -and $newNow -ge $minNow)

    Write-Host '=== QUALITY GATE ==='
    [pscustomobject]@{
        NewEPGChannels = $report.epgChannels
        NewProgrammes = $report.programmes
        NewCoverageNext24Hours = [Math]::Round($newMinutes / 60, 1)
        ExistingCoverageNext24Hours = [Math]::Round($oldMinutes / 60, 1)
        RequiredCoverageNext24Hours = [Math]::Round($minMinutes / 60, 1)
        NewChannelsPlayingNow = $newNow
        ExistingChannelsPlayingNow = $oldNow
        RequiredChannelsPlayingNow = $minNow
        QualityGate = if ($passed) { 'PASS' } else { 'FAIL' }
        Mode = if ($Publish) { 'PUBLISH' } else { 'DRY_RUN' }
    } | Format-List

    if (-not $passed) {
        throw 'QUALITY GATE FAILED: existing EPG remains unchanged'
    }
    if (-not $Publish) {
        Write-Host 'EPG GATE: PASS (NO PUBLICATION)'
        Write-Host "Candidate: $candidate"
        return
    }

    if ((Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash -ne $oldFileHash) {
        throw 'Active EPG changed during preview: refusing overwrite'
    }

    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $nonce = [Guid]::NewGuid().ToString('N').Substring(0,8)
    $backup = Join-Path $backupDir "IPTV-UA-EPG-before-$stamp-$nonce.xml"
    $tempPublished = Join-Path (Split-Path -Parent $active) "IPTV-UA-EPG-$nonce.tmp"
    $httpFile = Join-Path $runDir 'published-http-check.xml'

    Copy-Item -LiteralPath $candidate -Destination $tempPublished -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $tempPublished -Algorithm SHA256).Hash -ne $newHash) {
        throw 'Temporary publication checksum mismatch'
    }
    [IO.File]::Replace($tempPublished, $active, $backup)
    $tempPublished = $null

    try {
        if ((Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash -ne $newHash) {
            throw 'Local publication checksum mismatch'
        }
        & curl.exe -fLsS --connect-timeout 8 --max-time 30 -H 'Origin: https://lampa.mx' -o $httpFile $publicUrl
        if ($LASTEXITCODE -ne 0) {
            throw "Public HTTPS verification failed: $LASTEXITCODE"
        }
        if ((Get-FileHash -LiteralPath $httpFile -Algorithm SHA256).Hash -ne $newHash) {
            throw 'Public HTTPS checksum mismatch'
        }
    }
    catch {
        $reason = $_.Exception.Message
        # Restore atomically; preserve backup as a recovery artifact.
        $rollbackTemp = Join-Path (Split-Path -Parent $active) "IPTV-UA-EPG-rollback-$nonce.tmp"
        Copy-Item -LiteralPath $backup -Destination $rollbackTemp -ErrorAction Stop
        [IO.File]::Replace($rollbackTemp, $active, $null)
        throw "Publication verification failed; previous EPG restored: $reason"
    }

    Write-Host 'EPG PUBLISHED AND VERIFIED: OK'
    Write-Host "Active: $active"
    Write-Host "Backup: $backup"
    Write-Host "Report: $reportPath"
}
finally {
    if ($lock) { $lock.Dispose() }
    if ($tempPublished -and (Test-Path -LiteralPath $tempPublished)) {
        Remove-Item -LiteralPath $tempPublished -Force -ErrorAction SilentlyContinue
    }
}
