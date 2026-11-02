#requires -Version 7.0
# IPTV Manager: one-time publication of staged UA+RU guide to independent URL.
# NEVER edits the existing UA EPG, UA/RU playlists, Plugin Manager, or scheduled tasks.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreviewDir
)

$ErrorActionPreference = 'Stop'
$stageRoot = 'C:\ReservLampac\IPTVPlus\RU-EPG-Merge'
$backupRoot = 'C:\ReservLampac\IPTVPlus\RU-EPG-Backups'
$ua = 'C:\IPTV-Manager\public\playlists\IPTV-UA-EPG-Merged-test.xml'
$public = 'C:\IPTV-Manager\public\playlists\IPTV-UA-RU-EPG-Pilot-v1.xml'
$publicUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA-RU-EPG-Pilot-v1.xml'
$lockPath = Join-Path $stageRoot 'RU-EPG-Pilot-publication-v1.lock'
$previewDirResolved = (Resolve-Path -LiteralPath $PreviewDir -ErrorAction Stop).ProviderPath
$stageResolved = (Resolve-Path -LiteralPath $stageRoot -ErrorAction Stop).ProviderPath
if(-not $previewDirResolved.StartsWith($stageResolved + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)){
    throw 'Preview must be inside dedicated RU-EPG-Merge staging root'
}
if((Split-Path $previewDirResolved -Leaf) -notlike 'preview-*'){
    throw 'Preview directory does not match expected naming'
}
$preview = Join-Path $previewDirResolved 'IPTV-UA-RU-EPG-preview.xml'
$reportFile = Join-Path $previewDirResolved 'report.json'
$lock = $null
$tmp = $null
$published = $false

try {
    if(-not (Test-Path -LiteralPath $preview -PathType Leaf) -or
       -not (Test-Path -LiteralPath $reportFile -PathType Leaf)){
        throw 'Missing preview XMLTV or JSON quality report'
    }
    if(-not (Test-Path -LiteralPath $ua -PathType Leaf)){
        throw 'Existing UA XMLTV missing'
    }
    if(Test-Path -LiteralPath $public){
        throw "Pilot EPG already exists: $public (will not overwrite)"
    }
    $lock = [IO.FileStream]::new(
        $lockPath,[IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $report = Get-Content -LiteralPath $reportFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if($report.status -ne 'STAGED_NOT_PUBLISHED' -or
       $report.preview -ne $preview -or
       [int]$report.uaChannels -lt 20 -or
       [int]$report.ruChannelsWithGuide -ne 6 -or
       [int]$report.ruLiveNow -lt 5 -or
       [int]$report.ruChannelsNext24 -lt 5 -or
       [int]$report.ruPrograms -lt 100 -or
       [int]$report.totalChannels -ne
         ([int]$report.uaChannels + [int]$report.ruChannelsWithGuide) -or
       [int]$report.totalProgrammes -ne
         ([int]$report.uaProgrammes + [int]$report.ruPrograms)){
        throw 'EPG content/quality gate FAILED'
    }
    if(@($report.details).Count -ne 6 -or
       @($report.details | Where-Object { [int]$_.Next24 -gt 0 }).Count -lt 5){
        throw 'RU programme guide details do not meet freshness checks'
    }

    $hash = (Get-FileHash -LiteralPath $preview -Algorithm SHA256).Hash
    if($hash -ne $report.previewHash){
        throw 'Preview checksum mismatch'
    }
    $uaHash = (Get-FileHash -LiteralPath $ua -Algorithm SHA256).Hash
    if($uaHash -ne $report.uaBaselineHash){
        throw 'UA baseline has changed since preview: rebuild preview before publishing'
    }

    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Ignore
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($preview,$settings)
    try{
        $doc=[Xml.XmlDocument]::new()
        $doc.XmlResolver=$null
        $doc.Load($reader)
    }finally{$reader.Dispose()}
    if($doc.DocumentElement.LocalName -ne 'tv'){
        throw 'Preview is not XMLTV'
    }
    $allChannels = @($doc.SelectNodes('/tv/channel'))
    $allProgrammes = @($doc.SelectNodes('/tv/programme'))
    if($allChannels.Count -ne [int]$report.totalChannels -or
       $allProgrammes.Count -ne [int]$report.totalProgrammes){
        throw 'Preview XML channel/programme count mismatch'
    }
    $ids = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach($ch in $allChannels){
        if(-not $ids.Add($ch.GetAttribute('id'))){
            throw "Duplicate XMLTV channel: $($ch.GetAttribute('id'))"
        }
    }
    foreach($pr in $allProgrammes){
        if(-not $ids.Contains($pr.GetAttribute('channel'))){
            throw 'XMLTV programme refers to a missing channel'
        }
    }
    $requiredRU = @(
        'Pobeda.ru@SD','STSLove.ru@SD','Telecafe.ru@SD',
        'Tochkaotryva.ru@SD','Vgostyakhuskazki.ru@SD','Vremya.ru@SD'
    )
    foreach($channelId in $requiredRU){
        if(-not $ids.Contains($channelId)){
            throw "Missing expected RU channel: $channelId"
        }
    }

    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $nonce=[guid]::NewGuid().ToString('N').Substring(0,8)
    $backup=Join-Path $backupRoot "UA-before-RU-pilot-$stamp-$nonce.xml"
    Copy-Item -LiteralPath $ua -Destination $backup -ErrorAction Stop
    if((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $uaHash){
        throw 'Backup checksum mismatch'
    }
    $tmp=Join-Path (Split-Path $public -Parent) "RU-EPG-publish-$nonce.tmp"
    $httpCheck=Join-Path $previewDirResolved "published-http-$nonce.xml"

    Write-Host '=== PUBLISH INDEPENDENT UA+RU EPG ==='
    Write-Host "UA baseline: $($report.uaChannels) channels, $($report.uaProgrammes) programmes"
    Write-Host "RU addition: $($report.ruChannelsWithGuide) channels, $($report.ruPrograms) programmes"
    Write-Host "RU live now: $($report.ruLiveNow); next24: $($report.ruChannelsNext24)"
    Write-Host "Backup: $backup"
    Copy-Item -LiteralPath $preview -Destination $tmp -ErrorAction Stop
    if((Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash -ne $hash){
        throw 'Temporary publication checksum mismatch'
    }
    if(Test-Path -LiteralPath $public){
        throw 'Publication destination was created concurrently'
    }
    [IO.File]::Move($tmp,$public)
    $tmp=$null
    $published=$true

    Write-Host '=== VERIFY HTTPS PUBLICATION ==='
    & curl.exe -fLsS --connect-timeout 8 --max-time 35 -H 'Origin: https://lampa.mx' -o $httpCheck $publicUrl
    if($LASTEXITCODE -ne 0){
        throw "HTTPS download failed: $LASTEXITCODE"
    }
    if((Get-FileHash -LiteralPath $httpCheck -Algorithm SHA256).Hash -ne $hash){
        throw 'HTTPS payload checksum mismatch'
    }
    if((Get-FileHash -LiteralPath $ua -Algorithm SHA256).Hash -ne $uaHash){
        throw 'Existing UA EPG changed during pilot publication'
    }
    Write-Host 'UA+RU EPG PILOT: PUBLISHED AND VERIFIED'
    Write-Host "URL: $publicUrl"
    Write-Host "SHA256: $hash"
    Write-Host "Existing UA EPG: UNCHANGED"
    Write-Host "Backup: $backup"
}
catch{
    if($published -and (Test-Path -LiteralPath $public)){
        Remove-Item -LiteralPath $public -Force -ErrorAction SilentlyContinue
        Write-Host 'Pilot EPG removed following validation failure; original UA EPG untouched'
    }
    throw
}
finally{
    if($tmp -and (Test-Path -LiteralPath $tmp)){
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    if($lock){$lock.Dispose()}
}
