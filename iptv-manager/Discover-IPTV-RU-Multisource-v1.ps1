#requires -Version 7.0
# IPTV Manager: compare CURATED and LARGE public RU IPTV indexes.
# Discover alternatives for CURRENT channels as well as new unique channels.
# Exclude known bad Cinerama/Skygo providers from candidates.
# Test first HLS media segment; reject identical media URLs across different channels.
# Read-only: no publication, no client/plugin/EPG configuration changes.
[CmdletBinding()]
param([ValidateRange(20,500)][int]$MaxChecks=320)
$ErrorActionPreference='Stop'
$sources=[ordered]@{
    FreeTV='https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8'
    RU='https://iptv-org.github.io/iptv/countries/ru.m3u'
    RUS='https://iptv-org.github.io/iptv/languages/rus.m3u'
    BY='https://iptv-org.github.io/iptv/countries/by.m3u'
    KZ='https://iptv-org.github.io/iptv/countries/kz.m3u'
    NGRCH='https://ngrch.github.io/iptv/ru.m3u'
}
$root='C:\IPTV-Manager\public\playlists'
$uaFile=Join-Path $root 'IPTV-UA.m3u'
$ruFile=Join-Path $root 'IPTV-RU-Pilot-v1.m3u'
$combinedFile=Join-Path $root 'IPTV-UA-RU-Pilot-v1.m3u'
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$stage=Join-Path 'C:\ReservLampac\IPTVPlus\RU-Expansion' ('discovery-'+$runId)
$blocked='(?i)(casino|казино|betting|букмекер|ставки|poker|покер|porn|xxx|adult|18\+|эротик|erotic|playboy|hustler|brazzers)'
$excludedHosts='(?i)(^|\.)(cinerama\.uz|skygo\.mn)$'
function Read-M3u([string]$path) {
    $value=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    if(-not $value.StartsWith('#EXTM3U')){throw "Not M3U: $path"}
    return $value
}
function Add-Existing([string]$text,[Collections.Generic.HashSet[string]]$ids,
                      [Collections.Generic.HashSet[string]]$urls) {
    $lines=$text -split '\r?\n'
    $header=''
    foreach($lineRaw in $lines){
        $line=$lineRaw.Trim()
        if($line.StartsWith('#EXTINF:')){$header=$line;continue}
        if(-not $header -or -not $line -or $line.StartsWith('#')){continue}
        $idMatch=[regex]::Match($header,'(?i)tvg-id="([^"]+)"')
        if($idMatch.Success){[void]$ids.Add($idMatch.Groups[1].Value)}
        [void]$urls.Add($line)
        $header=''
    }
}
function Test-PublicUri([string]$value) {
    $uri=$null
    if(-not [Uri]::TryCreate($value,[UriKind]::Absolute,[ref]$uri)){return $false}
    if($uri.Scheme -notin @('http','https') -or $uri.UserInfo){return $false}
    if($uri.HostNameType -eq [UriHostNameType]::Unknown -or
       $uri.DnsSafeHost -notmatch '\.' -or $uri.DnsSafeHost.EndsWith('.local')){return $false}
    $ip=$null
    if([Net.IPAddress]::TryParse($uri.DnsSafeHost,[ref]$ip)){
        if($ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){return $false}
        $a=$ip.GetAddressBytes()
        if($a[0] -in @(0,10,127) -or $a[0] -ge 224 -or
           ($a[0] -eq 172 -and $a[1] -ge 16 -and $a[1] -le 31) -or
           ($a[0] -eq 192 -and $a[1] -eq 168) -or
           ($a[0] -eq 169 -and $a[1] -eq 254) -or
           ($a[0] -eq 100 -and $a[1] -ge 64 -and $a[1] -le 127)){
            return $false
        }
    }
    # Exclude domains resolving to private/LAN addresses.
    try {
        $addresses=[Net.Dns]::GetHostAddresses($uri.DnsSafeHost)
        if($addresses.Count -eq 0){return $false}
        foreach($address in $addresses){
            if($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork){
                $v=$address.GetAddressBytes()
                if($v[0] -in @(0,10,127) -or $v[0] -ge 224 -or
                    ($v[0] -eq 172 -and $v[1] -ge 16 -and $v[1] -le 31) -or
                    ($v[0] -eq 192 -and $v[1] -eq 168) -or
                    ($v[0] -eq 169 -and $v[1] -eq 254) -or
                    ($v[0] -eq 100 -and $v[1] -ge 64 -and $v[1] -le 127)){return $false}
            } elseif($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6){
                $v=$address.GetAddressBytes()
                if([Net.IPAddress]::IsLoopback($address) -or
                    $address.IsIPv6LinkLocal -or $address.IsIPv6SiteLocal -or
                    $address.IsIPv6Multicast -or ($v[0] -band 254) -eq 252){return $false}
            }else{return $false}
        }
    }catch{return $false}
    return $true
}
foreach($file in @($uaFile,$ruFile,$combinedFile)){
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw "Missing: $file"}
}
$ua=Read-M3u $uaFile
$ru=Read-M3u $ruFile
$combined=Read-M3u $combinedFile
$nUa=[regex]::Matches($ua,'(?m)^#EXTINF:').Count
$nRu=[regex]::Matches($ru,'(?m)^#EXTINF:').Count
$nCombined=[regex]::Matches($combined,'(?m)^#EXTINF:').Count
if($nUa -ne 84 -or $nRu -lt 47 -or $nCombined -ne ($nUa+$nRu)){
    throw "Unexpected source counts UA=$nUa RU=$nRu COMBINED=$nCombined; no action"
}
$beforeHashes=[ordered]@{}
foreach($file in @($uaFile,$ruFile,$combinedFile)){
    $beforeHashes[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
}
$oldIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$oldUrls=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
Add-Existing $combined $oldIds $oldUrls
$oldBaseIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($id in $oldIds){[void]$oldBaseIds.Add(($id -split '@')[0])}
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$pool=[Collections.Generic.List[object]]::new()
$allRussianIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
Write-Host '=== MULTISOURCE RU INDEX: FREE-TV + IPTV-ORG + NGRCH ==='
Write-Host "Published baseline: UA=$nUa RU=$nRu combined=$nCombined"
foreach($source in $sources.GetEnumerator()){
    $file=Join-Path $stage ($source.Key+'.m3u')
    & curl.exe -fLsS --connect-timeout 12 --max-time 65 --max-filesize 12000000 -o $file $source.Value
    if($LASTEXITCODE -ne 0){
        Write-Warning "Source $($source.Key) currently unavailable; other indexes continue"
        continue
    }
    $header=''
    $read=0
    $added=0
    foreach($raw in [IO.File]::ReadLines($file,[Text.Encoding]::UTF8)){
        $line=$raw.Trim()
        if($line.StartsWith('#EXTINF:')){$header=$line;continue}
        if(-not $header -or -not $line -or $line.StartsWith('#')){continue}
        $m=[regex]::Match($header,'(?i)tvg-id="([^"]+)"')
        if(-not $m.Success){$header='';continue}
        $id=$m.Groups[1].Value
        $name=$header.Substring($header.LastIndexOf(',')+1).Trim()
        $read++
        if($source.Key -eq 'RUS'){[void]$allRussianIds.Add($id)}
        # Limit world-wide Free-TV to explicitly Russian broadcast origin.
        $allowed=($source.Key -eq 'FreeTV' -and
            $header -match '(?i)tvg-country="RU"|group-title="Russia"') -or
            ($source.Key -eq 'NGRCH') -or
            ($source.Key -eq 'RU') -or
            ($source.Key -eq 'RUS' -and $id -match '(?i)\.(ru|by|kz|ua|int)@?') -or
            ($source.Key -in @('BY','KZ') -and $allRussianIds.Contains($id))
        $hls=$line -match '(?i)(\.m3u8(?:[?#]|$)|/hls(?:[/?]|$)|\.m3u(?:[?#]|$))'
        $uri=$null
        if([Uri]::TryCreate($line,[UriKind]::Absolute,[ref]$uri) -and
           $allowed -and $hls -and $name -and $header -notmatch $blocked -and
           $uri.DnsSafeHost -notmatch $excludedHosts -and
           -not $oldUrls.Contains($line) -and (Test-PublicUri $line)){
            $priority=if($uri.Scheme -eq 'https'){15}else{0}
            if($source.Key -eq 'FreeTV'){$priority+=120}
            if($source.Key -eq 'NGRCH'){$priority+=70}
            if($source.Key -eq 'RU'){$priority+=40}
            if($source.Key -eq 'RUS'){$priority+=25}
            if($source.Key -in @('BY','KZ')){$priority+=10}
            $existing=$oldBaseIds.Contains(($id -split '@')[0])
            $pool.Add([pscustomobject]@{
                Id=$id;Name=$name;Url=$line;Source=$source.Key
                Priority=$priority;Host=$uri.DnsSafeHost.ToLowerInvariant()
                ExistingChannel=$existing
            })
            $added++
        }
        $header=''
    }
    Write-Host "$($source.Key): indexed $read, eligible new streams $added"
}
$seenUrls=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$seenPrimaryIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$primary=[Collections.Generic.List[object]]::new()
$alternatives=[Collections.Generic.List[object]]::new()
foreach($item in ($pool | Sort-Object Priority -Descending)){
    if(-not $seenUrls.Add($item.Url)){continue}
    if($seenPrimaryIds.Add($item.Id)){$primary.Add($item)}
    else{$alternatives.Add($item)}
}
# Diversify: do not spend most of the sample on one provider.
$checks=[Collections.Generic.List[object]]::new()
$perHost=@{}
foreach($candidate in @($primary.ToArray())+@($alternatives.ToArray())){
    if($checks.Count -ge $MaxChecks){break}
    if(-not $perHost.ContainsKey($candidate.Host)){$perHost[$candidate.Host]=0}
    if($perHost[$candidate.Host] -ge 8){continue}
    $perHost[$candidate.Host]++
    $checks.Add($candidate)
}
Write-Host "Current published channels: $nCombined; candidate IDs across sources: $($primary.Count)"
Write-Host "Provider-diversified HLS tests: $($checks.Count) (limit $MaxChecks)"
Write-Host 'Excluded from testing: Cinerama and Skygo'
if($checks.Count -eq 0){
    Write-Host "Nothing eligible: $stage"
    return
}
Write-Host '=== CHECK MANIFEST + FIRST MEDIA SEGMENT (SERVER SIDE) ==='
$results=@(
    $checks | ForEach-Object -Parallel {
        $item=$_
        $client=$null
        $handler=$null
        $testUri={
            param([string]$value)
            $u=$null
            if(-not [Uri]::TryCreate($value,[UriKind]::Absolute,[ref]$u)){return $false}
            if($u.Scheme -notin @('http','https') -or $u.UserInfo){return $false}
            $hostName=$u.DnsSafeHost.ToLowerInvariant()
            if(-not $hostName.Contains('.') -or $hostName.EndsWith('.local')){return $false}
            $ip=$null
            if([Net.IPAddress]::TryParse($hostName,[ref]$ip)){
                if($ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){return $false}
                $b=$ip.GetAddressBytes()
                if($b[0] -in @(0,10,127) -or $b[0] -ge 224 -or
                   ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
                   ($b[0] -eq 192 -and $b[1] -eq 168) -or
                   ($b[0] -eq 169 -and $b[1] -eq 254) -or
                   ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127)){return $false}
            }
            try{
                $addresses=[Net.Dns]::GetHostAddresses($hostName)
                if($addresses.Count -eq 0){return $false}
                foreach($address in $addresses){
                    if($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork){
                        $b=$address.GetAddressBytes()
                        if($b[0] -in @(0,10,127) -or $b[0] -ge 224 -or
                            ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
                            ($b[0] -eq 192 -and $b[1] -eq 168) -or
                            ($b[0] -eq 169 -and $b[1] -eq 254) -or
                            ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127)){return $false}
                    } elseif($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6){
                        $b=$address.GetAddressBytes()
                        if([Net.IPAddress]::IsLoopback($address) -or
                            $address.IsIPv6LinkLocal -or $address.IsIPv6SiteLocal -or
                            $address.IsIPv6Multicast -or ($b[0] -band 254) -eq 252){return $false}
                    }else{return $false}
                }
            }catch{return $false}
            return $true
        }
        $fetch={
            param([string]$address,[int]$limit)
            if(-not (& $testUri $address)){throw 'Nonpublic/invalid media URL'}
            $uri=[Uri]$address
            $response=$client.GetAsync($uri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            try{
                if(-not $response.IsSuccessStatusCode){throw "HTTP $([int]$response.StatusCode)"}
                $s=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                try{
                    $buffer=[byte[]]::new($limit)
                    $n=0
                    while($n -lt $limit){
                        $count=$s.Read($buffer,$n,$limit-$n)
                        if($count -le 0){break}
                        $n+=$count
                    }
                    if($n -lt 100){throw "Too little content: $n bytes"}
                    return ,([byte[]]$buffer[0..($n-1)])
                }finally{$s.Dispose()}
            }finally{$response.Dispose()}
        }
        try{
            $handler=[Net.Http.HttpClientHandler]::new()
            $handler.AllowAutoRedirect=$false
            $handler.UseCookies=$false
            $client=[Net.Http.HttpClient]::new($handler)
            $client.Timeout=[TimeSpan]::FromSeconds(9)
            $client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0')
            $manifestUrl=$item.Url
            $manifestBytes=& $fetch $manifestUrl 32768
            $text=[Text.Encoding]::UTF8.GetString($manifestBytes)
            if($text.TrimStart([char]0xFEFF) -notmatch '^#EXTM3U' -or $text -notmatch '#EXT-X-'){
                throw 'Not an HLS manifest'
            }
            $lines=@($text -split '\r?\n')
            if($text -match '#EXT-X-STREAM-INF'){
                $variant=''
                $waitForVariant=$false
                foreach($line in $lines){
                    $line=$line.Trim()
                    if($line -match '^#EXT-X-STREAM-INF'){$waitForVariant=$true;continue}
                    if($waitForVariant -and $line -and -not $line.StartsWith('#')){
                        $variant=$line
                        break
                    }
                }
                if(-not $variant){throw 'HLS master has no variant URI'}
                $manifestUrl=([Uri]::new([Uri]$manifestUrl,$variant)).AbsoluteUri
                $manifestBytes=& $fetch $manifestUrl 32768
                $text=[Text.Encoding]::UTF8.GetString($manifestBytes)
                if($text.TrimStart([char]0xFEFF) -notmatch '^#EXTM3U'){
                    throw 'Variant is not HLS'
                }
                $lines=@($text -split '\r?\n')
            }
            if($text -notmatch '#EXTINF:'){
                throw 'HLS media list has no EXTINF segments'
            }
            $segment=''
            $expectSegment=$false
            foreach($line in $lines){
                $line=$line.Trim()
                if($line -match '^#EXTINF:'){$expectSegment=$true;continue}
                if($expectSegment -and $line -and -not $line.StartsWith('#')){
                    $segment=$line
                    break
                }
            }
            if(-not $segment){throw 'No media segment URL'}
            $segmentUrl=([Uri]::new([Uri]$manifestUrl,$segment)).AbsoluteUri
            $segmentBytes=& $fetch $segmentUrl 4096
            $head=[Text.Encoding]::ASCII.GetString($segmentBytes,0,[Math]::Min(64,$segmentBytes.Length))
            if($head -match '(?i)^\s*<(html|!doctype|xml)' -or
               $head -match '^\s*\{' -or $head -match '^#EXTM3U'){
                throw 'Media segment returned HTML or M3U'
            }
            $mediaHash=[Convert]::ToHexString(
                [Security.Cryptography.SHA256]::HashData(
                    [Text.Encoding]::UTF8.GetBytes($manifestUrl))).Substring(0,12)
            [pscustomobject]@{
                Id=$item.Id;Name=$item.Name;Url=$item.Url;Source=$item.Source
                Host=$item.Host;ExistingChannel=$item.ExistingChannel
                MediaUrlHash=$mediaHash
                Verified=$true;Stage='MANIFEST_AND_SEGMENT';Error=''
            }
        }catch{
            [pscustomobject]@{
                Id=$item.Id;Name=$item.Name;Url=$item.Url;Source=$item.Source
                Host=$item.Host;ExistingChannel=$item.ExistingChannel
                MediaUrlHash=''
                Verified=$false;Stage='FAILED';Error=$_.Exception.Message
            }
        }finally{
            if($client){$client.Dispose()}
            if($handler){$handler.Dispose()}
        }
    } -ThrottleLimit 10
)
$working=@($results | Where-Object Verified)
# Reject common final media HLS URI used as multiple different channel identities.
$sharedFeedKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($group in ($working | Group-Object MediaUrlHash)){
    $ids=@($group.Group | ForEach-Object { ($_.Id -split '@')[0] } |
        Sort-Object -Unique)
    if($ids.Count -gt 1){[void]$sharedFeedKeys.Add($group.Name)}
}
$selected=[Collections.Generic.List[object]]::new()
$selectedIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($item in ($working | Sort-Object Source,Name)){
    if($sharedFeedKeys.Contains($item.MediaUrlHash)){continue}
    $baseId=($item.Id -split '@')[0]
    if($selectedIds.Add($baseId)){$selected.Add($item)}
}
$newChannels=@($selected | Where-Object {-not $_.ExistingChannel})
$replacementChannels=@($selected | Where-Object ExistingChannel)
$nl=[Environment]::NewLine
$addedM3u=[Collections.Generic.List[string]]::new()
$addedM3u.Add('#EXTM3U')
foreach($item in ($newChannels | Sort-Object Name)){
    $name=$item.Name -replace '[\r\n]',' '
    $addedM3u.Add('#EXTINF:-1 tvg-id="'+$item.Id+'" group-title="RU Expansion",'+$name)
    $addedM3u.Add($item.Url)
}
$newText=($addedM3u -join $nl)+$nl
$preview=$combined.TrimEnd()
if($newChannels.Count -gt 0){
    $preview+=$nl+(@($addedM3u | Select-Object -Skip 1) -join $nl)
}
$preview+=$nl
$nPreview=[regex]::Matches($preview,'(?m)^#EXTINF:').Count
if($nPreview -ne ($nCombined+$newChannels.Count)){
    throw 'Expanded preview channel count mismatch'
}
foreach($file in @($uaFile,$ruFile,$combinedFile)){
    if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $beforeHashes[$file]){
        throw "Live playlist changed during discovery: $file"
    }
}
$candidatesFile=Join-Path $stage 'IPTV-RU-NEW-candidates.m3u'
$replacementFile=Join-Path $stage 'IPTV-RU-ALTERNATIVES-for-existing.m3u'
$replacementLines=[Collections.Generic.List[string]]::new()
$replacementLines.Add('#EXTM3U')
foreach($item in ($replacementChannels | Sort-Object Name)){
    $replacementLines.Add('#EXTINF:-1 tvg-id="'+$item.Id+'" group-title="RU / Альтернативы",'+$item.Name)
    $replacementLines.Add($item.Url)
}
[IO.File]::WriteAllText($replacementFile,
    (($replacementLines -join $nl)+$nl),[Text.UTF8Encoding]::new($false))
$previewFile=Join-Path $stage 'IPTV-UA-RU-expanded-PREVIEW.m3u'
[IO.File]::WriteAllText($candidatesFile,$newText,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($previewFile,$preview,[Text.UTF8Encoding]::new($false))
$report=[ordered]@{
    runId=$runId;status='MULTISOURCE_STAGED_NOT_PUBLISHED'
    existing=$nCombined;ruExisting=$nRu;uaExisting=$nUa;candidateIds=$primary.Count
    tested=$results.Count;verifiedSegments=$working.Count
    uniqueVerified=$selected.Count
    newUniqueVerifiedChannels=$newChannels.Count
    replacementCandidates=$replacementChannels.Count
    rejectedSharedMediaEndpoints=$sharedFeedKeys.Count
    previewChannels=$nPreview
    beforeSha256=$beforeHashes
    candidatesFile=$candidatesFile;replacementFile=$replacementFile;previewFile=$previewFile
    verified=@($selected);results=@($results)
}
$reportFile=Join-Path $stage 'report.json'
[IO.File]::WriteAllText($reportFile,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Host '=== NETWORK VERIFIED ALTERNATIVES FOR EXISTING CHANNELS ==='
$replacementChannels | Select-Object Name,Id,Source,Host | Format-Table -AutoSize
Write-Host '=== NETWORK VERIFIED NEW CHANNELS ==='
$newChannels | Select-Object Name,Id,Source,Host | Format-Table -AutoSize
Write-Host '=== DUPLICATED MEDIA ENDPOINTS EXCLUDED ==='
Write-Host "Common media-URL hashes rejected: $($sharedFeedKeys.Count)"
Write-Host '=== TOP FAILED CHECK REASONS ==='
$results | Where-Object {-not $_.Verified} | Group-Object Error |
    Sort-Object Count -Descending | Select-Object -First 8 Count,Name |
    Format-Table -AutoSize -Wrap
Write-Host '=== RESULT ==='
[pscustomobject]@{
    ExistingChannels=$nCombined
    CandidateIds=$primary.Count
    Tested=$results.Count
    VerifiedSegments=$working.Count
    AlternativeUrlsForExistingChannels=$replacementChannels.Count
    NewUniqueChannels=$newChannels.Count
    SharedMediaEndpointGroupsRejected=$sharedFeedKeys.Count
    ExpandedPreviewChannels=$nPreview
    NewChannelsPlaylist=$candidatesFile
    AlternativeSourcesPlaylist=$replacementFile
    Report=$reportFile
    Publication='NONE'
} | Format-List
Write-Host 'MULTISOURCE RU DISCOVERY: COMPLETE (NOT PUBLISHED)'
