#requires -Version 7.0
# Installer: UA+RU EPG separate 6-hour task offset 20 min after UA.
# Leaves original UA task, UA EPG, playlists, Caddy and Plugin Manager unchanged.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root='C:\ReservLampac\IPTVPlus\RU-EPG-Merge'
$updater=Join-Path $root 'Update-IPTV-UA-RU-EPG-Gated-v2.ps1'
$source='https://raw.githubusercontent.com/ipvideocom-star/lampa-plugins/114e2e6e5879146c80a6799e2841ac6450c112d5/iptv-manager/Update-IPTV-UA-RU-EPG-Gated-v2.ps1'
$uaTaskName='IPTV-Manager-EPG-UA-6h'
$ruTaskName='IPTV-Manager-EPG-UA-RU-6h'
$active='C:\IPTV-Manager\public\playlists\IPTV-UA-RU-EPG-Pilot-v1.xml'
$ua='C:\IPTV-Manager\public\playlists\IPTV-UA-EPG-Merged-test.xml'
$builder=Join-Path $root 'Build-IPTV-UA-RU-EPG-Preview-v1.ps1'
$newTaskCreated=$false
$temporary=$null

if($PSVersionTable.PSVersion.Major -lt 7){throw 'PowerShell 7 required'}
$pwsh=(Get-Command pwsh.exe -CommandType Application -ErrorAction Stop).Source
if(-not (Test-Path -LiteralPath $pwsh -PathType Leaf)){throw "pwsh missing: $pwsh"}
foreach($f in @($active,$ua,$builder)) {
    if(-not (Test-Path -LiteralPath $f -PathType Leaf)){throw "Required file missing: $f"}
}
$uaTask=Get-ScheduledTask -TaskName $uaTaskName -ErrorAction SilentlyContinue
if(-not $uaTask){throw "Existing UA scheduled task not found: $uaTaskName"}
if($uaTask.State -eq 'Disabled'){throw 'Existing UA scheduled task is disabled'}
if(Get-ScheduledTask -TaskName $ruTaskName -ErrorAction SilentlyContinue){
    throw "UA+RU scheduled task already exists: $ruTaskName (not overwriting)"
}
New-Item -ItemType Directory -Path $root -Force | Out-Null
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')
$nonce=[guid]::NewGuid().ToString('N').Substring(0,8)
$uaReference=Join-Path $root ('UA-task-before-RU-scheduler-'+$stamp+'-'+$nonce+'.xml')
Export-ScheduledTask -TaskName $uaTaskName | Set-Content -LiteralPath $uaReference -Encoding utf8 -ErrorAction Stop
Write-Host '=== ORIGINAL UA TASK: UNCHANGED ==='
Write-Host "Reference export: $uaReference"

try {
    if(Test-Path -LiteralPath $updater -PathType Leaf){
        $current=[IO.File]::ReadAllText($updater,[Text.Encoding]::UTF8)
        if(-not $current.Contains('Independent UA+RU EPG updater v2.') -or
           -not $current.Contains('Replace($rollback,$active,$badVersion)')){
            throw "Existing updater differs from expected v2: $updater"
        }
        Write-Host 'UPDATER V2: ALREADY PRESENT'
    } else {
        $temporary=Join-Path $root ('v2-download-'+$nonce+'.tmp')
        & curl.exe -fLsS --connect-timeout 10 --max-time 45 -o $temporary $source
        if($LASTEXITCODE -ne 0){throw "Updater download failed: $LASTEXITCODE"}
        $tokens=$null
        $errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($temporary,[ref]$tokens,[ref]$errors)
        if(@($errors).Count -gt 0){
            $errors | Format-List
            throw 'Updater PowerShell syntax failed'
        }
        $txt=[IO.File]::ReadAllText($temporary,[Text.Encoding]::UTF8)
        if(-not $txt.Contains('Independent UA+RU EPG updater v2.') -or
           -not $txt.Contains('Replace($rollback,$active,$badVersion)') -or
           -not $txt.Contains('RUChannelsNext24')){
            throw 'Updater contents unexpected'
        }
        [IO.File]::Move($temporary,$updater)
        $temporary=$null
        Write-Host 'UPDATER V2: VERIFIED AND INSTALLED'
    }

    $uaBefore=(Get-FileHash -LiteralPath $ua -Algorithm SHA256).Hash
    Write-Host '=== LIVE UA+RU EPG PUBLICATION ==='
    & $updater -Publish
    if(-not $?){throw 'Updater returned failure'}
    if((Get-FileHash -LiteralPath $ua -Algorithm SHA256).Hash -ne $uaBefore){
        throw 'Original UA EPG changed during installation'
    }
    Write-Host 'ORIGINAL UA EPG: UNCHANGED'

    # Register only after publication passed the full quality gate and HTTPS SHA256.
    Write-Host '=== REGISTER SCHEDULE (4 RUNS/DAY) ==='
    if(Get-ScheduledTask -TaskName $ruTaskName -ErrorAction SilentlyContinue){
        throw "Task name became occupied: $ruTaskName"
    }
    $clockTimes=@('00:20','06:20','12:20','18:20')
    $triggers=@(foreach($clock in $clockTimes){New-ScheduledTaskTrigger -Daily -At $clock})
    if($triggers.Count -ne 4){throw 'Expected four daily triggers'}
    $argsLine='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$updater+'" -Publish'
    $action=New-ScheduledTaskAction -Execute $pwsh -Argument $argsLine
    $principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
    $description='Independent UA+RU EPG with quality gate, SHA256, backup/rollback. Runs 20 min after UA EPG.'
    $null=Register-ScheduledTask -TaskName $ruTaskName -Action $action -Principal $principal -Trigger $triggers -Settings $settings -Description $description -ErrorAction Stop
    $newTaskCreated=$true
    $check=Get-ScheduledTask -TaskName $ruTaskName -ErrorAction Stop
    if(@($check.Triggers).Count -ne 4 -or
       $check.Principal.UserId -notin @('SYSTEM','NT AUTHORITY\SYSTEM') -or
       $check.State -eq 'Disabled'){
        throw 'Registered task verification failed'
    }
    $info=Get-ScheduledTaskInfo -TaskName $ruTaskName -ErrorAction Stop

    Write-Host '=== RESULTS ==='
    [pscustomobject]@{
        ExistingUATask='UNCHANGED'
        CombinedTask=$ruTaskName
        Times='00:20 / 06:20 / 12:20 / 18:20'
        RunAs=$check.Principal.UserId
        NextRun=$info.NextRunTime
        Updater=$updater
        EpgUrl='https://lampa.v6.army/iptv/playlists/IPTV-UA-RU-EPG-Pilot-v1.xml'
        State='REGISTERED'
    } | Format-List
    Write-Host 'UA+RU EPG SCHEDULE: INSTALLED AND VERIFIED'
}
catch {
    $reason=$_.Exception.Message
    if($newTaskCreated){
        try {
            Unregister-ScheduledTask -TaskName $ruTaskName -Confirm:$false -ErrorAction Stop
            Write-Host 'New task removed after validation failure; original UA task untouched'
        }catch{
            Write-Warning "Failed to remove new task: $($_.Exception.Message)"
        }
    }
    throw $reason
}
finally {
    if($temporary -and (Test-Path -LiteralPath $temporary)){
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}
