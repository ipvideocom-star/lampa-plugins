#requires -Version 5.1
# Activate existing IPTV UA/RU infrastructure on W2022, then schedule read-only v2 nightly.
# NO stream URLs in GitHub; NO modifications to published playlists, Caddy, Lampac, IPTV+ or EPG.
# Previous redundant private RU/UA task is disabled only after the v2 task is registered.
[CmdletBinding()]
param([switch]$InstallNightly)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$prod = 'C:\IPTV-Manager\public\playlists'
$files = [ordered]@{
    UA = 'IPTV-UA.m3u'
    RU = 'IPTV-RU-Pilot-v1.m3u'
    Combined = 'IPTV-UA-RU-Pilot-v1.m3u'
}
$expectedCounts = @{UA=84; RU=47; Combined=131}
$webBase = 'https://lampa.v6.army/iptv/playlists'
$scriptRoot = 'C:\ReservLampac\IPTVPlus\CatalogV2'
$auditRoot = 'C:\ReservLampac\IPTVPlus\GoLive'
$commit = 'efddfadd14319a35de1c84da0910bc4b6d39dd2f'
$repoBase = 'https://raw.githubusercontent.com/ipvideocom-star/lampa-plugins/' + $commit + '/iptv-manager/'
$nightTask = 'IPTV-Manager-v2-Nightly'
$redundantTask = 'IPTV-Manager-RU-UA'
$modules = [ordered]@{
    'Invoke-IPTV-Manager-v2-Nightly-v2.ps1' = 'IPTV MANAGER V2 NIGHTLY CYCLE V2: COMPLETE'
    'Build-IPTV-Catalog-v2.ps1' = 'CANONICAL CATALOG BUILT (NOT PUBLISHED)'
    'Audit-IPTV-Catalog-v2-Candidates-v2.ps1' = 'CANDIDATE AUDIT V2: COMPLETE (NO PUBLICATION)'
    'Rank-IPTV-RU-Alternatives-v1.ps1' = 'ALTERNATIVE SHORTLIST: COMPLETE'
    'Stage-IPTV-RU-Safe-Replacements-v2.ps1' = 'IPTV V2 REPLACEMENT STAGING V2: COMPLETE (NOT PUBLISHED)'
}
function Sha([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
function Write-Result([string]$name,[string]$value) { Write-Host ($name + ': ' + $value) }
function Get-ChannelCount([string]$path) {
    $text = [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
    if (-not $text.TrimStart([char]0xFEFF).StartsWith('#EXTM3U')) {throw "Invalid M3U header: $path"}
    return [regex]::Matches($text,'(?m)^#EXTINF:').Count
}
function Assert-Parse([string]$path) {
    $tokens = $null; $problems = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$problems)
    if (@($problems).Count -gt 0) { throw "PowerShell parser failed for $path : $($problems[0].Message)" }
}
function Fetch-Module([string]$name,[string]$marker) {
    $target = Join-Path $scriptRoot $name
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        Assert-Parse $target
        if (-not [IO.File]::ReadAllText($target,[Text.Encoding]::UTF8).Contains($marker)) {
            throw "Existing module differs from expected version; will not overwrite: $target"
        }
        Write-Result ('Module ' + $name) 'EXISTING'
        return
    }
    $temp = Join-Path $scriptRoot ('.module-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $url = $repoBase + $name
        & curl.exe -fLsS --connect-timeout 10 --max-time 60 --max-filesize 2000000 -o $temp $url
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temp -PathType Leaf)) {throw "Download failed: $name"}
        Assert-Parse $temp
        if (-not [IO.File]::ReadAllText($temp,[Text.Encoding]::UTF8).Contains($marker)) {throw "Unexpected module revision: $name"}
        Move-Item -LiteralPath $temp -Destination $target -ErrorAction Stop
        Write-Result ('Module ' + $name) 'INSTALLED'
    }
    finally { if (Test-Path -LiteralPath $temp -PathType Leaf) {Remove-Item -LiteralPath $temp -Force} }
}
Write-Host '=== IPTV EXISTING SYSTEM / GO-LIVE ==='
Write-Result 'Computer' $env:COMPUTERNAME
$os = (Get-CimInstance Win32_OperatingSystem).Caption
if ($os -notmatch '2022') {throw "Run on Windows Server 2022 only. Detected: $os"}
if (-not (Test-Path -LiteralPath $prod -PathType Container)) {throw "Published directory missing: $prod"}
if (-not (Test-Path -LiteralPath 'C:\Caddy\Caddyfile' -PathType Leaf)) {throw 'Caddyfile not found'}
$caddy = Get-Service -Name Caddy -ErrorAction Stop
if ($caddy.Status -ne 'Running') {throw "Caddy is not running: $($caddy.Status)"}
$caddyConfig = [IO.File]::ReadAllText('C:\Caddy\Caddyfile')
if (-not $caddyConfig.Contains('/iptv/playlists/') -or -not $caddyConfig.Contains('IPTV-Manager/public/playlists')) {
    throw 'Expected existing playlist route/root not found; refusing Caddy changes'
}
$hashes = [ordered]@{}
$counts = [ordered]@{}
foreach ($region in $files.Keys) {
    $path = Join-Path $prod $files[$region]
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {throw "Missing published playlist: $path"}
    $counts[$region] = Get-ChannelCount $path
    $hashes[$region] = Sha $path
    Write-Result ($region + ' local channels') ([string]$counts[$region])
    if ($counts[$region] -ne $expectedCounts[$region]) {throw "Unexpected production $region count; expected $($expectedCounts[$region]), no changes made"}
}
if ($counts['Combined'] -ne ($counts['UA'] + $counts['RU'])) {throw 'Combined channel count mismatch'}
New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null
$https = [ordered]@{}
foreach ($region in $files.Keys) {
    $url = $webBase + '/' + $files[$region]
    $tmp = Join-Path $auditRoot ('.https-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        & curl.exe -fLsS --connect-timeout 8 --max-time 30 --max-filesize 2000000 -H 'Cache-Control: no-cache' -H 'Accept-Encoding: identity' -o $tmp ($url + '?verify=' + [guid]::NewGuid().ToString('N'))
        $https[$region] = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tmp -PathType Leaf) -and (Sha $tmp) -eq $hashes[$region])
    }
    catch { $https[$region] = $false }
    finally { if (Test-Path -LiteralPath $tmp -PathType Leaf) { Remove-Item -LiteralPath $tmp -Force } }
    Write-Result ($region + ' HTTPS SHA256') $(if ($https[$region]) {'VERIFIED'} else {'NOT_VERIFIED'})
}
$nightStatus = 'NOT_REQUESTED'
$redundantStatus = 'UNTOUCHED'
if ($InstallNightly) {
    $pwsh = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {throw 'PowerShell 7 (pwsh.exe) is required for existing nightly v2 pipeline. Live playlists unchanged.'}
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {throw 'Run PowerShell as Administrator to install nightly task. Live playlists unchanged.'}
    New-Item -ItemType Directory -Path $scriptRoot -Force | Out-Null
    foreach ($module in $modules.Keys) {Fetch-Module $module $modules[$module]}
    $runner = Join-Path $scriptRoot 'Invoke-IPTV-Manager-v2-Nightly-v2.ps1'
    $task = Get-ScheduledTask -TaskName $nightTask -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        $nightStatus = 'EXISTING'
        $actionText = (@($task.Actions) | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' '
        if ($actionText -notmatch 'Invoke-IPTV-Manager-v2-Nightly') {
            throw "Existing $nightTask action is different. No task overwritten."
        }
        if ($task.State -eq 'Disabled') {throw "Existing $nightTask is disabled. No changes made."}
    }
    else {
        $taskTime = [DateTime]::Today.AddHours(4).AddMinutes(45)
        $taskAction = New-ScheduledTaskAction -Execute $pwsh.Source -Argument ('-NoLogo -NoProfile -NonInteractive -File "' + $runner + '"') -WorkingDirectory $scriptRoot
        $trigger = New-ScheduledTaskTrigger -Daily -At $taskTime
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $nightTask -Action $taskAction -Trigger $trigger -Settings $settings -Principal $taskPrincipal -Description 'IPTV existing catalog night audit + preview only; does not auto-publish unverified streams.' -ErrorAction Stop | Out-Null
        $nightStatus = 'INSTALLED_04:45_LOCAL'
    }
    $redundant = Get-ScheduledTask -TaskName $redundantTask -ErrorAction SilentlyContinue
    if ($null -ne $redundant -and $redundant.State -ne 'Disabled') {
        $backup = Join-Path $auditRoot ('task-' + $redundantTask + '-before-disable.xml')
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
            Export-ScheduledTask -TaskName $redundantTask | Out-File -LiteralPath $backup -Encoding UTF8 -ErrorAction Stop
        }
        Disable-ScheduledTask -TaskName $redundantTask -ErrorAction Stop | Out-Null
        $redundantStatus = 'DISABLED_WITH_XML_BACKUP'
    }
}
$statePath = Join-Path $auditRoot 'latest-go-live.json'
$state = [ordered]@{
    UpdatedUtc = [DateTime]::UtcNow.ToString('o')
    Computer = $env:COMPUTERNAME
    PlaylistFiles = $files
    ChannelCounts = $counts
    LocalSha256 = $hashes
    PublishedHTTPSVerified = $https
    NightlyTask = $nightStatus
    OldPrivateMergeTask = $redundantStatus
    ProductionPlaylistChanged = $false
    CaddyChanged = $false
    RealTVPlaybackVerified = $false
    AutomaticStreamPromotion = 'OFF_PENDING_CONTENT_RIGHTS_CHECK'
}
[IO.File]::WriteAllText($statePath,($state | ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
Write-Host '=== IPTV EXISTING SYSTEM READINESS SUMMARY ==='
Write-Result 'Playlists' 'UA=84 RU=47 Combined=131; UNCHANGED'
Write-Result 'Published HTTPS' $(if (@($https.Values | Where-Object {-not $_}).Count -eq 0) {'ALL_VERIFIED'} else {'NEEDS_CHECK'})
Write-Result 'Nightly v2' $nightStatus
Write-Result 'Redundant private task' $redundantStatus
Write-Result 'State' $statePath
Write-Result 'UA URL' ($webBase + '/' + $files['UA'])
Write-Result 'RU URL' ($webBase + '/' + $files['RU'])
Write-Result 'Combined URL' ($webBase + '/' + $files['Combined'])
Write-Host 'ProductionChanges: NONE'
Write-Host 'PlaybackVerified: FALSE (requires Samsung/Android TV check)'
Write-Host 'AutoPublishNewUnverifiedStreams: OFF'