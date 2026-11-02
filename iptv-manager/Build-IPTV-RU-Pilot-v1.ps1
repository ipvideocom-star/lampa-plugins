#requires -Version 7.0
# Independent RU HLS pilot. Never replaces existing UA, EPG, Caddy, or plugin settings.
[CmdletBinding()]
param([int]$MaxChecks=100,[int]$MinWorking=3)
$ErrorActionPreference='Stop'
$sourceUrls=[ordered]@{
    RU='https://iptv-org.github.io/iptv/countries/ru.m3u'
    RUS='https://iptv-org.github.io/iptv/languages/rus.m3u'
}
$root='C:\IPTV-Manager\public\playlists'
$uaFile=Join-Path $root 'IPTV-UA.m3u'
$ruName='IPTV-RU-Pilot-v1.m3u'
$combinedName='IPTV-UA-RU-Pilot-v1.m3u'
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$stage=Join-Path 'C:\ReservLampac\IPTVPlus\RU-Pilot' $runId
$maxChecks=[math]::Min(160,[math]::Max(20,$MaxChecks))
$minWorking=[math]::Max(1,$MinWorking)
$blockName='(?i)(casino|казино|betting|ставки|букмекер|poker|покер|porn|xxx|adult|18\+|эротик|erotic)'
function Test-PublicUri([string]$value) {
    $uri=$null
    if (-not [Uri]::TryCreate($value,[UriKind]::Absolute,[ref]$uri)) { return $false }
    if ($uri.Scheme -notin @('http','https') -or $uri.UserInfo) { return $false }
    $h=$uri.Host.ToLowerInvariant()
    if (-not $h.Contains('.') -or $h.EndsWith('.local')) { return $false }
    $ip=$null
    if ([Net.IPAddress]::TryParse($h,[ref]$ip)) {
        if ($ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { return $false }
        $a=$ip.GetAddressBytes()
        if ($a[0] -in @(0,10,127) -or $a[0] -ge 224 -or
            ($a[0] -eq 172 -and $a[1] -ge 16 -and $a[1] -le 31) -or
            ($a[0] -eq 192 -and $a[1] -eq 168) -or
            ($a[0] -eq 169 -and $a[1] -eq 254) -or
            ($a[0] -eq 100 -and $a[1] -ge 64 -and $a[1] -le 127)) { return $false }
    }
    return $true
}
if (-not (Test-Path $uaFile -PathType Leaf)) { throw "Missing $uaFile" }
foreach($name in @($ruName,$combinedName)) {
    if (Test-Path (Join-Path $root $name)) { throw "Target already exists: $name" }
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item $uaFile (Join-Path $stage 'IPTV-UA-original-backup.m3u')
$ua=[IO.File]::ReadAllText($uaFile,[Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
if (-not $ua.StartsWith('#EXTM3U')) { throw 'Invalid UA M3U' }
$uaCount=[regex]::Matches($ua,'(?m)^#EXTINF:').Count
if ($uaCount -ne 84) { throw "Expected 84 UA channels, got $uaCount" }
$uaIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($m in [regex]::Matches($ua,'(?im)^#EXTINF:[^\r\n]*tvg-id="([^"]+)"')) {
    [void]$uaIds.Add($m.Groups[1].Value)
}
$candidates=[Collections.Generic.List[object]]::new()
Write-Host '=== DOWNLOAD RU/RUS SOURCES ==='
foreach($source in $sourceUrls.GetEnumerator()) {
    $file=Join-Path $stage ($source.Key+'.m3u')
    & curl.exe -fLsS --connect-timeout 10 --max-time 50 --max-filesize 6000000 -o $file $source.Value
    if ($LASTEXITCODE -ne 0) { throw "Could not fetch $($source.Key)" }
    $header=''
    foreach($lineRaw in [IO.File]::ReadLines($file,[Text.Encoding]::UTF8)) {
        $line=$lineRaw.Trim()
        if ($line.StartsWith('#EXTINF:')) { $header=$line;continue }
        if (-not $header -or -not $line -or $line.StartsWith('#')) { continue }
        $match=[regex]::Match($header,'(?i)tvg-id="([^"]+)"')
        if (-not $match.Success) { $header='';continue }
        $id=$match.Groups[1].Value
        $name=$header.Substring($header.LastIndexOf(',')+1).Trim()
        $allow=($source.Key -eq 'RU') -or (($id -split '@')[0] -match '(?i)\.(ru|by|kz|int)$')
        $hls=$line -match '(?i)(\.m3u8(?:[?#]|$)|/hls(?:[/?]|$)|\.m3u(?:[?#]|$))'
        if ($allow -and $hls -and $name -and
            $header -notmatch $blockName -and
            -not $uaIds.Contains($id) -and
            (Test-PublicUri $line)) {
            $priority=(if ([Uri]$line -and ([Uri]$line).Scheme -eq 'https') { 10 } else { 0 })
            $candidates.Add([pscustomobject]@{
                Id=$id;Name=$name;Url=$line;Source=$source.Key;Priority=$priority
            })
        }
        $header=''
    }
    Write-Host "$($source.Key): parsed"
}
$seenUrls=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$pool=@(
    foreach($item in ($candidates | Sort-Object Priority -Descending)) {
        if ($seenUrls.Add($item.Url)) { $item }
    }
)
$checks=@($pool | Select-Object -First $maxChecks)
Write-Host "HLS candidates selected for checking: $($checks.Count)"
if (-not $checks) { throw 'No public HLS candidates' }
Write-Host '=== CHECK HLS MANIFESTS IN PARALLEL ==='
$results=@(
    $checks | ForEach-Object -Parallel {
        $item=$_
        $handler=[Net.Http.HttpClientHandler]::new()
        $handler.AllowAutoRedirect=$false
        $client=[Net.Http.HttpClient]::new($handler)
        $client.Timeout=[TimeSpan]::FromSeconds(9)
        $client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0')
        try {
            $uri=[Uri]$item.Url
            $response=$client.GetAsync($uri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            try {
                if (-not $response.IsSuccessStatusCode) { throw "HTTP $([int]$response.StatusCode)" }
                $stream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                try {
                    $bytes=[byte[]]::new(16384)
                    $cts=[Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(8))
                    try {
                        $n=$stream.ReadAsync($bytes,0,$bytes.Length,$cts.Token).GetAwaiter().GetResult()
                    } finally { $cts.Dispose() }
                    if ($n -le 20) { throw 'Manifest empty' }
                    $text=[Text.Encoding]::UTF8.GetString($bytes,0,$n)
                    if ($text.TrimStart([char]0xFEFF) -notmatch '^#EXTM3U' -or
                        $text -notmatch '#EXT-X-') { throw 'Not HLS' }
                    [pscustomobject]@{
                        Id=$item.Id;Name=$item.Name;Url=$item.Url
                        Source=$item.Source;Working=$true;Reason='HLS manifest'
                    }
                } finally { $stream.Dispose() }
            } finally { $response.Dispose() }
        } catch {
            [pscustomobject]@{
                Id=$item.Id;Name=$item.Name;Url=$item.Url
                Source=$item.Source;Working=$false;Reason=$_.Exception.Message
            }
        } finally { $client.Dispose();$handler.Dispose() }
    } -ThrottleLimit 10
)
$verified=@($results | Where-Object Working)
$selected=[Collections.Generic.List[object]]::new()
$seenIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($item in $verified) {
    if ($seenIds.Add($item.Id)) { $selected.Add($item) }
}
$report=[ordered]@{
    runId=$runId;stage=$stage
    checked=$results.Count;verifiedStreams=$verified.Count
    uniqueRUChannels=$selected.Count
    status='STAGED_NOT_PUBLISHED'
    results=@($results)
}
$reportPath=Join-Path $stage 'report.json'
[IO.File]::WriteAllText($reportPath,($report | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Host '=== VERIFIED RU CHANNELS ==='
$selected | Select-Object Name,Id,Source | Format-Table -AutoSize
Write-Host "Verified HLS manifests: $($verified.Count); unique channels: $($selected.Count)"
if ($selected.Count -lt $minWorking) {
    Write-Host 'NOT ENOUGH WORKING CHANNELS; NO PUBLICATION'
    Write-Host "Report: $reportPath"
    return
}
$nl=[Environment]::NewLine
$ruLines=[Collections.Generic.List[string]]::new()
$ruLines.Add('#EXTM3U')
foreach($item in ($selected | Sort-Object Name)) {
    $safeName=$item.Name -replace '[\r\n]',' '
    $ruLines.Add('#EXTINF:-1 tvg-id="' + $item.Id + '" group-title="RU Pilot",' + $safeName)
    $ruLines.Add($item.Url)
}
$ruText=($ruLines -join $nl)+$nl
$combined=$ua.TrimEnd()+$nl+(($ruLines | Select-Object -Skip 1) -join $nl)+$nl
$expectedCombined=84+$selected.Count
if ([regex]::Matches($ruText,'(?m)^#EXTINF:').Count -ne $selected.Count -or
    [regex]::Matches($combined,'(?m)^#EXTINF:').Count -ne $expectedCombined) {
    throw 'Final M3U channel count mismatch'
}
$files=[ordered]@{$ruName=$ruText;$combinedName=$combined}
foreach($entry in $files.GetEnumerator()) {
    [IO.File]::WriteAllText((Join-Path $stage $entry.Key),$entry.Value,[Text.UTF8Encoding]::new($false))
}
$created=[Collections.Generic.List[string]]::new()
try {
    foreach($entry in $files.GetEnumerator()) {
        $target=Join-Path $root $entry.Key
        if (Test-Path $target) { throw "Target exists: $target" }
        $tmp=Join-Path $root ('.'+$entry.Key+'.'+$runId+'.tmp')
        Copy-Item (Join-Path $stage $entry.Key) $tmp
        Move-Item $tmp $target -ErrorAction Stop
        $created.Add($target)
    }
} catch {
    foreach($target in $created) {
        Remove-Item $target -Force -ErrorAction SilentlyContinue
    }
    throw
}
Write-Host '=== NEW PLAYLISTS PUBLISHED ==='
Write-Host "RU: https://lampa.v6.army/iptv/playlists/$ruName"
Write-Host "UA+RU: https://lampa.v6.army/iptv/playlists/$combinedName"
Write-Host "Channels: RU=$($selected.Count), combined=$expectedCombined"
Write-Host "Stage and report: $stage"
Write-Host 'IPTV RU PILOT: PUBLISHED'
