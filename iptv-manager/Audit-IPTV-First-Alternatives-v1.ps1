#requires -Version 7.0
# IPTV Manager - read-only First Channel alternatives audit, W2022 direct route.
# Tests existing 2026-11-03 discovery candidates as HLS manifests + TS segments.
# No stream URL publication; no changes to IPTV+, Caddy, Relay, 3proxy or live M3Us.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$inputPath='C:\ReservLampac\IPTVPlus\Discovery\source-discovery-20261103-174853-693718c1.json'
$outDir='C:\ReservLampac\IPTVPlus\FirstChannel'
if(-not (Test-Path -LiteralPath $inputPath -PathType Leaf)){throw "Missing staged discovery: $inputPath"}
$source=Get-Content -LiteralPath $inputPath -Raw -Encoding UTF8 | ConvertFrom-Json
if(@($source.Records).Count -ne 1949){throw 'Unexpected discovery record count'}
function VariantOf([string]$name){
    $n=$name.Normalize([Text.NormalizationForm]::FormKC)
    $n=$n.Replace('Ⓢ','').Replace('Ⓖ','').Replace('Ⓨ','').ToLowerInvariant().Trim()
    $n=$n -replace '(?i)\s*(?:\(|\[)?(?:hd|fhd|sd|1080p|720p)(?:\)|\])?\s*$',''
    $n=$n -replace '\s+',' '
    $shift=[regex]::Match($n,'([+-])\s*(\d+)\s*$')
    if($shift.Success){$n=$n.Substring(0,$shift.Index).Trim()}
    if($n -notmatch '^(первый(?: канал)?|1 канал|орт|channel one)$'){return ''}
    if(-not $shift.Success){return 'Первый'}
    $suffix=$shift.Groups[1].Value+$shift.Groups[2].Value
    if($suffix -eq '-1'){return 'Первый -1'}
    if($suffix -eq '+2'){return 'Первый +2'}
    return ''
}
$items=@(
    foreach($r in $source.Records){
        $variant=VariantOf ([string]$r.Channel)
        if(-not $variant){continue}
        $uri=$null
        if(-not [Uri]::TryCreate([string]$r.URL,[UriKind]::Absolute,[ref]$uri) -or
           $uri.Scheme -notin @('http','https') -or $uri.UserInfo){continue}
        $key=[Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]$r.URL))
        ).Substring(0,16)
        if($key -cne [string]$r.URLKey){throw "Discovery URLKey mismatch: $($r.URLKey)"}
        [pscustomobject]@{
            Variant=$variant;Channel=[string]$r.Channel;URLKey=$key
            Url=[string]$r.URL;Host=$uri.DnsSafeHost;Feed=[string]$r.Feed
            UserAgent=[string]$r.UserAgent;Referrer=[string]$r.Referrer
        }
    }
)
$expected=@{'Первый'=23;'Первый -1'=1;'Первый +2'=2}
foreach($k in $expected.Keys){
    $n=@($items|Where-Object Variant -eq $k).Count
    if($n -ne $expected[$k]){throw "Unexpected candidate count $k : $n"}
}
if(@($items|Select-Object -ExpandProperty URLKey -Unique).Count -ne 26){
    throw 'Duplicate source URLs across variants; review required'
}
$skipped=@($items|Where-Object Host -eq 'zabava-htlive.cdn.ngenix.net')
$probes=@($items|Where-Object Host -ne 'zabava-htlive.cdn.ngenix.net')
Write-Host '=== FIRST CHANNEL BATCH, DIRECT W2022 ==='
Write-Host "Candidates: $($items.Count); blocked Zabava skipped: $($skipped.Count); probing: $($probes.Count)"
Write-Host 'Read-only: HLS manifest / nested variant / 4 KB of first media segment'
$before=@{}
foreach($path in @(
    'C:\IPTV-Manager\public\playlists\IPTV-RU-Pilot-v1.m3u',
    'C:\IPTV-Manager\public\playlists\IPTV-UA-RU-Pilot-v1.m3u'
)){
    $before[$path]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
$results=@(
    $probes | ForEach-Object -Parallel {
            $item=$_
            $timeout=12
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
            # Follow only a bounded number of HTTP redirects and validate
            # EVERY target. Preserve the resolved URI for relative HLS links.
            $get={
                param([string]$url,[int]$limit)
                $current=[Uri]$url
                $redirects=0
                $cts=[Threading.CancellationTokenSource]::new(
                    [TimeSpan]::FromSeconds($timeout))
                try {
                    while($true) {
                        if(-not (& $checkUrl $current.AbsoluteUri)) {
                            throw 'INVALID_OR_PRIVATE_URL'
                        }
                        $response=$client.GetAsync(
                            $current,
                            [Net.Http.HttpCompletionOption]::ResponseHeadersRead,
                            $cts.Token).GetAwaiter().GetResult()
                        try {
                            $status=[int]$response.StatusCode
                            if($status -in @(301,302,303,307,308)) {
                                if($redirects -ge 4) {throw 'TOO_MANY_REDIRECTS'}
                                $location=$response.Headers.Location
                                if($null -eq $location) {throw 'REDIRECT_WITHOUT_LOCATION'}
                                $target=[Uri]::new($current,$location)
                                if(-not (& $checkUrl $target.AbsoluteUri)) {
                                    throw 'REDIRECT_TO_INVALID_OR_PRIVATE_URL'
                                }
                                $current=$target
                                $redirects++
                                continue
                            }
                            if(-not $response.IsSuccessStatusCode) {
                                throw "HTTP_$status"
                            }
                            $stream=$response.Content.ReadAsStreamAsync($cts.Token).GetAwaiter().GetResult()
                            try {
                                $buffer=[byte[]]::new($limit)
                                $read=0
                                while($read -lt $limit) {
                                    $n=$stream.ReadAsync(
                                        $buffer,$read,$limit-$read,
                                        $cts.Token).GetAwaiter().GetResult()
                                    if($n -le 0) {break}
                                    $read+=$n
                                }
                                if($read -lt 100){throw "RESPONSE_TOO_SHORT_$read"}
                                return [pscustomobject]@{
                                    Bytes=([byte[]]$buffer[0..($read-1)])
                                    FinalUrl=$current.AbsoluteUri
                                    Redirects=$redirects
                                }
                            }finally{$stream.Dispose()}
                        }finally{$response.Dispose()}
                    }
                }finally{$cts.Dispose()}
            }
            try{
                $handler=[Net.Http.HttpClientHandler]::new()
                $handler.AllowAutoRedirect=$false
                $handler.UseProxy=$false
                $handler.UseCookies=$false
                $client=[Net.Http.HttpClient]::new($handler)
                $client.Timeout=[TimeSpan]::FromSeconds($timeout+2)
                if($item.UserAgent -and $item.UserAgent -notmatch '[\r\n]'){
                    [void]$client.DefaultRequestHeaders.UserAgent.TryParseAdd([string]$item.UserAgent)
                }else{
                    $client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0')
                }
                if($item.Referrer -and $item.Referrer -notmatch '[\r\n]'){
                    $refUri=$null
                    if([Uri]::TryCreate([string]$item.Referrer,[UriKind]::Absolute,[ref]$refUri) -and
                       $refUri.Scheme -in @('http','https') -and (& $checkUrl $refUri.AbsoluteUri)){
                        $client.DefaultRequestHeaders.Referrer=$refUri
                    }
                }
                $firstResult=& $get $item.Url 32768
                $manifestUrl=$firstResult.FinalUrl
                $totalRedirects=[int]$firstResult.Redirects
                $manifest=[Text.Encoding]::UTF8.GetString($firstResult.Bytes)
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
                    $nextManifest=([Uri]::new([Uri]$manifestUrl,$variant)).AbsoluteUri
                    $variantResult=& $get $nextManifest 32768
                    $manifestUrl=$variantResult.FinalUrl
                    $totalRedirects += [int]$variantResult.Redirects
                    $manifest=[Text.Encoding]::UTF8.GetString($variantResult.Bytes)
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
                $segmentResult=& $get $segmentUrl 4096
                $totalRedirects += [int]$segmentResult.Redirects
                $bytes=$segmentResult.Bytes
                $head=[Text.Encoding]::ASCII.GetString(
                    $bytes,0,[Math]::Min($bytes.Length,64))
                if($head -match '(?i)^\s*<(html|!doctype|xml)' -or
                   $head -match '^\s*\{' -or $head -match '^#EXTM3U'){
                    throw 'SEGMENT_NOT_MEDIA'
                }
                # Verify several 188-byte TS packets, even with an ID3 prefix.
                $ts=$false
                for($i=0;$i -lt [Math]::Min(188,$bytes.Length-377);$i++){
                    if($bytes[$i] -eq 71 -and $bytes[$i+188] -eq 71 -and $bytes[$i+376] -eq 71){
                        $ts=$true;break
                    }
                }
                if(-not $ts){throw 'SEGMENT_NOT_TS_REVIEW'}
                [pscustomobject]@{Variant=$item.Variant;Name=$item.Channel;
                    Feed=$item.Feed;Host=$item.Host;URLKey=$item.URLKey;Available=$true;
                    Status='TS_SEGMENT_CONFIRMED';Redirects=$totalRedirects}
            }catch{
                $reason=$_.Exception.Message
                if($reason -match 'cancel|timed out|Timeout|operation was canceled'){
                    $reason='TIMEOUT'
                }elseif($reason -match 'HTTP_(403|451)'){
                    $reason='HTTP_GEO_OR_ACCESS'
                }elseif($reason -match 'REDIRECT|HTTP_(301|302|307|308)'){
                    $reason='REDIRECT_UNVERIFIED'
                }elseif($reason -match 'HTTP_429'){
                    $reason='HTTP_RATE_LIMIT'
                }elseif($reason.Length -gt 145){
                    $reason=$reason.Substring(0,145)
                }
                [pscustomobject]@{Variant=$item.Variant;Name=$item.Channel;
                    Feed=$item.Feed;Host=$item.Host;URLKey=$item.URLKey;Available=$false;
                    Status=$reason;Redirects=0}
            }finally{
                if($client){$client.Dispose()}
                if($handler){$handler.Dispose()}
            }
        } -ThrottleLimit 6
)
foreach($item in $skipped){
    $results+= [pscustomobject]@{
        Variant=$item.Variant;Name=$item.Channel;Feed=$item.Feed
        Host=$item.Host;URLKey=$item.URLKey;Available=$false
        Status='SKIP_KNOWN_ZABAVA_BLOCK';Redirects=0
    }
}
if(@($results).Count -ne $items.Count){throw 'Audit incomplete'}
foreach($path in $before.Keys){
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $before[$path]){
        throw "Production file changed while checking: $path"
    }
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$filename='First-Alternatives-Audit-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.csv'
$out=Join-Path $outDir $filename
$results|Sort-Object Variant,Available,Host -Descending |
    Export-Csv -LiteralPath $out -NoTypeInformation -Encoding utf8
Write-Host '=== RESULTS BY VARIANT ==='
$results|Group-Object Variant,Status|Sort-Object Name |
    Select-Object Name,Count|Format-Table -AutoSize
Write-Host '=== CONFIRMED TS SEGMENTS ==='
$results|Where-Object Available|Sort-Object Variant,Host|
    Select-Object Variant,Name,Feed,Host,URLKey,Redirects|Format-Table -AutoSize
Write-Host "AUDIT_REPORT: $out"
Write-Host 'PRODUCTION CHANGES: NONE'
Write-Host 'TESTED ROUTE: W2022 DIRECT ONLY'
