#requires -Version 7.0
# Read-only M3U health audit for the current 47 RU channels (UA+RU = 131).
# Tests HLS manifest AND media segment, tracks repeated failures.
# Never edits published M3U/XMLTV, plugin settings, or scheduled tasks.
[CmdletBinding()]
param([ValidateRange(8,30)][int]$TimeoutSeconds=16)
$ErrorActionPreference='Stop'
$root='C:\IPTV-Manager\public\playlists'
$ua=Join-Path $root 'IPTV-UA.m3u'
$ru=Join-Path $root 'IPTV-RU-Pilot-v1.m3u'
$combined=Join-Path $root 'IPTV-UA-RU-Pilot-v1.m3u'
$stageRoot='C:\ReservLampac\IPTVPlus\RU-Health'
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$runDir=Join-Path $stageRoot ('audit-'+$runId)
$statePath=Join-Path $stageRoot 'health-state.json'
$lockPath=Join-Path $stageRoot 'RU-health-audit.lock'
$lock=$null
$tmp=$null
$now=[DateTime]::UtcNow

function Get-Hash([string]$value) {
    $bytes=[Text.Encoding]::UTF8.GetBytes($value)
    return [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
}
function Read-Entries([string]$file) {
    $text=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    if(-not $text.StartsWith('#EXTM3U')){throw "Not M3U: $file"}
    $items=[Collections.Generic.List[object]]::new()
    $header=''
    foreach($raw in ($text -split '\r?\n')){
        $line=$raw.Trim()
        if($line.StartsWith('#EXTINF:')){$header=$line;continue}
        if(-not $header -or -not $line -or $line.StartsWith('#')){continue}
        $match=[regex]::Match($header,'(?i)tvg-id="([^"]+)"')
        if(-not $match.Success){throw "Missing tvg-id in $file"}
        $id=$match.Groups[1].Value
        $name=$header.Substring($header.LastIndexOf(',')+1).Trim()
        $items.Add([pscustomobject]@{
            Id=$id;Name=$name;Url=$line;Key=(Get-Hash ($id+'|'+$line))
        })
        $header=''
    }
    return ,$items
}
function Assert-Preserved([object[]]$expected,[object[]]$received,[string]$label){
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($item in $received){
        [void]$seen.Add($item.Id+'|'+$item.Url)
    }
    foreach($item in $expected){
        if(-not $seen.Contains($item.Id+'|'+$item.Url)){
            throw "Missing $label channel in combined playlist: $($item.Id)"
        }
    }
}

foreach($file in @($ua,$ru,$combined)){
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw "Missing live playlist: $file"}
}
$uaItems=(Read-Entries $ua).ToArray()
$ruItems=(Read-Entries $ru).ToArray()
$allItems=(Read-Entries $combined).ToArray()
if($uaItems.Count -ne 84 -or $ruItems.Count -ne 47 -or $allItems.Count -ne 131){
    throw "Unexpected channel counts: UA=$($uaItems.Count), RU=$($ruItems.Count), combined=$($allItems.Count)"
}
Assert-Preserved $uaItems $allItems 'UA'
Assert-Preserved $ruItems $allItems 'RU'
$before=@{}
foreach($file in @($ua,$ru,$combined)){
    $before[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
}
New-Item -ItemType Directory -Path $stageRoot,$runDir -Force | Out-Null

try{
    $lock=[IO.FileStream]::new($lockPath,[IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    Write-Host '=== AUDIT 47 EXISTING RU HLS STREAMS ==='
    Write-Host "Local source integrity: UA 84, RU 47, combined 131"
    Write-Host "Timeout per URL: $TimeoutSeconds seconds"

    $results=@(
        $ruItems | ForEach-Object -Parallel {
            $item=$_
            $timeout=$using:TimeoutSeconds
            $client=$null
            $handler=$null
            $checkUrl={
                param([string]$value)
                $u=$null
                if(-not [Uri]::TryCreate($value,[UriKind]::Absolute,[ref]$u) -or
                   $u.Scheme -notin @('http','https') -or $u.UserInfo){return $false}
                $hostname=$u.DnsSafeHost.ToLowerInvariant()
                if(-not $hostname.Contains('.') -or $hostname.EndsWith('.local')){return $false}
                try{
                    $addresses=[Net.Dns]::GetHostAddresses($hostname)
                    if($addresses.Count -eq 0){return $false}
                    foreach($ip in $addresses){
                        if($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork){
                            $b=$ip.GetAddressBytes()
                            if($b[0] -in @(0,10,127) -or $b[0] -ge 224 -or
                                ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
                                ($b[0] -eq 192 -and $b[1] -eq 168) -or
                                ($b[0] -eq 169 -and $b[1] -eq 254) -or
                                ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127)){return $false}
                        }elseif($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6){
                            $b=$ip.GetAddressBytes()
                            if([Net.IPAddress]::IsLoopback($ip) -or $ip.IsIPv6LinkLocal -or
                                $ip.IsIPv6SiteLocal -or $ip.IsIPv6Multicast -or
                                ($b[0] -band 254) -eq 252){return $false}
                        }else{return $false}
                    }
                }catch{return $false}
                return $true
            }
            $get={
                param([string]$url,[int]$limit)
                if(-not (& $checkUrl $url)){throw 'INVALID_OR_PRIVATE_URL'}
                $uri=[Uri]$url
                $cts=[Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($timeout))
                try{
                    $response=$client.GetAsync($uri,
                        [Net.Http.HttpCompletionOption]::ResponseHeadersRead,
                        $cts.Token).GetAwaiter().GetResult()
                    try{
                        if(-not $response.IsSuccessStatusCode){
                            throw "HTTP_$([int]$response.StatusCode)"
                        }
                        $stream=$response.Content.ReadAsStreamAsync($cts.Token).GetAwaiter().GetResult()
                        try{
                            $buffer=[byte[]]::new($limit)
                            $read=0
                            while($read -lt $limit){
                                $n=$stream.ReadAsync($buffer,$read,$limit-$read,$cts.Token).GetAwaiter().GetResult()
                                if($n -le 0){break}
                                $read+=$n
                            }
                            if($read -lt 100){throw "RESPONSE_TOO_SHORT_$read"}
                            return ,([byte[]]$buffer[0..($read-1)])
                        }finally{$stream.Dispose()}
                    }finally{$response.Dispose()}
                }finally{$cts.Dispose()}
            }
            try{
                $handler=[Net.Http.HttpClientHandler]::new()
                $handler.AllowAutoRedirect=$false
                $handler.UseCookies=$false
                $client=[Net.Http.HttpClient]::new($handler)
                $client.Timeout=[TimeSpan]::FromSeconds($timeout+2)
                $client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0')
                $manifestUrl=$item.Url
                $manifest=[Text.Encoding]::UTF8.GetString((& $get $manifestUrl 32768))
                if($manifest.TrimStart([char]0xFEFF) -notmatch '^#EXTM3U' -or
                   $manifest -notmatch '#EXT-X-'){throw 'INVALID_HLS_MANIFEST'}
                if($manifest -match '#EXT-X-STREAM-INF'){
                    $getVariant=$false
                    $variant=''
                    foreach($line in ($manifest -split '\r?\n')){
                        $line=$line.Trim()
                        if($line -match '^#EXT-X-STREAM-INF'){$getVariant=$true;continue}
                        if($getVariant -and $line -and -not $line.StartsWith('#')){
                            $variant=$line
                            break
                        }
                    }
                    if(-not $variant){throw 'MISSING_HLS_VARIANT'}
                    $manifestUrl=([Uri]::new([Uri]$manifestUrl,$variant)).AbsoluteUri
                    $manifest=[Text.Encoding]::UTF8.GetString((& $get $manifestUrl 32768))
                }
                if($manifest -notmatch '#EXTINF:'){throw 'MISSING_MEDIA_SEGMENTS'}
                $findSegment=$false
                $segment=''
                foreach($line in ($manifest -split '\r?\n')){
                    $line=$line.Trim()
                    if($line -match '^#EXTINF:'){$findSegment=$true;continue}
                    if($findSegment -and $line -and -not $line.StartsWith('#')){
                        $segment=$line
                        break
                    }
                }
                if(-not $segment){throw 'MISSING_FIRST_SEGMENT'}
                $segmentUrl=([Uri]::new([Uri]$manifestUrl,$segment)).AbsoluteUri
                $bytes=& $get $segmentUrl 4096
                $head=[Text.Encoding]::ASCII.GetString(
                    $bytes,0,[Math]::Min($bytes.Length,64))
                if($head -match '(?i)^\s*<(html|!doctype|xml)' -or
                   $head -match '^\s*\{' -or $head -match '^#EXTM3U'){
                    throw 'SEGMENT_NOT_MEDIA'
                }
                [pscustomobject]@{Id=$item.Id;Name=$item.Name;Url=$item.Url;
                    Key=$item.Key;Available=$true;Status='HLS_SEGMENT_OK'}
            }catch{
                $reason=$_.Exception.Message
                if($reason -match 'cancel|timed out|Timeout|operation was canceled'){
                    $reason='TIMEOUT'
                }elseif($reason -match 'HTTP_(403|451)'){
                    $reason='HTTP_GEO_OR_ACCESS'
                }elseif($reason -match 'HTTP_(301|302|307|308)'){
                    $reason='HTTP_REDIRECT'
                }elseif($reason -match 'HTTP_429'){
                    $reason='HTTP_RATE_LIMIT'
                }elseif($reason.Length -gt 145){
                    $reason=$reason.Substring(0,145)
                }
                [pscustomobject]@{Id=$item.Id;Name=$item.Name;Url=$item.Url;
                    Key=$item.Key;Available=$false;Status=$reason}
            }finally{
                if($client){$client.Dispose()}
                if($handler){$handler.Dispose()}
            }
        } -ThrottleLimit 8
    )

    if($results.Count -ne 47){throw "Audit incomplete: only $($results.Count)/47 results"}
    $previous=@{version=1;channels=@{}}
    if(Test-Path -LiteralPath $statePath -PathType Leaf){
        $previous=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 |
            ConvertFrom-Json -AsHashtable
        if($previous.version -ne 1 -or $null -eq $previous.channels){
            throw 'Unrecognized previous health state'
        }
    }
    $next=@{version=1;updatedUtc=$now.ToString('o');channels=@{}}
    $rows=[Collections.Generic.List[object]]::new()
    $quarantine=[Collections.Generic.List[object]]::new()
    foreach($result in $results){
        $old=$null
        if($previous.channels.ContainsKey($result.Key)){
            $old=$previous.channels[$result.Key]
        }
        $failures=0
        $totalChecks=0
        $lastSuccess=''
        $lastCountedFailure=''
        if($old){
            $failures=[int]$old.consecutiveFailures
            $totalChecks=[int]$old.totalChecks
            $lastSuccess=[string]$old.lastSuccessUtc
            $lastCountedFailure=[string]$old.lastCountedFailureUtc
        }
        $totalChecks++
        $counted=$true
        if($result.Available){
            $failures=0
            $lastSuccess=$now.ToString('o')
            $lastCountedFailure=''
        } else {
            # More than one failure in an hour counts as ONE incident.
            $prior=[DateTime]::MinValue
            if($lastCountedFailure){
                [void][DateTime]::TryParse($lastCountedFailure,[ref]$prior)
            }
            if($prior -gt $now.AddHours(-1)){
                $counted=$false
            } else {
                $failures++
                $lastCountedFailure=$now.ToString('o')
            }
        }
        $status=if($result.Available){'HEALTHY'}
            elseif($failures -ge 3){'QUARANTINE_CANDIDATE'}
            elseif($failures -eq 2){'RECHECK_REQUIRED'}
            else{'TRANSIENT_OR_UNVERIFIED'}
        if($status -eq 'QUARANTINE_CANDIDATE'){$quarantine.Add($result)}
        $next.channels[$result.Key]=[ordered]@{
            id=$result.Id;name=$result.Name;url=$result.Url
            consecutiveFailures=$failures;totalChecks=$totalChecks
            lastSuccessUtc=$lastSuccess
            lastCountedFailureUtc=$lastCountedFailure
            lastSeenUtc=$now.ToString('o')
            lastStatus=$result.Status
        }
        $rows.Add([pscustomobject]@{
            Channel=$result.Name;Id=$result.Id
            Available=$result.Available;Reason=$result.Status
            Failures=$failures;CountedIncident=$counted
            Action=$status
        })
    }
    foreach($file in @($ua,$ru,$combined)){
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $before[$file]){
            throw "Live playlist unexpectedly changed: $file"
        }
    }
    $report=Join-Path $runDir 'report.json'
    $reportData=[ordered]@{
        status='HEALTH_AUDIT_NOT_PUBLISHED'
        runId=$runId;checkedAtUtc=$now.ToString('o')
        tested=$results.Count;healthy=@($results | Where-Object Available).Count
        unavailableOrUnverified=@($results | Where-Object {-not $_.Available}).Count
        quarantineCandidates=$quarantine.Count
        originalCounts=@{UA=84;RU=47;Combined=131}
        results=@($rows)
    }
    [IO.File]::WriteAllText($report,($reportData|ConvertTo-Json -Depth 8),
        [Text.UTF8Encoding]::new($false))
    $tmp=Join-Path $stageRoot ('health-state-'+[guid]::NewGuid().ToString('N')+'.tmp')
    [IO.File]::WriteAllText($tmp,($next|ConvertTo-Json -Depth 8),
        [Text.UTF8Encoding]::new($false))
    if(Test-Path -LiteralPath $statePath){
        $backup=Join-Path $runDir 'health-state-before.json'
        [IO.File]::Replace($tmp,$statePath,$backup)
    }else{
        [IO.File]::Move($tmp,$statePath)
    }
    $tmp=$null

    Write-Host '=== AUDIT HEALTH SUMMARY ==='
    [pscustomobject]@{
        RUChannels=$results.Count
        AvailableHlsSegments=@($results|Where-Object Available).Count
        UnavailableOrUnverified=@($results|Where-Object {-not $_.Available}).Count
        RecheckRequired=@($rows|Where-Object {$_.Action -eq 'RECHECK_REQUIRED'}).Count
        QuarantineCandidates=$quarantine.Count
        Publication='NONE'
        ExistingPlaylists='UNCHANGED'
        State=$statePath
        Report=$report
    } | Format-List
    Write-Host '=== FAILED OR UNVERIFIED CHANNELS ==='
    $rows | Where-Object {-not $_.Available} |
        Select-Object Channel,Reason,Failures,Action | Format-Table -AutoSize -Wrap
    Write-Host 'RU HEALTH AUDIT: COMPLETE (NO CHANNELS REMOVED)'
}
finally {
    if($tmp -and (Test-Path -LiteralPath $tmp)){
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    if($lock){$lock.Dispose()}
}
