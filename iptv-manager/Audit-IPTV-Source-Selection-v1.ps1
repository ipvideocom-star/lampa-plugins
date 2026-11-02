#requires -Version 7.0
# IPTV source selection: audit independent HLS alternatives for one region.
# Adapted from verified HLS audit v2; fetches only manifests and 4 KiB
# of first video segment. A passing network test does NOT establish the
# actual channel content. No production/published IPTV changes.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceSelectionReportPath,
    [ValidateSet('RU','UA')][string]$Region='RU',
    [ValidateRange(8,35)][int]$TimeoutSeconds=19,
    [ValidateRange(5,30)][int]$RecheckSeconds=12,
    [ValidateRange(1,6)][int]$Concurrency=4
)
$ErrorActionPreference='Stop'
$sourceReportPath=(Resolve-Path -LiteralPath $SourceSelectionReportPath -ErrorAction Stop).ProviderPath
$root='C:\ReservLampac\IPTVPlus\SourceSelection'
$ru='C:\IPTV-Manager\public\playlists\IPTV-RU-Pilot-v1.m3u'
$ua='C:\IPTV-Manager\public\playlists\IPTV-UA.m3u'
$both='C:\IPTV-Manager\public\playlists\IPTV-UA-RU-Pilot-v1.m3u'
$base=(Resolve-Path -LiteralPath $root -ErrorAction Stop).ProviderPath
if(-not $sourceReportPath.StartsWith($base+[IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)){
    throw 'Selection report must reside in SourceSelection folder'
}
$baseHashes=[ordered]@{}
foreach($file in @($ru,$ua,$both)){
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){
        throw "Published playlist missing: $file"
    }
    $baseHashes[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
}
$selection=Get-Content -LiteralPath $sourceReportPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
if($selection.Status -ne 'STAGED_SOURCE_INVENTORY_NO_PUBLICATION' -or
   [int]$selection.PublishedRU -ne 47 -or
   [int]$selection.PublishedUA -ne 84 -or
   [int]$selection.PublishedCombined -ne 131){
    throw 'Unexpected source-selection report'
}
foreach($file in $baseHashes.Keys){
    if($selection.PublishedHashes[$file] -ne $baseHashes[$file]){
        throw "Published playlist changed since source selection: $file"
    }
}
$folder=Split-Path -Parent $sourceReportPath
$testPath=if($Region -eq 'RU'){[string]$selection.TestRu}else{[string]$selection.TestUa}
$testPath=(Resolve-Path -LiteralPath $testPath -ErrorAction Stop).ProviderPath
if(-not $testPath.StartsWith($folder+[IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)){
    throw 'Review M3U path is outside the selected source folder'
}
$reviewHash=(Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash
$candidates=[Collections.Generic.List[object]]::new()
$header=''
$sourceName=''
$agent=''
$referer=''
$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($raw in [IO.File]::ReadLines($testPath,[Text.Encoding]::UTF8)){
    $line=$raw.Trim()
    if($line.StartsWith('#EXTINF:')){
        $header=$line
        $agent=''
        $referer=''
        continue
    }
    if(-not $header -or -not $line){continue}
    if($line -match '(?i)^#EXTVLCOPT:http-user-agent=(.*)$'){
        $agent=$Matches[1];continue
    }
    if($line -match '(?i)^#EXTVLCOPT:http-referrer=(.*)$'){
        $referer=$Matches[1];continue
    }
    if($line.StartsWith('#')){continue}
    $uri=$null
    if(-not [Uri]::TryCreate($line,[UriKind]::Absolute,[ref]$uri) -or
       $uri.Scheme -notin @('http','https') -or $uri.UserInfo){
        throw 'Invalid source URL found in test M3U'
    }
    $hostName=$uri.DnsSafeHost.ToLowerInvariant()
    if($hostName -match '(^|\.)(cinerama\.uz|skygo\.mn)$'){
        throw 'Quarantined host unexpectedly found in test M3U'
    }
    $idMatch=[regex]::Match($header,'(?i)tvg-id="([^"]*)"')
    $name=$header.Substring($header.LastIndexOf(',')+1).Trim()
    $sourceMatch=[regex]::Match($name,'\s+\[([^\]]+)\]$')
    if(-not $sourceMatch.Success){throw 'Source label missing from staged review M3U'}
    $sourceName=$sourceMatch.Groups[1].Value
    $name=$name.Substring(0,$sourceMatch.Index).Trim()
    $id=if($idMatch.Success){$idMatch.Groups[1].Value}else{''}
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes($line))).Substring(0,16)
    $key=$name+'|'+$line
    if($seen.Add($key)){
        $candidates.Add([pscustomobject]@{
            Channel=$name;Id=$id;URL=$line;UrlHash=$hash
            Host=$hostName;Source=$sourceName
            UserAgent=$agent;Referrer=$referer;Quality=''
        })
    }
    $header=''
}
if($candidates.Count -lt 1 -or $candidates.Count -gt 250){
    throw "Unexpected staged source count: $($candidates.Count)"
}
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$dir=Join-Path $root ('source-audit-'+$Region.ToLowerInvariant()+'-'+$stamp)
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$oldCount=$candidates.Count
Write-Host '=== IPTV INDEPENDENT SOURCE HLS AUDIT ==='
Write-Host "$Region review candidates: $oldCount"
Write-Host "Per-request timeout: $TimeoutSeconds seconds; parallel: $Concurrency; recheck: $RecheckSeconds seconds"
Write-Host 'Only bounded HLS manifests and the beginning of ONE segment per source'
Write-Host 'No stream playback, no publication, no playlist changes'

$results=@(
    $candidates.ToArray() | ForEach-Object -Parallel {
        $entry=$_
        $timeout=$using:TimeoutSeconds
        $delay=$using:RecheckSeconds
        $client=$null
        $handler=$null
        $phase='PREPARE'
        $hash={
            param([string]$s)
            $bytes=[Text.Encoding]::UTF8.GetBytes($s)
            [Convert]::ToHexString(
                [Security.Cryptography.SHA256]::HashData($bytes)).Substring(0,12)
        }
        $validate={
            param([Uri]$url)
            if($null -eq $url -or $url.Scheme -notin @('http','https') -or
               $url.UserInfo -or $url.DnsSafeHost -notmatch '\.'){
                throw 'INVALID_OR_NONPUBLIC_URI'
            }
            $ips=[Net.Dns]::GetHostAddresses($url.DnsSafeHost)
            if($ips.Count -lt 1){throw 'DNS_NOT_RESOLVED'}
            foreach($ip in $ips){
                if([Net.IPAddress]::IsLoopback($ip)){throw 'PRIVATE_DNS'}
                if($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork){
                    $b=$ip.GetAddressBytes()
                    if($b[0] -in @(0,10,127) -or $b[0] -ge 224 -or
                       ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
                       ($b[0] -eq 192 -and $b[1] -eq 168) -or
                       ($b[0] -eq 169 -and $b[1] -eq 254) -or
                       ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127) -or
                       ($b[0] -eq 198 -and $b[1] -in @(18,19))){
                        throw 'PRIVATE_DNS'
                    }
                }elseif($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6){
                    $b=$ip.GetAddressBytes()
                    if($ip.IsIPv6LinkLocal -or $ip.IsIPv6SiteLocal -or
                       $ip.IsIPv6Multicast -or ($b[0] -band 254) -eq 252){
                        throw 'PRIVATE_DNS'
                    }
                }else{throw 'UNKNOWN_IP_TYPE'}
            }
        }
        $fetch={
            param([Uri]$start,[int]$limit,[bool]$prefixOnly=$false)
            $uri=$start
            $hops=0
            $cancel=[Threading.CancellationTokenSource]::new(
                [TimeSpan]::FromSeconds($timeout))
            try{
                while($true){
                    & $validate $uri
                    $resp=$client.GetAsync(
                        $uri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,
                        $cancel.Token).GetAwaiter().GetResult()
                    try{
                        $code=[int]$resp.StatusCode
                        if($code -in @(301,302,303,307,308)){
                            if($hops -ge 4){throw 'TOO_MANY_REDIRECTS'}
                            $location=$resp.Headers.Location
                            if($null -eq $location){throw 'REDIRECT_WITHOUT_LOCATION'}
                            $uri=[Uri]::new($uri,$location)
                            $hops++
                            continue
                        }
                        if(-not $resp.IsSuccessStatusCode){throw "HTTP_$code"}
                        # HLS .ts / .m4s segments often are megabytes long:
                        # Content-Length is NOT a valid reason to reject a prefix read.
                        # Only complete HLS manifests retain the strict size cap.
                        if(-not $prefixOnly -and
                           $resp.Content.Headers.ContentLength -gt $limit){
                            throw 'MANIFEST_TOO_LARGE'
                        }
                        $stream=$resp.Content.ReadAsStreamAsync($cancel.Token).GetAwaiter().GetResult()
                        try{
                            $capacity=if($prefixOnly){$limit}else{$limit+1}
                            $buffer=[byte[]]::new($capacity)
                            $n=0
                            while($n -lt $buffer.Length){
                                $p=$stream.ReadAsync($buffer,$n,$buffer.Length-$n,
                                    $cancel.Token).GetAwaiter().GetResult()
                                if($p -le 0){break}
                                $n+=$p
                            }
                            if(-not $prefixOnly -and $n -gt $limit){
                                throw 'MANIFEST_TOO_LARGE'
                            }
                            if($n -lt 1){throw 'EMPTY_RESPONSE'}
                            $content=[byte[]]::new($n)
                            [Array]::Copy($buffer,$content,$n)
                            return [pscustomobject]@{Bytes=$content;Uri=$uri;Redirects=$hops}
                        }finally{$stream.Dispose()}
                    }finally{$resp.Dispose()}
                }
            }finally{$cancel.Dispose()}
        }
        $manifest={
            param([Uri]$url)
            $packet=& $fetch $url 65536
            $txt=[Text.Encoding]::UTF8.GetString($packet.Bytes)
            if(-not $txt.TrimStart([char]0xFEFF).StartsWith('#EXTM3U')){
                throw 'NOT_HLS_MANIFEST'
            }
            return [pscustomobject]@{Text=$txt;Uri=$packet.Uri}
        }
        try{
            $url=[Uri]$entry.URL
            $handler=[Net.Http.HttpClientHandler]::new()
            $handler.AllowAutoRedirect=$false
            $handler.UseCookies=$false
            $handler.AutomaticDecompression=(
                [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate)
            $client=[Net.Http.HttpClient]::new($handler)
            $client.Timeout=[TimeSpan]::FromSeconds($timeout+2)
            if($entry.UserAgent){
                $client.DefaultRequestHeaders.UserAgent.ParseAdd($entry.UserAgent)
            }else{
                $client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0')
            }
            if($entry.Referrer){
                $ref=[Uri]$entry.Referrer
                if($ref.Scheme -notin @('http','https') -or $ref.UserInfo){
                    throw 'INVALID_SOURCE_REFERRER'
                }
                $client.DefaultRequestHeaders.Referrer=$ref
            }
            $phase='FETCH_MASTER'
            $master=& $manifest $url
            $media=$master
            if($master.Text -match '#EXT-X-STREAM-INF'){
                $variant=''
                $next=$false
                foreach($line in ($master.Text -split '\r?\n')){
                    $line=$line.Trim()
                    if($line.StartsWith('#EXT-X-STREAM-INF')){$next=$true;continue}
                    if($next -and $line -and -not $line.StartsWith('#')){
                        $variant=$line
                        break
                    }
                }
                if(-not $variant){throw 'HLS_MASTER_WITHOUT_VARIANT'}
                $phase='FETCH_MEDIA'
                $media=& $manifest ([Uri]::new($master.Uri,$variant))
            }
            if($media.Text -notmatch '#EXTINF:'){
                throw 'HLS_MEDIA_WITHOUT_SEGMENTS'
            }
            $first=''
            $expect=$false
            foreach($line in ($media.Text -split '\r?\n')){
                $line=$line.Trim()
                if($line.StartsWith('#EXTINF:')){$expect=$true;continue}
                if($expect -and $line -and -not $line.StartsWith('#')){
                    $first=$line
                    break
                }
            }
            if(-not $first){throw 'NO_SEGMENT_ADDRESS'}
            $phase='FETCH_SEGMENT_PREFIX'
            $segment=& $fetch ([Uri]::new($media.Uri,$first)) 4096 $true
            if($segment.Bytes.Length -lt 188){throw 'SEGMENT_TOO_SHORT'}
            $prefix=[Text.Encoding]::ASCII.GetString(
                $segment.Bytes,0,[Math]::Min($segment.Bytes.Length,32))
            if($prefix -match '(?i)^\s*<(html|!doctype|xml)|^\s*\{|^#EXTM3U'){
                throw 'SEGMENT_CONTAINS_ERROR_TEXT'
            }
            $phase='WAIT_FOR_PROGRESS'
            Start-Sleep -Seconds $delay
            $phase='RECHECK_MEDIA'
            $again=& $manifest $media.Uri
            if($again.Text -notmatch '#EXTINF:'){
                throw 'SECOND_MEDIA_MANIFEST_INVALID'
            }
            $changed=$media.Text -cne $again.Text
            $phase='COMPLETE'
            [pscustomobject]@{
                Channel=$entry.Channel;Id=$entry.Id;Source=$entry.Source
                Host=$entry.Host;UrlHash=$entry.UrlHash
                Status=if($changed){'HLS_PROGRESS_OBSERVED'}else{'HLS_SEGMENT_OK_NO_PROGRESS_SEEN'}
                MediaUriHash=(& $hash $media.Uri.AbsoluteUri)
                MediaBodyHash=(& $hash $media.Text)
                Segments=[regex]::Matches($media.Text,'(?m)^#EXTINF:').Count
                HeadersUsed=([bool]$entry.UserAgent -or [bool]$entry.Referrer)
                Stage=$phase
                Error=''
            }
        }catch{
            $reason=$_.Exception.Message
            if($reason -match 'timed out|Timeout|canceled'){ $reason='TIMEOUT' }
            elseif($reason -match '^HTTP_\d+'){ }
            elseif($reason -notmatch '^(DNS_NOT_RESOLVED|PRIVATE_DNS|UNKNOWN_IP_TYPE|INVALID_OR_NONPUBLIC_URI|TOO_MANY_REDIRECTS|REDIRECT_WITHOUT_LOCATION|MANIFEST_TOO_LARGE|EMPTY_RESPONSE|NOT_HLS_MANIFEST|INVALID_SOURCE_REFERRER|HLS_MASTER_WITHOUT_VARIANT|HLS_MEDIA_WITHOUT_SEGMENTS|NO_SEGMENT_ADDRESS|SEGMENT_TOO_SHORT|SEGMENT_CONTAINS_ERROR_TEXT|SECOND_MEDIA_MANIFEST_INVALID)$'){
                $reason='OTHER_REQUEST_ERROR'
            }
            [pscustomobject]@{
                Channel=$entry.Channel;Id=$entry.Id;Source=$entry.Source
                Host=$entry.Host;UrlHash=$entry.UrlHash
                Status='FAILED';MediaUriHash='';MediaBodyHash='';Segments=0
                HeadersUsed=([bool]$entry.UserAgent -or [bool]$entry.Referrer)
                Stage=$phase
                Error=$reason
            }
        }finally{
            if($client){$client.Dispose()}
            if($handler){$handler.Dispose()}
        }
    } -ThrottleLimit $Concurrency
)
if($results.Count -ne $candidates.Count){
    throw "Incomplete audit: $($results.Count) of $($candidates.Count)"
}
if((Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash -ne $reviewHash){
    throw 'Staged review list changed during audit'
}
foreach($file in $baseHashes.Keys){
    if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $baseHashes[$file]){
        throw "Published playlist changed during audit: $file"
    }
}
$success=@($results | Where-Object {$_.Status -ne 'FAILED'})
$progress=@($results | Where-Object {$_.Status -eq 'HLS_PROGRESS_OBSERVED'})
$shared=@(
    $success | Group-Object MediaUriHash | Where-Object {
        @($_.Group | Select-Object -ExpandProperty Channel -Unique).Count -gt 1
    }
)
$badMedia=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($item in $shared){[void]$badMedia.Add($item.Name)}
foreach($entry in $results){
    if($entry.MediaUriHash -and $badMedia.Contains($entry.MediaUriHash)){
        $entry.Status='SHARED_MEDIA_ROUTE_REVIEW'
    }
}
# Generate a separate technically passing TEST M3U; this is NOT broadcast verified
# and is NOT served through Lampa/Caddy. Each row comes from a staged source.
$passM3u=Join-Path $dir ($Region+'-NETWORK-OK-TEST-NOT-PUBLISHED.m3u')
$passEntries=[Collections.Generic.List[string]]::new()
$passEntries.Add('#EXTM3U')
$approved=@($results | Where-Object {
    $_.Status -eq 'HLS_PROGRESS_OBSERVED' -and $_.MediaUriHash
})
$unique=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($ok in $approved){
    $match=@($candidates | Where-Object {
        $_.Channel -ceq $ok.Channel -and $_.UrlHash -eq $ok.UrlHash
    })
    if($match.Count -ne 1){throw "Ambiguous passing URL for $($ok.Channel)"}
    $entry=$match[0]
    $uniqueKey=$entry.Channel+'|'+$entry.URL
    if(-not $unique.Add($uniqueKey)){continue}
    $title=($entry.Channel -replace '[\r\n,",]',' ').Trim()
    $id=([string]$entry.Id -replace '[\r\n"]','').Trim()
    $passEntries.Add('#EXTINF:-1 tvg-id="'+$id+
        '" group-title="SOURCE TEST '+$Region+'",'+$title+' ['+$entry.Host+']')
    if($entry.UserAgent){
        $passEntries.Add('#EXTVLCOPT:http-user-agent='+
            ($entry.UserAgent -replace '[\r\n]',''))
    }
    if($entry.Referrer){
        $passEntries.Add('#EXTVLCOPT:http-referrer='+
            ($entry.Referrer -replace '[\r\n]',''))
    }
    $passEntries.Add($entry.URL)
}
[IO.File]::WriteAllText($passM3u,
    ($passEntries.ToArray() -join [Environment]::NewLine)+[Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))
$report=[ordered]@{
    Mode='SOURCE_SELECTION_NETWORK_ONLY_NOT_CONTENT_VERIFIED'
    DateUtc=[DateTime]::UtcNow.ToString('o')
    Region=$Region
    SelectionReport=$sourceReportPath
    ReviewM3u=$testPath
    ReviewSha256=$reviewHash
    NetworkPassingTestM3U=$passM3u
    NetworkPassingTestEntries=$unique.Count
    RealBroadcastVerified=$false
    ProductionSHA256=$baseHashes
    Total=$results.Count
    HlsSegmentOk=$success.Count
    ProgressObserved=$progress.Count
    SharedRouteGroups=$shared.Count
    SharedRoutes=@($shared | ForEach-Object {
        [pscustomobject]@{
            MediaUriHash=$_.Name;Count=$_.Count
            ChannelNames=@($_.Group.Channel)
        }
    })
    Results=@($results)
    LivePlaylist='UNCHANGED'
    Publication='NONE'
}
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$reportFile=Join-Path $dir 'report.json'
[IO.File]::WriteAllText($reportFile,($report|ConvertTo-Json -Depth 9),
    [Text.UTF8Encoding]::new($false))
Write-Host '=== WORKING HLS CANDIDATES (BROADCAST CONTENT NOT VERIFIED) ==='
$results | Where-Object {$_.Status -ne 'FAILED'} |
    Select-Object Channel,Source,Host,Status,Segments |
    Format-Table -AutoSize -Wrap
Write-Host '=== FAILED CANDIDATES ==='
$results | Where-Object {$_.Status -eq 'FAILED'} |
    Group-Object Stage,Error | Sort-Object Count -Descending |
    Select-Object Count,Name | Format-Table -AutoSize -Wrap
Write-Host '=== FAILURE STAGES ==='
$results | Where-Object {$_.Status -eq 'FAILED'} |
    Group-Object Stage | Sort-Object Count -Descending |
    Select-Object Count,Name | Format-Table -AutoSize
$passing=@($results | Where-Object {
    $_.Status -eq 'HLS_PROGRESS_OBSERVED' -and $_.MediaUriHash
})
$channels=@($passing | Select-Object -ExpandProperty Channel -Unique)
Write-Host '=== NETWORK AUDIT SUMMARY ==='
[pscustomobject]@{
    Region=$Region
    CandidatesTested=$results.Count
    ChannelsWithProgress=$channels.Count
    TestM3u=$passM3u
    HlsSegmentResponses=$success.Count
    HlsProgressObserved=$progress.Count
    SharedMediaRouteGroups=$shared.Count
    Failed=$results.Count-$success.Count
    Report=$reportFile
    LivePlaylists='UNCHANGED'
    AutomaticReplacement='DISABLED'
} | Format-List
Write-Host 'IPTV SOURCE SELECTION HLS AUDIT: COMPLETE (NO PUBLICATION)'
