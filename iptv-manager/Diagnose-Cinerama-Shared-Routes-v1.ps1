#requires -Version 7.0
# Read-only: determine whether 22 current Cinerama RU entries resolve
# to the same HLS media playlist. Fetches no video segments.
[CmdletBinding()]
param([ValidateRange(8,25)][int]$TimeoutSeconds=14)
$ErrorActionPreference='Stop'
$playlist='C:\IPTV-Manager\public\playlists\IPTV-RU-Pilot-v1.m3u'
$outRoot='C:\ReservLampac\IPTVPlus\Cinerama-Diagnostics'
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$outDir=Join-Path $outRoot ('routes-'+$runId)
$before=(Get-FileHash -LiteralPath $playlist -Algorithm SHA256).Hash
$ua='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36'
$items=[Collections.Generic.List[object]]::new()
$header=''
foreach($raw in [IO.File]::ReadLines($playlist,[Text.Encoding]::UTF8)){
    $line=$raw.Trim()
    if($line.StartsWith('#EXTINF:')){$header=$line;continue}
    if(-not $header -or -not $line -or $line.StartsWith('#')){continue}
    $uri=$null
    if([Uri]::TryCreate($line,[UriKind]::Absolute,[ref]$uri) -and
        $uri.DnsSafeHost -match '(^|\.)cinerama\.uz$'){
        $items.Add([pscustomobject]@{
            Name=$header.Substring($header.LastIndexOf(',')+1).Trim()
            Url=$line
            Host=$uri.DnsSafeHost
        })
    }
    $header=''
}
if($items.Count -ne 22){throw "Expected 22 Cinerama entries, found $($items.Count)"}
Write-Host '=== CINERAMA: COMPARE FINAL HLS MEDIA URLS ==='
Write-Host '22 channel URLs; no playback, no video segments, no production writes'

$results=@(
    $items.ToArray() | ForEach-Object -Parallel {
        $item=$_
        $timeout=$using:TimeoutSeconds
        $agent=$using:ua
        $client=$null
        $handler=$null
        $sha={
            param([string]$data)
            $raw=[Text.Encoding]::UTF8.GetBytes($data)
            [Convert]::ToHexString(
                [Security.Cryptography.SHA256]::HashData($raw)).Substring(0,12)
        }
        $validate={
            param([Uri]$uri)
            if($null -eq $uri -or $uri.Scheme -notin @('http','https') -or
                $uri.UserInfo -or $uri.DnsSafeHost -notmatch '(^|\.)cinerama\.uz$'){
                throw 'NON_CINERAMA_TARGET_NOT_FETCHED'
            }
            $addresses=[Net.Dns]::GetHostAddresses($uri.DnsSafeHost)
            foreach($ip in $addresses){
                if([Net.IPAddress]::IsLoopback($ip)){throw 'PRIVATE_DNS'}
                if($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork){
                    $b=$ip.GetAddressBytes()
                    if($b[0] -in @(0,10,127) -or $b[0] -ge 224 -or
                        ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
                        ($b[0] -eq 192 -and $b[1] -eq 168) -or
                        ($b[0] -eq 169 -and $b[1] -eq 254)){
                        throw 'PRIVATE_DNS'
                    }
                }elseif($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6){
                    if($ip.IsIPv6LinkLocal -or $ip.IsIPv6SiteLocal -or $ip.IsIPv6Multicast){
                        throw 'PRIVATE_DNS'
                    }
                }else{throw 'UNKNOWN_ADDRESS_TYPE'}
            }
        }
        $fetch={
            param([Uri]$start)
            $url=$start
            $redirects=0
            $cancel=[Threading.CancellationTokenSource]::new(
                [TimeSpan]::FromSeconds($timeout))
            try{
                while($true){
                    & $validate $url
                    $response=$client.GetAsync($url,
                        [Net.Http.HttpCompletionOption]::ResponseHeadersRead,
                        $cancel.Token).GetAwaiter().GetResult()
                    try{
                        $status=[int]$response.StatusCode
                        if($status -in @(301,302,303,307,308)){
                            if($redirects -ge 4){throw 'TOO_MANY_REDIRECTS'}
                            if(-not $response.Headers.Location){throw 'REDIRECT_WITHOUT_LOCATION'}
                            $url=[Uri]::new($url,$response.Headers.Location)
                            $redirects++
                            continue
                        }
                        if(-not $response.IsSuccessStatusCode){throw "HTTP_$status"}
                        if($response.Content.Headers.ContentLength -gt 65536){
                            throw 'MANIFEST_LARGER_THAN_LIMIT'
                        }
                        $stream=$response.Content.ReadAsStreamAsync($cancel.Token).GetAwaiter().GetResult()
                        try{
                            $buf=[byte[]]::new(65537)
                            $n=0
                            while($n -lt $buf.Length){
                                $read=$stream.ReadAsync($buf,$n,$buf.Length-$n,
                                    $cancel.Token).GetAwaiter().GetResult()
                                if($read -lt 1){break}
                                $n+=$read
                            }
                            if($n -gt 65536){throw 'MANIFEST_LARGER_THAN_LIMIT'}
                            $txt=[Text.Encoding]::UTF8.GetString($buf,0,$n)
                            if(-not $txt.TrimStart([char]0xFEFF).StartsWith('#EXTM3U')){
                                throw ('NOT_HLS_'+$n+'_BYTES')
                            }
                            return [pscustomobject]@{Final=$url;Body=$txt;Redirects=$redirects}
                        }finally{$stream.Dispose()}
                    }finally{$response.Dispose()}
                }
            }finally{$cancel.Dispose()}
        }
        try{
            $handler=[Net.Http.HttpClientHandler]::new()
            $handler.AllowAutoRedirect=$false
            $handler.UseCookies=$false
            $handler.AutomaticDecompression=(
                [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate)
            $client=[Net.Http.HttpClient]::new($handler)
            $client.Timeout=[TimeSpan]::FromSeconds($timeout+2)
            $client.DefaultRequestHeaders.UserAgent.ParseAdd($agent)
            $initial=& $fetch ([Uri]$item.Url)
            if($initial.Body -match '#EXT-X-STREAM-INF'){
                $want=$false
                $variant=''
                foreach($line in ($initial.Body -split '\r?\n')){
                    $line=$line.Trim()
                    if($line.StartsWith('#EXT-X-STREAM-INF')){$want=$true;continue}
                    if($want -and $line -and -not $line.StartsWith('#')){
                        $variant=$line
                        break
                    }
                }
                if(-not $variant){throw 'NO_HLS_VARIANT'}
                $media=& $fetch ([Uri]::new($initial.Final,$variant))
            }elseif($initial.Body -match '#EXTINF:'){
                $media=$initial
            }else{
                throw 'NOT_MASTER_OR_MEDIA_HLS'
            }
            $segmentCount=[regex]::Matches($media.Body,'(?m)^#EXTINF:').Count
            if($segmentCount -lt 1){throw 'NO_MEDIA_SEGMENTS'}
            [pscustomobject]@{
                Channel=$item.Name;SourceHost=$item.Host
                Status='MEDIA_MANIFEST'
                MasterHash=(& $sha $initial.Body)
                MediaUrlHash=(& $sha $media.Final.AbsoluteUri)
                MediaBodyHash=(& $sha $media.Body)
                Segments=$segmentCount;Error=''
            }
        }catch{
            $reason=$_.Exception.Message
            if($reason -match 'timed out|Timeout|canceled'){$reason='TIMEOUT'}
            if($reason.Length -gt 100){$reason=$reason.Substring(0,100)}
            [pscustomobject]@{
                Channel=$item.Name;SourceHost=$item.Host
                Status='UNVERIFIED';MasterHash='';MediaUrlHash=''
                MediaBodyHash='';Segments=0;Error=$reason
            }
        }finally{
            if($client){$client.Dispose()}
            if($handler){$handler.Dispose()}
        }
    } -ThrottleLimit 6
)
if($results.Count -ne 22){throw "Incomplete results: $($results.Count)/22"}
if((Get-FileHash -LiteralPath $playlist -Algorithm SHA256).Hash -ne $before){
    throw 'Published playlist changed during diagnostic'
}
$verified=@($results | Where-Object {$_.Status -eq 'MEDIA_MANIFEST'})
$groups=@(
    $verified | Group-Object MediaUrlHash |
        Where-Object {$_.Count -gt 1} |
        Sort-Object Count -Descending
)
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$reportFile=Join-Path $outDir 'report.json'
[IO.File]::WriteAllText($reportFile,([ordered]@{
    Status='READ_ONLY_DIAGNOSTIC'
    CheckedUtc=[DateTime]::UtcNow.ToString('o')
    SourceSHA256=$before
    Total=22
    Verified=$verified.Count
    SharedFeedGroups=@($groups | ForEach-Object {
        [pscustomobject]@{
            MediaUrlHash=$_.Name
            Count=$_.Count
            Channels=@($_.Group.Channel)
        }
    })
    Results=@($results)
} | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Host '=== DUPLICATE FINAL MEDIA URL HASHES ==='
if($groups.Count -eq 0){Write-Host 'No duplicates among successfully checked streams'}
foreach($group in $groups){
    [pscustomobject]@{
        Streams=$group.Count
        MediaHash=$group.Name
        Channels=($group.Group.Channel -join '; ')
    } | Format-List
}
Write-Host '=== INDIVIDUAL STREAM RESULTS ==='
$results | Select-Object Channel,Status,MediaUrlHash,MediaBodyHash,
    Segments,Error | Format-Table -AutoSize -Wrap
Write-Host '=== SUMMARY ==='
[pscustomobject]@{
    TotalCinerama=22
    MediaManifests=$verified.Count
    Unverified=22-$verified.Count
    DuplicateGroups=$groups.Count
    Report=$reportFile
    Publication='NONE'
    LivePlaylists='UNCHANGED'
} | Format-List
Write-Host 'CINERAMA ROUTE AUDIT: COMPLETE'
