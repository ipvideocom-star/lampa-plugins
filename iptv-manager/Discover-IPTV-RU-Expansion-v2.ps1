#requires -Version 7.0
# IPTV Manager: find NEW RU/Russian-language HLS streams (not existing 98).
# Read-only production: NO publication, NO replacement, NO client/plugin changes.
[CmdletBinding()]
param([ValidateRange(20,400)][int]$MaxChecks=260)
$ErrorActionPreference='Stop'
$sources=[ordered]@{
    RU='https://iptv-org.github.io/iptv/countries/ru.m3u'
    RUS='https://iptv-org.github.io/iptv/languages/rus.m3u'
    BY='https://iptv-org.github.io/iptv/countries/by.m3u'
    KZ='https://iptv-org.github.io/iptv/countries/kz.m3u'
}
$root='C:\IPTV-Manager\public\playlists'
$uaFile=Join-Path $root 'IPTV-UA.m3u'
$ruFile=Join-Path $root 'IPTV-RU-Pilot-v1.m3u'
$combinedFile=Join-Path $root 'IPTV-UA-RU-Pilot-v1.m3u'
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$stage=Join-Path 'C:\ReservLampac\IPTVPlus\RU-Expansion' ('discovery-'+$runId)
$blocked='(?i)(casino|казино|betting|букмекер|ставки|poker|покер|porn|xxx|adult|18\+|эротик|erotic|playboy|hustler|brazzers)'
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
if($nUa -ne 84 -or $nRu -ne 14 -or $nCombined -ne 98){
    throw "Unexpected source counts UA=$nUa RU=$nRu COMBINED=$nCombined; no action"
}
$beforeHashes=[ordered]@{}
foreach($file in @($uaFile,$ruFile,$combinedFile)){
    $beforeHashes[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
}
$oldIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$oldUrls=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
Add-Existing $combined $oldIds $oldUrls
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$pool=[Collections.Generic.List[object]]::new()
$allRussianIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
Write-Host '=== DOWNLOAD RU / RUS / BY / KZ CHANNEL INDEX ==='
foreach($source in $sources.GetEnumerator()){
    $file=Join-Path $stage ($source.Key+'.m3u')
    & curl.exe -fLsS --connect-timeout 12 --max-time 65 --max-filesize 8000000 -o $file $source.Value
    if($LASTEXITCODE -ne 0){throw "Cannot download source $($source.Key): $LASTEXITCODE"}
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
        # In BY and KZ, only accept entries also present in Russian-language list.
        $allowed=($source.Key -eq 'RU') -or
            ($source.Key -eq 'RUS' -and $id -match '(?i)\.(ru|by|kz|ua|int)@') -or
            ($source.Key -in @('BY','KZ') -and $allRussianIds.Contains($id))
        $hls=$line -match '(?i)(\.m3u8(?:[?#]|$)|/hls(?:[/?]|$)|\.m3u(?:[?#]|$))'
        if($allowed -and $hls -and $name -and $header -notmatch $blocked -and
           -not $oldIds.Contains($id) -and -not $oldUrls.Contains($line) -and
           (Test-PublicUri $line)){
            $priority=if(([Uri]$line).Scheme -eq 'https'){20}else{0}
            if($source.Key -eq 'RU'){$priority+=10}
            if($source.Key -eq 'RUS'){$priority+=5}
            $pool.Add([pscustomobject]@{Id=$id;Name=$name;Url=$line;Source=$source.Key;Priority=$priority})
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
$checks=@(@($primary.ToArray())+@($alternatives.ToArray()) | Select-Object -First $MaxChecks)
Write-Host "Existing channels preserved: 98; unique new candidate IDs: $($primary.Count)"
Write-Host "New streams selected for testing: $($checks.Count) (limit $MaxChecks)"
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
            if($head -match '(?i)^\s*<(html|!doctype|xml)' -or $head -match '^#EXTM3U'){
                throw 'Media segment returned HTML or M3U'
            }
            [pscustomobject]@{
                Id=$item.Id;Name=$item.Name;Url=$item.Url;Source=$item.Source
                Verified=$true;Stage='MANIFEST_AND_SEGMENT';Error=''
            }
        }catch{
            [pscustomobject]@{
                Id=$item.Id;Name=$item.Name;Url=$item.Url;Source=$item.Source
                Verified=$false;Stage='FAILED';Error=$_.Exception.Message
            }
        }finally{
            if($client){$client.Dispose()}
            if($handler){$handler.Dispose()}
        }
    } -ThrottleLimit 10
)
$working=@($results | Where-Object Verified)
$selected=[Collections.Generic.List[object]]::new()
$selectedIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($item in $working){
    if($selectedIds.Add($item.Id)){$selected.Add($item)}
}
$nl=[Environment]::NewLine
$addedM3u=[Collections.Generic.List[string]]::new()
$addedM3u.Add('#EXTM3U')
foreach($item in ($selected | Sort-Object Name)){
    $name=$item.Name -replace '[\r\n]',' '
    $addedM3u.Add('#EXTINF:-1 tvg-id="'+$item.Id+'" group-title="RU Expansion",'+$name)
    $addedM3u.Add($item.Url)
}
$newText=($addedM3u -join $nl)+$nl
$preview=$combined.TrimEnd()+$nl+(@($addedM3u | Select-Object -Skip 1) -join $nl)+$nl
$nPreview=[regex]::Matches($preview,'(?m)^#EXTINF:').Count
if($nPreview -ne (98+$selected.Count)){throw 'Expanded preview channel count mismatch'}
foreach($file in @($uaFile,$ruFile,$combinedFile)){
    if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $beforeHashes[$file]){
        throw "Live playlist changed during discovery: $file"
    }
}
$candidatesFile=Join-Path $stage 'IPTV-RU-NEW-candidates.m3u'
$previewFile=Join-Path $stage 'IPTV-UA-RU-expanded-PREVIEW.m3u'
[IO.File]::WriteAllText($candidatesFile,$newText,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($previewFile,$preview,[Text.UTF8Encoding]::new($false))
$report=[ordered]@{
    runId=$runId;status='STAGED_NOT_PUBLISHED'
    existing=98;newUniqueCandidateIds=$primary.Count
    tested=$results.Count;verifiedSegments=$working.Count;newUniqueVerifiedChannels=$selected.Count
    previewChannels=$nPreview
    beforeSha256=$beforeHashes
    candidatesFile=$candidatesFile;previewFile=$previewFile
    verified=@($selected);results=@($results)
}
$reportFile=Join-Path $stage 'report.json'
[IO.File]::WriteAllText($reportFile,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Host '=== NEW VERIFIED RU/RUS CHANNELS ==='
$selected | Select-Object Name,Id,Source | Format-Table -AutoSize
Write-Host '=== RESULT ==='
[pscustomobject]@{
    ExistingChannels=98
    NewUniqueCandidateIds=$primary.Count
    Tested=$results.Count
    VerifiedSegments=$working.Count
    NewUniqueChannels=$selected.Count
    ExpandedPreviewChannels=$nPreview
    Preview=$previewFile
    Report=$reportFile
    Publication='NONE'
} | Format-List
Write-Host 'RU EXPANSION DISCOVERY: COMPLETE (NOT PUBLISHED)'
