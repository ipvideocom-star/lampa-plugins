#requires -Version 7.0
# Publish vetted 131-channel UA/RU grouping under existing M3U URLs.
# No channel deletions, stream URL changes, tvg-id changes or HTTP option changes.
# All 3 M3Us backed up before replacing; rollback on any error, HTTPS SHA check.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PreviewDir
)
$ErrorActionPreference='Stop'
$public='C:\IPTV-Manager\public\playlists'
$stageRoot='C:\ReservLampac\IPTVPlus\Playlist-Cleanup'
$backupRoot=Join-Path $stageRoot 'Published-Backups'
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$backupDir=Join-Path $backupRoot $runId
$lockPath=Join-Path $stageRoot 'group-publish.lock'
$published=@(
    [pscustomobject]@{Name='UA';Path=(Join-Path $public 'IPTV-UA.m3u');PreviewName='UA-7-GROUPS-PREVIEW.m3u';Count=84;Url='https://lampa.v6.army/iptv/playlists/IPTV-UA.m3u'}
    [pscustomobject]@{Name='RU';Path=(Join-Path $public 'IPTV-RU-Pilot-v1.m3u');PreviewName='RU-GROUPED-PREVIEW.m3u';Count=47;Url='https://lampa.v6.army/iptv/playlists/IPTV-RU-Pilot-v1.m3u'}
    [pscustomobject]@{Name='Combined';Path=(Join-Path $public 'IPTV-UA-RU-Pilot-v1.m3u');PreviewName='UA-RU-GROUPED-PREVIEW.m3u';Count=131;Url='https://lampa.v6.army/iptv/playlists/IPTV-UA-RU-Pilot-v1.m3u'}
)
$expectedGroups=[ordered]@{
    'Украина / Основные'=30
    'Украина / Новости'=13
    'Украина / Кино и развлечения'=12
    'Украина / Музыка'=11
    'Украина / Спорт и активный отдых'=9
    'Украина / Познавательные'=6
    'Украина / Детям'=3
}
$origHash=@{}
$backups=@{}
$previewHash=@{}
$changed=[Collections.Generic.List[string]]::new()
$temps=[Collections.Generic.List[string]]::new()
$lock=$null
$rollbackFailed=$false

function Sha([string]$path){
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function Parse-M3u([string]$path) {
    $lines=[IO.File]::ReadAllLines($path,[Text.Encoding]::UTF8)
    if($lines.Count -lt 3 -or
       $lines[0].TrimStart([char]0xFEFF) -cne '#EXTM3U'){
        throw "Unsupported M3U header: $path"
    }
    $entries=[Collections.Generic.List[object]]::new()
    $header=''
    $meta=[Collections.Generic.List[string]]::new()
    for($i=1;$i -lt $lines.Count;$i++){
        $line=$lines[$i].Trim()
        if(-not $line){continue}
        if($line.StartsWith('#EXTINF:')){
            if($header){throw "Double EXTINF in $path"}
            $header=$line
            $meta.Clear()
            continue
        }
        if($line.StartsWith('#')){
            if(-not $header){throw "Unpaired directive in $path"}
            $meta.Add($line)
            continue
        }
        if(-not $header){throw "Unpaired URL in $path"}
        $uri=$null
        if(-not [Uri]::TryCreate($line,[UriKind]::Absolute,[ref]$uri) -or
           $uri.Scheme -notin @('http','https')){
            throw "Invalid stream URL in $path"
        }
        $group=[regex]::Match($header,'(?i)group-title="([^"]*)"')
        if(-not $group.Success){throw "Missing group-title in $path"}
        $entries.Add([pscustomobject]@{
            Header=$header
            Group=$group.Groups[1].Value
            Meta=@($meta.ToArray())
            Url=$line
        })
        $header=''
        $meta.Clear()
    }
    if($header){throw "Missing final URL in $path"}
    return ,$entries
}
function NormalizedHeader([string]$value){
    return [regex]::Replace($value,'(?i)\s+group-title="[^"]*"','')
}
function Compare-Entry([object]$before,[object]$after,[string]$label,[int]$i){
    if((NormalizedHeader $before.Header) -cne (NormalizedHeader $after.Header)){
        throw "Header attributes other than group changed: $label entry $i"
    }
    if($before.Url -cne $after.Url){
        throw "Stream URL changed: $label entry $i"
    }
    if(@($before.Meta).Count -ne @($after.Meta).Count){
        throw "HTTP/directive count changed: $label entry $i"
    }
    for($j=0;$j -lt @($before.Meta).Count;$j++){
        $x=[string]$before.Meta[$j]
        $y=[string]$after.Meta[$j]
        if($x -match '(?i)^#EXTGRP:'){
            if($y -cne ('#EXTGRP:'+$after.Group)){
                throw "EXTGRP is not consistent with new group: $label $i"
            }
        }elseif($x -cne $y){
            throw "HTTP option or metadata modified: $label entry $i directive $j"
        }
    }
}
function Rollback-Changed {
    foreach($file in $changed.ToArray()){
        if(-not $backups.ContainsKey($file)){throw "Rollback backup missing in index: $file"}
        $restore=Join-Path $public ('.iptv-restore-'+[guid]::NewGuid().ToString('N')+'.tmp')
        $rejected=Join-Path $backupDir ('rejected-'+[IO.Path]::GetFileName($file))
        Copy-Item -LiteralPath $backups[$file] -Destination $restore -ErrorAction Stop
        [IO.File]::Replace($restore,$file,$rejected)
        if((Sha $file) -ne $origHash[$file]){
            throw "Rollback checksum mismatch: $file"
        }
        Write-Host "ROLLED BACK: $file"
    }
}
try {
    $stage=(Resolve-Path -LiteralPath $PreviewDir -ErrorAction Stop).ProviderPath
    $root=(Resolve-Path -LiteralPath $stageRoot -ErrorAction Stop).ProviderPath
    if(-not $stage.StartsWith(
        $root+[IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $stage -Leaf) -notlike 'preview-*'){
        throw "Preview folder must be under $stageRoot"
    }
    $reportFile=Join-Path $stage 'report.json'
    if(-not (Test-Path -LiteralPath $reportFile -PathType Leaf)){throw 'Staged report missing'}
    $report=Get-Content -LiteralPath $reportFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    if($report.Status -ne 'PREVIEW_NOT_PUBLISHED_ALL_131_PRESERVED' -or
       [int]$report.Existing.UA -ne 84 -or
       [int]$report.Existing.RU -ne 47 -or
       [int]$report.Existing.Combined -ne 131 -or
       [int]$report.Preview.UA -ne 84 -or
       [int]$report.Preview.RU -ne 47 -or
       [int]$report.Preview.Combined -ne 131 -or
       [int]$report.RuNeedsReview -ne 26){
        throw 'Staged report does not match validated 131-channel grouping'
    }
    foreach($item in $published){
        $item | Add-Member -NotePropertyName PreviewPath -NotePropertyValue (Join-Path $stage $item.PreviewName)
        if(-not (Test-Path -LiteralPath $item.Path -PathType Leaf) -or
           -not (Test-Path -LiteralPath $item.PreviewPath -PathType Leaf)){
            throw "Missing current or staged file for $($item.Name)"
        }
        $expectedPath=[string]$report.Files[$item.Name]
        if($expectedPath -ne $item.PreviewPath){
            throw "Report path does not match staged $($item.Name)"
        }
        $origHash[$item.Path]=Sha $item.Path
        $p=[string]$report.SourceSha256[$item.Path]
        if($origHash[$item.Path] -ne $p){
            throw "Published file changed after staging: $($item.Path)"
        }
        $previewHash[$item.Path]=Sha $item.PreviewPath
    }

    $old=@{}
    $new=@{}
    foreach($item in $published){
        $old[$item.Name]=(Parse-M3u $item.Path).ToArray()
        $new[$item.Name]=(Parse-M3u $item.PreviewPath).ToArray()
        if($old[$item.Name].Count -ne $item.Count -or
           $new[$item.Name].Count -ne $item.Count){
            throw "Unexpected channel count: $($item.Name)"
        }
        for($i=0;$i -lt $item.Count;$i++){
            Compare-Entry $old[$item.Name][$i] $new[$item.Name][$i] $item.Name $i
        }
    }

    $groupCounter=@{}
    foreach($entry in $new['UA']){
        if(-not $expectedGroups.Contains($entry.Group)){
            throw "Unexpected new UA group: $($entry.Group)"
        }
        if(-not $groupCounter.ContainsKey($entry.Group)){$groupCounter[$entry.Group]=0}
        $groupCounter[$entry.Group]++
    }
    if($groupCounter.Count -ne 7){throw 'Expected seven UA groups'}
    foreach($key in $expectedGroups.Keys){
        if($groupCounter[$key] -ne $expectedGroups[$key]){
            throw "Unexpected count in group $key"
        }
    }
    foreach($entry in $new['RU']){
        if($entry.Group -notin @(
            'Россия / Кино и сериалы','Россия / Музыка','Россия / Остальные')){
            throw "Unexpected RU group: $($entry.Group)"
        }
    }
    for($i=0;$i -lt 131;$i++){
        $expected=if($i -lt 84){$new['UA'][$i]}else{$new['RU'][$i-84]}
        $actual=$new['Combined'][$i]
        if($actual.Header -cne $expected.Header -or $actual.Url -cne $expected.Url -or
           (@($actual.Meta) -join [char]10) -cne (@($expected.Meta) -join [char]10)){
            throw "Combined preview not equal to UA+RU preview at index $i"
        }
    }
    $originalOptions=@($old['UA'] | ForEach-Object { $_.Meta } |
        Where-Object {$_ -match '^#EXTVLCOPT:'}).Count
    $newOptions=@($new['UA'] | ForEach-Object { $_.Meta } |
        Where-Object {$_ -match '^#EXTVLCOPT:'}).Count
    if($originalOptions -ne 35 -or $newOptions -ne 35){
        throw "HTTP metadata count changed: $originalOptions -> $newOptions"
    }

    $lock=[IO.FileStream]::new($lockPath,[IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Write-Host '=== VALIDATED PREVIEW ==='
    Write-Host 'UA 84 channels / 7 groups; RU 47 channels; combined 131'
    Write-Host 'All channel headers, URL, tvg-id, and 35 EXTVLCOPT options preserved'
    foreach($item in $published){
        $backup=Join-Path $backupDir ([IO.Path]::GetFileName($item.Path))
        Copy-Item -LiteralPath $item.Path -Destination $backup -ErrorAction Stop
        if((Sha $backup) -ne $origHash[$item.Path]){
            throw "Backup hash failed for $($item.Name)"
        }
        $backups[$item.Path]=$backup
    }
    Write-Host "Backups verified: $backupDir"
    Write-Host '=== PUBLISH THREE GROUPED M3U FILES ==='
    foreach($item in $published){
        if((Sha $item.Path) -ne $origHash[$item.Path]){
            throw "Live M3U modified concurrently: $($item.Path)"
        }
        $temp=Join-Path $public ('.iptv-group-'+[guid]::NewGuid().ToString('N')+'.tmp')
        $temps.Add($temp)
        Copy-Item -LiteralPath $item.PreviewPath -Destination $temp -ErrorAction Stop
        if((Sha $temp) -ne $previewHash[$item.Path]){
            throw "Staged copy checksum failed: $($item.Name)"
        }
        $oldBackup=Join-Path $backupDir ('replaced-'+[IO.Path]::GetFileName($item.Path))
        [IO.File]::Replace($temp,$item.Path,$oldBackup)
        $changed.Add($item.Path)
        if((Sha $item.Path) -ne $previewHash[$item.Path]){
            throw "Local post-replacement checksum mismatch: $($item.Name)"
        }
    }
    Write-Host '=== VERIFY PUBLIC HTTPS RESPONSES ==='
    foreach($item in $published){
        $download=Join-Path $stage ('https-check-'+$item.Name+'-'+$runId+'.m3u')
        $url=$item.Url+'?verify='+$runId
        & curl.exe -fLsS --connect-timeout 10 --max-time 45 -H 'Cache-Control: no-cache' -o $download $url
        if($LASTEXITCODE -ne 0){throw "HTTPS fetch failed for $($item.Name): $LASTEXITCODE"}
        if((Sha $download) -ne $previewHash[$item.Path]){
            throw "Public HTTPS data mismatch for $($item.Name)"
        }
    }
    Write-Host 'IPTV GROUPED PLAYLISTS: PUBLISHED AND VERIFIED'
    Write-Host "UA: $($published[0].Url)"
    Write-Host "RU: $($published[1].Url)"
    Write-Host "Combined: $($published[2].Url)"
    Write-Host 'All 131 channels, IDs and per-stream HTTP metadata preserved'
    Write-Host "Rollback backups: $backupDir"
    Write-Host 'EPG files, scheduled tasks and plugin settings: NOT MODIFIED'
}
catch {
    $problem=$_.Exception.Message
    if($changed.Count -gt 0) {
        Write-Warning "Publication check failed, restoring original M3U: $problem"
        try {
            Rollback-Changed
        }catch {
            $rollbackFailed=$true
            Write-Warning "ROLLBACK ERROR: $($_.Exception.Message); backups remain in $backupDir"
        }
    }
    if($rollbackFailed){
        throw "Failed publication and automatic rollback: $problem. Backups: $backupDir"
    }
    throw $problem
}
finally {
    foreach($temp in $temps){
        if(Test-Path -LiteralPath $temp){
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        }
    }
    if($lock){$lock.Dispose()}
}
