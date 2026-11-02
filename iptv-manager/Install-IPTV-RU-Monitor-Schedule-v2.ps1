#requires -Version 7.0
# Install 2 non-destructive IPTV RU monitoring tasks (health and discovery).
# v2 fixes invalid foreach pipeline when validating registered task triggers.
# Never changes existing UA/UA+RU EPG schedules, playlists, Caddy, plugins.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$base='C:\ReservLampac\IPTVPlus'
$health=Join-Path $base 'RU-Health\Audit-IPTV-RU-Health-v3.ps1'
$discovery=Join-Path $base 'RU-Expansion\Discover-IPTV-RU-Expansion-v3.ps1'
$runner=Join-Path $base 'RU-Monitor\Run-IPTV-RU-Monitor-v1.ps1'
$taskHealth='IPTV-Manager-RU-Health-6h'
$taskDiscovery='IPTV-Manager-RU-Discovery-Daily'
$moduleSpecs=@(
    [pscustomobject]@{
        Path=$health
        Url='https://raw.githubusercontent.com/ipvideocom-star/lampa-plugins/1dd9c5a789d2610f5984a2939704126be5741aa5/iptv-manager/Audit-IPTV-RU-Health-v3.ps1'
        Marker='TOO_MANY_REDIRECTS'
    }
    [pscustomobject]@{
        Path=$discovery
        Url='https://raw.githubusercontent.com/ipvideocom-star/lampa-plugins/aeab7436ade7666a8b25a54495d81d078b9c4ae2/iptv-manager/Discover-IPTV-RU-Expansion-v3.ps1'
        Marker='existing=$nCombined'
    }
    [pscustomobject]@{
        Path=$runner
        Url='https://raw.githubusercontent.com/ipvideocom-star/lampa-plugins/87e20735fa19c6536d100133f5daf282fc409953/iptv-manager/Run-IPTV-RU-Monitor-v1.ps1'
        Marker='IPTV MONITOR'
    }
)
$created=[Collections.Generic.List[string]]::new()
$tempFiles=[Collections.Generic.List[string]]::new()
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$nonce=[guid]::NewGuid().ToString('N').Substring(0,8)
$pwsh=(Get-Command pwsh.exe -CommandType Application -ErrorAction Stop).Source
if($PSVersionTable.PSVersion.Major -lt 7){throw 'PowerShell 7 is required'}
foreach($name in @('IPTV-Manager-EPG-UA-6h','IPTV-Manager-EPG-UA-RU-6h')){
    if(-not (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue)){
        throw "Existing EPG schedule not found: $name"
    }
}
foreach($name in @($taskHealth,$taskDiscovery)){
    if(Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue){
        throw "Monitoring task already exists, will not overwrite: $name"
    }
}
foreach($spec in $moduleSpecs){
    if(Test-Path -LiteralPath $spec.Path -PathType Leaf){
        throw "Monitoring script already exists, will not overwrite: $($spec.Path)"
    }
    $dir=Split-Path $spec.Path -Parent
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
$recordDir=Join-Path $base ('RU-Monitor\Task-References-'+$stamp+'-'+$nonce)
New-Item -ItemType Directory -Path $recordDir -Force | Out-Null
foreach($name in @('IPTV-Manager-EPG-UA-6h','IPTV-Manager-EPG-UA-RU-6h')){
    Export-ScheduledTask -TaskName $name | Set-Content -LiteralPath (Join-Path $recordDir ($name+'.xml')) -Encoding UTF8
}
Write-Host '=== EPG TASKS PRESERVED ==='
Write-Host "Reference exports: $recordDir"
try {
    Write-Host '=== DOWNLOAD AND VERIFY MONITORING MODULES ==='
    foreach($spec in $moduleSpecs){
        $temp=Join-Path (Split-Path $spec.Path -Parent) ('module-download-'+[guid]::NewGuid().ToString('N')+'.tmp')
        $tempFiles.Add($temp)
        & curl.exe -fLsS --connect-timeout 10 --max-time 45 -o $temp $spec.Url
        if($LASTEXITCODE -ne 0){throw "Download failed: $($spec.Path)"}
        $tokens=$null;$errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($temp,[ref]$tokens,[ref]$errors)
        if(@($errors).Count -gt 0){
            $errors | Format-List
            throw "Downloaded script syntax error: $($spec.Path)"
        }
        $text=[IO.File]::ReadAllText($temp,[Text.Encoding]::UTF8)
        if(-not $text.Contains($spec.Marker)){
            throw "Downloaded script content check failed: $($spec.Path)"
        }
        [IO.File]::Move($temp,$spec.Path)
        Write-Host "MODULE VERIFIED: $($spec.Path)"
    }
    Write-Host '=== AUDIT WITH SAFE REDIRECT HANDLING ==='
    & $health -TimeoutSeconds 16
    if(-not $?){throw 'Health audit failed; new tasks not registered'}
    Write-Host '=== REGISTER MONITORING SCHEDULES ==='
    $principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 25)
    $healthTimes=@('01:00','07:00','13:00','19:00')
    $healthTriggers=@(foreach($hour in @(1,7,13,19)){New-ScheduledTaskTrigger -Daily -At ([datetime]::Today.AddHours($hour))})
    $discoveryTriggers=@(New-ScheduledTaskTrigger -Daily -At ([datetime]::Today.AddHours(3).AddMinutes(30)))
    $actionHealth=New-ScheduledTaskAction -Execute $pwsh -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$runner+'" -Mode Health')
    $actionDiscovery=New-ScheduledTaskAction -Execute $pwsh -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$runner+'" -Mode Discovery')
    $null=Register-ScheduledTask -TaskName $taskHealth -Trigger $healthTriggers -Action $actionHealth -Principal $principal -Settings $settings -Description 'Read-only IPTV RU HLS health checks and incident history, every 6 hours; no quarantine changes' -ErrorAction Stop
    $created.Add($taskHealth)
    $null=Register-ScheduledTask -TaskName $taskDiscovery -Trigger $discoveryTriggers -Action $actionDiscovery -Principal $principal -Settings $settings -Description 'Read-only IPTV RU public-source discovery daily; saves staged candidates, does not publish' -ErrorAction Stop
    $created.Add($taskDiscovery)
    Write-Host '=== VALIDATE REGISTERED TASKS ==='
    foreach($entry in @(
        [pscustomobject]@{Name=$taskHealth;Times=$healthTimes;Mode='Health'}
        [pscustomobject]@{Name=$taskDiscovery;Times=@('03:30');Mode='Discovery'}
    )){
        $task=Get-ScheduledTask -TaskName $entry.Name -ErrorAction Stop
        $actual=@(
            foreach($trigger in @($task.Triggers)){
                $boundary=[string]$trigger.StartBoundary
                if($boundary -match 'T(\d{2}:\d{2})') {
                    $Matches[1]
                }
                else {
                    "INVALID:$boundary"
                }
            }
        )
        $actual=@($actual | Sort-Object)
        $expected=@($entry.Times | Sort-Object)
        if($task.State -eq 'Disabled' -or $actual.Count -ne $expected.Count -or
           ($actual -join ',') -ne ($expected -join ',')){
            throw "Task triggers mismatch: $($entry.Name)"
        }
        $actions=@($task.Actions)
        if($actions.Count -ne 1 -or
           -not $actions[0].Arguments.Contains($runner) -or
           -not $actions[0].Arguments.Contains('-Mode '+$entry.Mode)){
            throw "Task action mismatch: $($entry.Name)"
        }
        $info=Get-ScheduledTaskInfo -TaskName $entry.Name
        [pscustomobject]@{
            Task=$entry.Name;State=$task.State
            Account=$task.Principal.UserId
            Times=($actual -join ', ')
            NextRun=$info.NextRunTime
        } | Format-List
        Export-ScheduledTask -TaskName $entry.Name | Set-Content -LiteralPath (Join-Path $recordDir ($entry.Name+'.xml')) -Encoding UTF8
    }
    Write-Host 'IPTV MANAGER MONITORING: INSTALLED AND VERIFIED'
    Write-Host 'EPG TASKS AND PUBLISHED 131 CHANNELS: UNCHANGED'
    Write-Host 'AUTOMATIC CHANNEL REMOVAL: DISABLED'
}
catch {
    $reason=$_.Exception.Message
    foreach($name in $created){
        try{
            Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
            Write-Host "ROLLED BACK NEW TASK: $name"
        }catch{
            Write-Warning "Could not remove new task: $name"
        }
    }
    throw $reason
}
finally {
    foreach($temp in $tempFiles){
        if(Test-Path -LiteralPath $temp){
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        }
    }
}
