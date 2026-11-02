#requires -Version 7.0
# Independent UA+RU EPG updater v1. Default DRY RUN; publish only with -Publish.
# Keeps existing UA auto updater untouched; never edits Lampa plugins, Caddy or M3U.
[CmdletBinding()]
param([switch]$Publish)

$ErrorActionPreference='Stop'
$ruSource='https://iptv-epg.org/files/epg-ru.xml.gz'
$ruRoot='C:\ReservLampac\IPTVPlus\RU-EPG'
$stage='C:\ReservLampac\IPTVPlus\RU-EPG-Merge'
$builder=Join-Path $stage 'Build-IPTV-UA-RU-EPG-Preview-v1.ps1'
$ua='C:\IPTV-Manager\public\playlists\IPTV-UA-EPG-Merged-test.xml'
$active='C:\IPTV-Manager\public\playlists\IPTV-UA-RU-EPG-Pilot-v1.xml'
$url='https://lampa.v6.army/iptv/playlists/IPTV-UA-RU-EPG-Pilot-v1.xml'
$backupDir='C:\ReservLampac\IPTVPlus\RU-EPG-Backups'
$logsDir='C:\ReservLampac\IPTVPlus\RU-EPG-Logs'
$lockPath=Join-Path $stage 'UA-RU-EPG-Updater-v1.lock'
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$runDir=Join-Path $ruRoot ('update-'+$runId)
$archive=Join-Path $runDir 'epg-ru.xml.gz'
$httpCheck=Join-Path $runDir 'published-check.xml'
$lock=$null
$temp=$null
$logRunning=$false
$exitSuccess=$false

function Get-GuideIds([Xml.XmlDocument]$doc) {
    $ids=[Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach($node in $doc.SelectNodes('/tv/channel')) {
        $id=$node.GetAttribute('id')
        if(-not $id -or -not $ids.Add($id)) {
            throw "Duplicate/empty XMLTV channel ID: $id"
        }
    }
    return ,$ids
}

try {
    foreach($f in @($ua,$active,$builder)) {
        if(-not (Test-Path -LiteralPath $f -PathType Leaf)) {
            throw "Required file missing: $f"
        }
    }
    New-Item -ItemType Directory -Path $runDir,$logsDir,$backupDir -Force | Out-Null
    $log=Join-Path $logsDir ('UA-RU-EPG-'+$runId+'.log')
    Start-Transcript -Path $log -ErrorAction Stop | Out-Null
    $logRunning=$true
    $lock=[IO.FileStream]::new(
        $lockPath,[IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)

    Write-Host "=== UA+RU EPG UPDATE $runId ==="
    Write-Host "Mode: $(if($Publish){'PUBLISH'}else{'DRY_RUN'})"
    Write-Host "Log: $log"
    $uaHash=(Get-FileHash -LiteralPath $ua -Algorithm SHA256).Hash
    $oldHash=(Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash
    $before=[Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach($dir in (Get-ChildItem -LiteralPath $stage -Directory -Filter 'preview-*')) {
        [void]$before.Add($dir.FullName)
    }

    Write-Host '=== FETCH FRESH RU XMLTV ==='
    & curl.exe -fLsS --connect-timeout 12 --max-time 150 --max-filesize 40000000 -o $archive $ruSource
    if($LASTEXITCODE -ne 0) {
        throw "RU XMLTV download failed with curl exit $LASTEXITCODE"
    }
    if((Get-Item -LiteralPath $archive).Length -lt 100000) {
        throw 'RU XMLTV archive too small'
    }
    $f=[IO.File]::OpenRead($archive)
    try {
        $head=[byte[]]::new(3)
        $n=$f.Read($head,0,3)
        if($n -ne 3 -or $head[0] -ne 31 -or $head[1] -ne 139 -or $head[2] -ne 8) {
            throw 'RU XMLTV response is not GZIP'
        }
    } finally {$f.Dispose()}
    Write-Host "RU archive: $archive"

    Write-Host '=== BUILD MERGED UA+RU PREVIEW ==='
    & $builder
    if(-not $?) {throw 'RU merge builder returned failure'}

    $newRuns=@(Get-ChildItem -LiteralPath $stage -Directory -Filter 'preview-*' |
        Where-Object {-not $before.Contains($_.FullName)})
    if($newRuns.Count -ne 1) {
        throw "Expected exactly one fresh preview, found $($newRuns.Count)"
    }
    $previewDir=$newRuns[0].FullName
    $candidate=Join-Path $previewDir 'IPTV-UA-RU-EPG-preview.xml'
    $reportFile=Join-Path $previewDir 'report.json'
    if(-not (Test-Path -LiteralPath $candidate -PathType Leaf) -or
       -not (Test-Path -LiteralPath $reportFile -PathType Leaf)) {
        throw 'Fresh preview/report is missing'
    }
    $report=Get-Content -LiteralPath $reportFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if($report.status -ne 'STAGED_NOT_PUBLISHED' -or
       $report.preview -ne $candidate -or
       $report.ruArchive -ne $archive -or
       [int]$report.ruChannelsWithGuide -ne 6 -or
       [int]$report.ruLiveNow -lt 5 -or
       [int]$report.ruChannelsNext24 -lt 5 -or
       [int]$report.ruPrograms -lt 150 -or
       [int]$report.uaChannels -lt 9 -or
       [int]$report.uaProgrammes -lt 100 -or
       [int]$report.totalChannels -ne
         ([int]$report.uaChannels+[int]$report.ruChannelsWithGuide) -or
       [int]$report.totalProgrammes -ne
         ([int]$report.uaProgrammes+[int]$report.ruPrograms)) {
        throw 'Candidate report FAIL: coverage or channel count too low'
    }
    $details=@($report.details)
    if($details.Count -ne 6 -or
       @($details | Where-Object {[int]$_.Next24 -gt 0}).Count -lt 5) {
        throw 'Candidate RU details FAIL: fewer than five channels with future EPG'
    }
    $newHash=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
    if($newHash -ne $report.previewHash) {
        throw 'Candidate SHA256 mismatch'
    }
    if((Get-FileHash -LiteralPath $ua -Algorithm SHA256).Hash -ne $uaHash -or
       $report.uaBaselineHash -ne $uaHash) {
        throw 'Published UA EPG changed while building; retry later'
    }
    $xmlSettings=[Xml.XmlReaderSettings]::new()
    $xmlSettings.DtdProcessing=[Xml.DtdProcessing]::Ignore
    $xmlSettings.XmlResolver=$null
    $candidateReader=[Xml.XmlReader]::Create($candidate,$xmlSettings)
    try {
        $doc=[Xml.XmlDocument]::new()
        $doc.XmlResolver=$null
        $doc.Load($candidateReader)
    } finally {$candidateReader.Dispose()}
    if($doc.DocumentElement.LocalName -ne 'tv') {
        throw 'Candidate is not XMLTV'
    }
    $ids=Get-GuideIds $doc
    $nChannels=@($doc.SelectNodes('/tv/channel')).Count
    $nPrograms=@($doc.SelectNodes('/tv/programme')).Count
    if($nChannels -ne [int]$report.totalChannels -or
       $nPrograms -ne [int]$report.totalProgrammes) {
        throw 'Candidate XMLTV and JSON report differ'
    }
    $ruRequired=@(
        'Pobeda.ru@SD','STSLove.ru@SD','Telecafe.ru@SD',
        'Tochkaotryva.ru@SD','Vgostyakhuskazki.ru@SD','Vremya.ru@SD'
    )
    foreach($ruId in $ruRequired) {
        if(-not $ids.Contains($ruId)) {
            throw "Missing RU guide channel: $ruId"
        }
    }

    $uaReader=[Xml.XmlReader]::Create($ua,$xmlSettings)
    try {
        $uaDoc=[Xml.XmlDocument]::new()
        $uaDoc.XmlResolver=$null
        $uaDoc.Load($uaReader)
    } finally {$uaReader.Dispose()}
    $uaIds=Get-GuideIds $uaDoc
    if($uaIds.Count -ne [int]$report.uaChannels) {
        throw 'Published UA channel count changed'
    }
    foreach($uaId in $uaIds) {
        if(-not $ids.Contains($uaId)) {
            throw "UA regression: missing $uaId"
        }
    }
    foreach($pr in $doc.SelectNodes('/tv/programme')) {
        if(-not $ids.Contains($pr.GetAttribute('channel'))) {
            throw 'Programme references an unknown channel'
        }
    }

    Write-Host '=== QUALITY GATE ==='
    [pscustomobject]@{
        UAChannels=$uaIds.Count
        RUChannels=[int]$report.ruChannelsWithGuide
        RULiveNow=[int]$report.ruLiveNow
        RUChannelsNext24=[int]$report.ruChannelsNext24
        RUProgrammes=[int]$report.ruPrograms
        CombinedChannels=$nChannels
        CombinedProgrammes=$nPrograms
        LostUAChannels=0
        Mode=if($Publish){'PUBLISH'}else{'DRY_RUN'}
        QualityGate='PASS'
    } | Format-List

    if(-not $Publish) {
        Write-Host 'UA+RU EPG QUALITY GATE: PASS (NOT PUBLISHED)'
        Write-Host "Preview: $candidate"
        $exitSuccess=$true
        return
    }

    if((Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash -ne $oldHash -or
       (Get-FileHash -LiteralPath $ua -Algorithm SHA256).Hash -ne $uaHash) {
        throw 'Publication files changed concurrently; refusing overwrite'
    }

    $nonce=[guid]::NewGuid().ToString('N').Substring(0,8)
    $backup=Join-Path $backupDir ('UA-RU-before-'+$runId+'.xml')
    $temp=Join-Path (Split-Path $active -Parent) ('UA-RU-'+$nonce+'.tmp')
    Copy-Item -LiteralPath $candidate -Destination $temp -ErrorAction Stop
    if((Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash -ne $newHash) {
        throw 'Temporary EPG checksum mismatch'
    }
    [IO.File]::Replace($temp,$active,$backup)
    $temp=$null
    try {
        if((Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash -ne $newHash) {
            throw 'Local publication checksum mismatch'
        }
        & curl.exe -fLsS --connect-timeout 8 --max-time 35 -H 'Origin: https://lampa.mx' -o $httpCheck $url
        if($LASTEXITCODE -ne 0) {
            throw "HTTPS verification failed: $LASTEXITCODE"
        }
        if((Get-FileHash -LiteralPath $httpCheck -Algorithm SHA256).Hash -ne $newHash) {
            throw 'HTTPS payload SHA256 mismatch'
        }
    } catch {
        $reason=$_.Exception.Message
        $rollback=Join-Path (Split-Path $active -Parent) ('UA-RU-rollback-'+$nonce+'.tmp')
        Copy-Item -LiteralPath $backup -Destination $rollback -ErrorAction Stop
        [IO.File]::Replace($rollback,$active,$null)
        throw "Publication check failed; old guide restored: $reason"
    }

    Write-Host 'UA+RU EPG: PUBLISHED AND VERIFIED'
    Write-Host "URL: $url"
    Write-Host "SHA256: $newHash"
    Write-Host "Backup: $backup"
    Write-Host "Log: $log"
    Write-Host 'Existing UA EPG and playlists: UNCHANGED'
    $exitSuccess=$true
}
finally {
    if($lock) {$lock.Dispose()}
    if($temp -and (Test-Path -LiteralPath $temp)) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
    if($logRunning) {
        try {Stop-Transcript | Out-Null}
        catch {Write-Host "Transcript close error: $($_.Exception.Message)"}
    }
}
