#requires -Version 7.0
# IPTV Manager: promote previously tested RU expansion to the SAME two public URLs.
# Preserves all 98 original combined entries exactly; UA M3U and EPG untouched.
# Backup, two-file replacement, verification, and rollback on failure.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$DiscoveryDir
)
$ErrorActionPreference='Stop'
$public='C:\IPTV-Manager\public\playlists'
$ua=Join-Path $public 'IPTV-UA.m3u'
$ru=Join-Path $public 'IPTV-RU-Pilot-v1.m3u'
$combined=Join-Path $public 'IPTV-UA-RU-Pilot-v1.m3u'
$epg=Join-Path $public 'IPTV-UA-RU-EPG-Pilot-v1.xml'
$stageRoot='C:\ReservLampac\IPTVPlus\RU-Expansion'
$backupRoot=Join-Path $stageRoot 'Backups'
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$backupDir=Join-Path $backupRoot $runId
$lockPath=Join-Path $stageRoot 'RU-expansion-publication-v1.lock'
$urls=[ordered]@{
    RU='https://lampa.v6.army/iptv/playlists/IPTV-RU-Pilot-v1.m3u'
    Combined='https://lampa.v6.army/iptv/playlists/IPTV-UA-RU-Pilot-v1.m3u'
}
$files=@($ru,$combined)
$before=@{}
$backups=@{}
$updated=[Collections.Generic.List[string]]::new()
$lock=$null
$temps=[Collections.Generic.List[string]]::new()

function Assert-Count([string]$text,[int]$expected,[string]$label) {
    $n=[regex]::Matches($text,'(?m)^#EXTINF:').Count
    if($n -ne $expected){throw "$label channel count $n; expected $expected"}
}
function New-Sha([string]$file) {
    return (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
}
function Restore-Changed {
    foreach($dest in $updated.ToArray()){
        $source=$backups[$dest]
        if(-not (Test-Path -LiteralPath $source -PathType Leaf)){
            Write-Warning "Rollback backup absent for $dest"
            continue
        }
        $restore=Join-Path $public ('.rollback-'+[guid]::NewGuid().ToString('N')+'.tmp')
        $rejected=Join-Path $backupDir ('rejected-'+[IO.Path]::GetFileName($dest))
        Copy-Item -LiteralPath $source -Destination $restore -ErrorAction Stop
        [IO.File]::Replace($restore,$dest,$rejected)
        if((New-Sha $dest) -ne $before[$dest]) {
            throw "Rollback checksum mismatch: $dest"
        }
        Write-Host "ROLLED BACK: $dest"
    }
}
function Assert-SourceSha([object]$report,[string]$file) {
    $p=$report.beforeSha256.PSObject.Properties[$file]
    if($null -eq $p -or [string]$p.Value -ne (New-Sha $file)){
        throw "Staged source SHA256 mismatch or source changed: $file"
    }
}
function Test-Same-Entry([string]$line,[string]$url,[string]$expectedId,[string]$expectedUrl) {
    $m=[regex]::Match($line,'(?i)tvg-id="([^"]+)"')
    return $m.Success -and $m.Groups[1].Value -eq $expectedId -and $url -eq $expectedUrl
}
try {
    $stage=(Resolve-Path -LiteralPath $DiscoveryDir -ErrorAction Stop).ProviderPath
    $root=(Resolve-Path -LiteralPath $stageRoot -ErrorAction Stop).ProviderPath
    if(-not $stage.StartsWith($root+[IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $stage -Leaf) -notlike 'discovery-*'){
        throw 'Discovery directory must be an RU-Expansion/discovery-* stage'
    }
    $reportPath=Join-Path $stage 'report.json'
    $newFile=Join-Path $stage 'IPTV-RU-NEW-candidates.m3u'
    $preview=Join-Path $stage 'IPTV-UA-RU-expanded-PREVIEW.m3u'
    foreach($p in @($ua,$ru,$combined,$epg,$reportPath,$newFile,$preview)){
        if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
            throw "Required file missing: $p"
        }
    }
    $report=Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($report.status -ne 'STAGED_NOT_PUBLISHED' -or
       $report.previewFile -ne $preview -or
       $report.candidatesFile -ne $newFile -or
       [int]$report.existing -ne 98 -or
       [int]$report.newUniqueVerifiedChannels -ne 33 -or
       [int]$report.previewChannels -ne 131 -or
       [int]$report.verifiedSegments -lt 33 -or
       @($report.verified).Count -ne 33){
        throw 'Discovery report failed expected 98+33 quality gate'
    }
    $verifiedIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $verifiedUrls=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($item in @($report.verified)){
        if(-not $verifiedIds.Add([string]$item.Id) -or
           -not $verifiedUrls.Add([string]$item.Url)){
            throw 'Verified candidate IDs/URLs are duplicated'
        }
    }

    $lock=[IO.FileStream]::new($lockPath,[IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    foreach($p in @($ua,$ru,$combined)){Assert-SourceSha $report $p}
    $uaHash=New-Sha $ua
    $epgHash=New-Sha $epg
    $ruText=[IO.File]::ReadAllText($ru,[Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    $combinedText=[IO.File]::ReadAllText($combined,[Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    $newText=[IO.File]::ReadAllText($newFile,[Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    $expandedText=[IO.File]::ReadAllText($preview,[Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    Assert-Count $ruText 14 'Original RU'
    Assert-Count $combinedText 98 'Original combined'
    Assert-Count $newText 33 'New candidate'
    Assert-Count $expandedText 131 'Expanded combined'
    if(-not $newText.StartsWith('#EXTM3U') -or
       -not $expandedText.StartsWith('#EXTM3U')){throw 'Invalid M3U header'}
    $nl=[Environment]::NewLine
    $newBody=($newText -split '\r?\n' | Select-Object -Skip 1) -join $nl
    $expectedExpanded=$combinedText.TrimEnd()+$nl+$newBody.TrimEnd()+$nl
    if($expandedText.TrimEnd() -cne $expectedExpanded.TrimEnd()){
        throw 'Expanded preview differs from exact original 98 plus staged 33'
    }
    $newRuText=$ruText.TrimEnd()+$nl+$newBody.TrimEnd()+$nl
    Assert-Count $newRuText 47 'Expanded RU'

    # Validate all new EXTINF/URL pairs against the verified report.
    $actualPairs=[Collections.Generic.List[object]]::new()
    $header=''
    foreach($lineRaw in ($newText -split '\r?\n')){
        $line=$lineRaw.Trim()
        if($line.StartsWith('#EXTINF:')){$header=$line;continue}
        if(-not $header -or -not $line -or $line.StartsWith('#')){continue}
        $actualPairs.Add([pscustomobject]@{Header=$header;Url=$line})
        $header=''
    }
    if($actualPairs.Count -ne 33){throw 'New candidate pairing count mismatch'}
    foreach($item in @($report.verified)){
        $matches=@($actualPairs | Where-Object {
            Test-Same-Entry $_.Header $_.Url ([string]$item.Id) ([string]$item.Url)
        })
        if($matches.Count -ne 1){throw "Report/new M3U stream mismatch: $($item.Id)"}
    }

    $payload=[ordered]@{$ru=$newRuText;$combined=$expandedText}
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    foreach($dest in $files) {
        $before[$dest]=New-Sha $dest
        $backup=Join-Path $backupDir ([IO.Path]::GetFileName($dest))
        Copy-Item -LiteralPath $dest -Destination $backup -ErrorAction Stop
        if((New-Sha $backup) -ne $before[$dest]) {
            throw "Backup verification failed: $dest"
        }
        $backups[$dest]=$backup
    }
    $dataHash=@{}
    foreach($dest in $files) {
        $dataHash[$dest]=[Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes($payload[$dest]))
    }

    Write-Host '=== VERIFIED RU EXPANSION ==='
    Write-Host 'Original channels: UA 84, RU 14, combined 98'
    Write-Host 'New verified channels: 33'
    Write-Host 'Expected: RU 47, combined 131'
    Write-Host "Backups: $backupDir"
    Write-Host '=== REPLACE RU AND COMBINED M3U FILES ==='
    foreach($dest in $files) {
        $tmp=Join-Path $public ('.iptv-expand-'+[guid]::NewGuid().ToString('N')+'.tmp')
        $temps.Add($tmp)
        [IO.File]::WriteAllText($tmp,$payload[$dest],[Text.UTF8Encoding]::new($false))
        $oldLocalHash=New-Sha $dest
        if($oldLocalHash -ne $before[$dest]) {
            throw "Playlist changed during staging: $dest"
        }
        $expectedHash=[Convert]::ToHexString($dataHash[$dest])
        if((New-Sha $tmp) -ne $expectedHash) {throw "Staging hash mismatch: $dest"}
        $replacedBackup=Join-Path $backupDir ('replaced-'+[IO.Path]::GetFileName($dest))
        [IO.File]::Replace($tmp,$dest,$replacedBackup)
        $updated.Add($dest)
        if((New-Sha $dest) -ne $expectedHash) {throw "Local publication hash mismatch: $dest"}
    }
    if((New-Sha $ua) -ne $uaHash -or (New-Sha $epg) -ne $epgHash){
        throw 'Untouched UA or EPG changed during publication'
    }

    Write-Host '=== VERIFY TWO PUBLIC HTTPS PLAYLISTS ==='
    $i=0
    foreach($dest in $files){
        $role=if($dest -eq $ru){'RU'}else{'Combined'}
        $http=Join-Path $stage ('published-'+$role+'-'+$runId+'.m3u')
        $i++
        $checkUrl=$urls[$role]+'?verify='+$runId
        & curl.exe -fLsS --connect-timeout 10 --max-time 45 -H 'Cache-Control: no-cache' -o $http $checkUrl
        if($LASTEXITCODE -ne 0){throw "HTTPS failed for $role : $LASTEXITCODE"}
        if((New-Sha $http) -ne (New-Sha $dest)){
            throw "HTTPS SHA256 mismatch for $role"
        }
    }
    Write-Host 'IPTV RU EXPANSION: PUBLISHED AND VERIFIED'
    Write-Host "RU: 47 channels — $($urls.RU)"
    Write-Host "Combined: 131 channels — $($urls.Combined)"
    Write-Host "Original UA / combined EPG: UNCHANGED"
    Write-Host "Rollback backups: $backupDir"
}
catch {
    $reason=$_.Exception.Message
    if($updated.Count -gt 0){
        Write-Warning "Publication failed; restoring $($updated.Count) changed M3U file(s): $reason"
        Restore-Changed
    }
    throw
}
finally {
    foreach($tmp in $temps){
        if(Test-Path -LiteralPath $tmp){
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    if($lock){$lock.Dispose()}
}
