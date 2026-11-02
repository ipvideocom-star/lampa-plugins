#requires -Version 7.0
# One-time installation of a read-only IPTV Manager v2 Windows scheduled task.
# Back up and disable the old standalone RU discovery job ONLY after v2 registers.
# Does not change any public playlists, EPG tasks, Lampac or plugin settings.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root='C:\ReservLampac\IPTVPlus\CatalogV2'
$runner=Join-Path $root 'Invoke-IPTV-Manager-v2-Nightly-v1.ps1'
$newName='IPTV-Manager-v2-Nightly'
$legacyName='IPTV-Manager-RU-Discovery-Daily'
$taskTime=[DateTime]::Today.AddHours(4).AddMinutes(35)
$pwsh=Join-Path $PSHOME 'pwsh.exe'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$admin=[Security.Principal.WindowsPrincipal]::new($identity)
if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    throw 'Run PowerShell 7 as Administrator to install Windows scheduled task'
}
if(-not (Test-Path -LiteralPath $pwsh -PathType Leaf)){throw 'PowerShell 7 pwsh.exe not found'}
if(-not (Test-Path -LiteralPath $runner -PathType Leaf)){throw "Nightly runner not found: $runner"}
$modules=@(
  'Build-IPTV-Catalog-v2.ps1'
  'Audit-IPTV-Catalog-v2-Candidates-v2.ps1'
  'Rank-IPTV-RU-Alternatives-v1.ps1'
)
foreach($file in $modules){
    if(-not (Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf)){
        throw "Required module is missing: $file"
    }
}
$reader=Get-Content -LiteralPath $runner -Raw -Encoding UTF8
foreach($need in @(
    'IPTV MANAGER V2 NIGHTLY CYCLE: COMPLETE (READ ONLY)'
    'AutoPublish'
    'C:\ReservLampac\IPTVPlus\CatalogV2'
)){
    if(-not $reader.Contains($need)){throw "Runner verification failed: $need"}
}
$tokens=$null
$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors)
if(@($errors).Count -gt 0){throw 'Nightly runner PowerShell syntax is invalid'}
if(Get-ScheduledTask -TaskName $newName -ErrorAction SilentlyContinue){
    throw "Scheduled task $newName already exists. Refusing to overwrite."
}
$legacy=Get-ScheduledTask -TaskName $legacyName -ErrorAction SilentlyContinue
$legacyWasEnabled=($null -ne $legacy -and $legacy.State -ne 'Disabled')
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$backup=Join-Path $root ('Nightly\TaskBackups\install-'+$stamp)
New-Item -ItemType Directory -Path $backup -Force | Out-Null
if($legacy){
    Export-ScheduledTask -TaskName $legacyName |
      Out-File -LiteralPath (Join-Path $backup 'Legacy-RU-Discovery.xml') -Encoding UTF8
}
$settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$trigger=New-ScheduledTaskTrigger -Daily -At $taskTime
$principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$arg='-NoLogo -NoProfile -NonInteractive -File '+[char]34+$runner+[char]34
$action=New-ScheduledTaskAction -Execute $pwsh -Argument $arg -WorkingDirectory $root
$registered=$false
$disabledOld=$false
try{
    Register-ScheduledTask -TaskName $newName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'IPTV Manager v2: source catalog, HLS checks, candidate history, read-only shortlist; no automatic publication.' | Out-Null
    $registered=$true
    $current=Get-ScheduledTask -TaskName $newName -ErrorAction Stop
    if($current.State -eq 'Disabled'){throw 'New nightly task unexpectedly disabled'}
    Export-ScheduledTask -TaskName $newName |
      Out-File -LiteralPath (Join-Path $backup 'New-IPTV-Manager-v2.xml') -Encoding UTF8
    if($legacyWasEnabled){
        Disable-ScheduledTask -TaskName $legacyName -ErrorAction Stop | Out-Null
        $disabledOld=$true
    }
    $info=Get-ScheduledTaskInfo -TaskName $newName
    Write-Host '=== IPTV MANAGER V2 TASK INSTALLED ==='
    [pscustomobject]@{
        NewTask=$newName
        TaskState=(Get-ScheduledTask -TaskName $newName).State
        RunsAtServerLocalTime='04:35 daily'
        ServerTimeZone=(Get-TimeZone).Id
        RunAs='SYSTEM'
        MaxExecution='2 hours'
        OldDiscovery=if($disabledOld){'DISABLED; XML SAVED'}elseif($legacy){'ALREADY DISABLED'}else{'NOT FOUND'}
        OtherHealthTasks='UNCHANGED'
        EpgTasks='UNCHANGED'
        PublicPlaylists='UNCHANGED'
        AutoPublish='OFF'
        NextScheduledRun=$info.NextRunTime
        Backup=$backup
        LiveResult=Join-Path $root 'Nightly\latest-success.json'
    } | Format-List
    Write-Host 'IPTV MANAGER V2 TASK: READY FOR FIRST AUTOMATIC NIGHTLY RUN'
}catch{
    if($disabledOld){
        try{Enable-ScheduledTask -TaskName $legacyName -ErrorAction Stop | Out-Null}catch{
            Write-Warning 'Legacy task re-enable failed; check Task Scheduler manually'
        }
    }
    if($registered){
        try{Unregister-ScheduledTask -TaskName $newName -Confirm:$false -ErrorAction Stop}catch{
            Write-Warning 'New task removal failed; check Task Scheduler manually'
        }
    }
    throw
}
