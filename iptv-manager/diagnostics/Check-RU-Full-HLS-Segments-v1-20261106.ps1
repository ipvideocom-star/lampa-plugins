#requires -Version 7.0
# Read-only full HLS segment delivery diagnostic: Первый and Суббота.
# Tests the current candidate #0 directly and through the same active Relay.
# Video is discarded to NUL; no video file is stored.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$PSNativeCommandUseErrorActionPreference = $false

$pilot = 'C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\IPTV-UA-RU-Relay-v02-257-STAGING-NOT-PUBLISHED.m3u'
$stage = 'C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\First-Expansion-20261105-215516-d198e6bb\RU-Relay-Candidates-FIRST-STAGING.json'
$outdir = 'C:\ReservLampac\IPTVPlus\RU-Network-Diagnostics'
foreach ($file in @($pilot,$stage)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Input missing: $file" }
}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'curl.exe is unavailable' }

$entries = [Collections.Generic.List[object]]::new()
$name = $null
foreach ($raw in [IO.File]::ReadAllLines($pilot,[Text.Encoding]::UTF8)) {
    $line = $raw.Trim()
    if ($line.StartsWith('#EXTINF:')) {
        $name = $line.Substring($line.LastIndexOf(',')+1).Trim()
        continue
    }
    if ($null -ne $name -and $line -match '^https?://') {
        $entries.Add([pscustomobject]@{Id=$entries.Count+1;Name=$name;Url=$line})
        $name = $null
    }
}
if ($entries.Count -ne 257) { throw 'Expected 257 entries in pilot playlist' }

$config = Get-Content -LiteralPath $stage -Encoding UTF8 -Raw | ConvertFrom-Json
if ($config.Mode -ne 'STAGING_ONLY' -or @($config.Candidates).Count -ne 65) {
    throw 'Unexpected source-candidate configuration'
}
$targets = @(
    [pscustomobject]@{Id=206;Index=82;Name='Первый';Relay=9145},
    [pscustomobject]@{Id=235;Index=111;Name='Суббота';Relay=9144}
)
$tests = [Collections.Generic.List[object]]::new()
foreach ($t in $targets) {
    $entry = $entries[$t.Id - 1]
    if ($entry.Name -cne $t.Name) { throw "Channel position $($t.Id) differs" }
    $uri = $null
    if (-not [Uri]::TryCreate($entry.Url,[UriKind]::Absolute,[ref]$uri) -or
        $uri.Scheme -ne 'https' -or $uri.DnsSafeHost -cne 'lampa.v6.army' -or
        $uri.AbsolutePath -notmatch ("^/iptv-relay/p/[0-9a-f]{64}/channel/" + $t.Index + "[.]m3u8$") -or
        $uri.Query) {
        throw "Current Relay playlist URL differs for channel $($t.Id)"
    }
    if (@(Get-NetTCPConnection -LocalPort $t.Relay -State Listen -ErrorAction SilentlyContinue).Count -eq 0) {
        throw "Required active Relay port $($t.Relay) is not listening"
    }
    $choices = @($config.Candidates | Where-Object { [int]$_.Index -eq $t.Index })
    if ($choices.Count -lt 1 -or $choices[0].Route -ne 'DIRECT_W2022') {
        throw "Current candidate 0 differs for channel $($t.Id)"
    }
    $tests.Add([pscustomobject]@{Id=$t.Id;Name=$t.Name;Route='UPSTREAM';Url=[string]$choices[0].URL})
    $tests.Add([pscustomobject]@{Id=$t.Id;Name=$t.Name;Route='RELAY';Url=$entry.Url})
}
New-Item -ItemType Directory -Path $outdir -Force | Out-Null
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$csv = Join-Path $outdir "RU-FullSegments-$stamp.csv"
$summary = Join-Path $outdir "RU-FullSegments-Summary-$stamp.txt"
$rows = [Collections.Generic.List[object]]::new()

function FetchHls {
    param([string]$Url,[string]$Route)
    # A bounded temporary text manifest, never a media segment.
    $temp = Join-Path $env:TEMP ('IPTV-Manifest-'+[guid]::NewGuid().ToString('N')+'.tmp')
    $args = @('--silent','--globoff','--location','--max-redirs','3',
        '--connect-timeout','4','--max-time','14','--max-filesize','262144',
        '--noproxy','*','--output',$temp,
        '--write-out','METRIC|%{http_code}|%{time_starttransfer}|%{time_total}|%{url_effective}')
    if ($Route -eq 'RELAY') { $args += @('--resolve','lampa.v6.army:443:127.0.0.1') }
    $args += $Url
    try {
        $lines = @(& curl.exe @args 2>$null)
        $exit = $LASTEXITCODE
        $match = @($lines | Where-Object { [string]$_ -like 'METRIC|*' } | Select-Object -Last 1)
        if ($match.Count -eq 0) {
            return [pscustomobject]@{Ok=$false;Code='000';Exit=$exit;Text='';Effective=$Url;Ttfb=0;Total=0}
        }
        $fields = ([string]$match[0]) -split '\|',5
        if ($fields.Count -ne 5) { throw 'Unexpected curl manifest measurement' }
        $ci = [Globalization.CultureInfo]::InvariantCulture
        $ttfb = [double]::Parse($fields[2],$ci)
        $total = [double]::Parse($fields[3],$ci)
        $body = ''
        $ok = $fields[1] -eq '200' -and $exit -eq 0 -and (Test-Path -LiteralPath $temp)
        if ($ok) {
            $body = [IO.File]::ReadAllText($temp)
            if (-not $body.TrimStart([char]0xFEFF).StartsWith('#EXTM3U')) { $ok=$false }
        }
        return [pscustomobject]@{Ok=$ok;Code=$fields[1];Exit=$exit;Text=$body;Effective=$fields[4];Ttfb=$ttfb;Total=$total}
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

function Get-MediaSegment {
    param([string]$Url,[string]$Route)
    $current = $Url
    $codecs = 'NOT_DECLARED'
    $resolution = 'NOT_DECLARED'
    for ($depth=0; $depth -lt 3; $depth++) {
        $m = FetchHls -Url $current -Route $Route
        if (-not $m.Ok) { return [pscustomobject]@{Ok=$false;Error='MANIFEST';M=$m;Segment='';Codecs=$codecs;Resolution=$resolution;Sequence='N/A';Encrypted=$false} }
        $lines = @($m.Text -split '\r?\n')
        $variants = [Collections.Generic.List[string]]::new()
        $segments = [Collections.Generic.List[string]]::new()
        $seq = 'N/A'
        $encrypted = $false
        for ($i=0; $i -lt $lines.Count; $i++) {
            $l=$lines[$i].Trim()
            if ($l -match '^#EXT-X-MEDIA-SEQUENCE:(\d+)') { $seq=$Matches[1] }
            if ($l -match '^#EXT-X-KEY:METHOD=(?!NONE)') { $encrypted=$true }
            if ($l.StartsWith('#EXT-X-STREAM-INF:') -and $i+1 -lt $lines.Count) {
                $attr=$l
                if ($attr -match 'CODECS="([^"]+)"') { $codecs=$Matches[1] }
                if ($attr -match 'RESOLUTION=(\d+x\d+)') { $resolution=$Matches[1] }
                $candidate=$lines[$i+1].Trim()
                if ($candidate -and -not $candidate.StartsWith('#')) { $variants.Add($candidate) }
            }
            if ($l.StartsWith('#EXTINF:') -and $i+1 -lt $lines.Count) {
                $candidate=$lines[$i+1].Trim()
                if ($candidate -and -not $candidate.StartsWith('#')) { $segments.Add($candidate) }
            }
        }
        if ($segments.Count -gt 0) {
            # Choose the penultimate segment when possible, to avoid racing the live edge.
            $idx = if ($segments.Count -ge 2) { $segments.Count-2 } else { 0 }
            $s = [Uri]::new([Uri]$m.Effective,$segments[$idx])
            if ($s.Scheme -notin @('http','https') -or
                ($Route -eq 'RELAY' -and $s.DnsSafeHost -cne 'lampa.v6.army')) {
                throw 'Unrecognized HLS segment routing'
            }
            return [pscustomobject]@{Ok=$true;Error='';M=$m;Segment=$s.AbsoluteUri;Codecs=$codecs;Resolution=$resolution;Sequence=$seq;Encrypted=$encrypted}
        }
        if ($variants.Count -eq 0) {
            return [pscustomobject]@{Ok=$false;Error='NO_SEGMENTS';M=$m;Segment='';Codecs=$codecs;Resolution=$resolution;Sequence=$seq;Encrypted=$encrypted}
        }
        $next = [Uri]::new([Uri]$m.Effective,$variants[0])
        if ($next.Scheme -notin @('http','https') -or
            ($Route -eq 'RELAY' -and $next.DnsSafeHost -cne 'lampa.v6.army')) {
            throw 'Unrecognized HLS variant routing'
        }
        $current=$next.AbsoluteUri
    }
    return [pscustomobject]@{Ok=$false;Error='TOO_MANY_VARIANTS';M=$null;Segment='';Codecs=$codecs;Resolution=$resolution;Sequence='N/A';Encrypted=$false}
}

function Get-FullSegment {
    param([string]$Url,[string]$Route)
    # FULL segment, with no Range header; discard bytes instead of writing video to disk.
    $args = @('--silent','--globoff','--location','--max-redirs','3',
        '--connect-timeout','4','--max-time','28','--max-filesize','16777216',
        '--noproxy','*','--output','NUL',
        '--write-out','METRIC|%{http_code}|%{time_starttransfer}|%{time_total}|%{size_download}|%{speed_download}')
    if ($Route -eq 'RELAY') { $args += @('--resolve','lampa.v6.army:443:127.0.0.1') }
    $args += $Url
    $output = @(& curl.exe @args 2>$null)
    $exit = $LASTEXITCODE
    $metric = @($output | Where-Object { [string]$_ -like 'METRIC|*' } | Select-Object -Last 1)
    if ($metric.Count -eq 0) { return [pscustomobject]@{Ok=$false;Http='000';Exit=$exit;Ttfb=0;Total=0;Bytes=0;Speed=0} }
    $parts = ([string]$metric[0]) -split '\|'
    if ($parts.Count -ne 6) { throw 'Unexpected segment timing response' }
    $ci = [Globalization.CultureInfo]::InvariantCulture
    $first = [double]::Parse($parts[2],$ci)
    $total = [double]::Parse($parts[3],$ci)
    $bytes = [double]::Parse($parts[4],$ci)
    $speed = [double]::Parse($parts[5],$ci)
    return [pscustomobject]@{
        Ok=($exit -eq 0 -and $parts[1] -eq '200' -and $bytes -gt 0)
        Http=$parts[1];Exit=$exit;Ttfb=$first;Total=$total;Bytes=[int64]$bytes;Speed=$speed
    }
}

Write-Host '=== RU IPTV FULL SEGMENT STABILITY CHECK ==='
Write-Host '2 channels x 2 routes x 5 rounds; full segments to NUL (no video saved).'
Write-Host 'Caddy used over local HTTPS; upstream tested directly from W2022.'
Write-Host 'This does not test the Samsung decoder or LAN connection.'
try {
    for ($round=1; $round -le 5; $round++) {
        foreach ($t in $tests) {
            $m=Get-MediaSegment -Url $t.Url -Route $t.Route
            $s=$null
            if ($m.Ok) { $s=Get-FullSegment -Url $m.Segment -Route $t.Route }
            $success=$m.Ok -and $null -ne $s -and $s.Ok
            $row = [pscustomobject]@{
                ChannelIndex=$t.Id;Channel=$t.Name;Route=$t.Route;Round=$round
                Status=if($success){'OK'}else{'FAILED'}
                ManifestHTTP=if($m.M){$m.M.Code}else{'000'}
                SegmentHTTP=if($s){$s.Http}else{'NOT_TESTED'}
                CurlExit=if($s){$s.Exit}else{-1}
                SegmentBytes=if($s){$s.Bytes}else{0}
                TTFBSeconds=if($s){[Math]::Round($s.Ttfb,3)}else{0}
                FullDownloadSeconds=if($s){[Math]::Round($s.Total,3)}else{0}
                AverageKiBPerSecond=if($s){[Math]::Round($s.Speed/1024,1)}else{0}
                MediaSequence=$m.Sequence;HlsCodecs=$m.Codecs;Resolution=$m.Resolution
                Encrypted=$m.Encrypted;Error=$m.Error
            }
            $rows.Add($row)
            Write-Host ('{0,-8} {1,-8} round {2}: HLS={3} SEG={4} BYTES={5} TIME={6:N2}s SPEED={7:N0} KiB/s' -f
                $t.Name,$t.Route,$round,$row.ManifestHTTP,$row.SegmentHTTP,$row.SegmentBytes,
                $row.FullDownloadSeconds,$row.AverageKiBPerSecond)
        }
        if ($round -lt 5) { Start-Sleep -Seconds 9 }
    }
}
finally {
    $rows | Export-Csv -LiteralPath $csv -Encoding UTF8 -NoTypeInformation
}
$lines=[Collections.Generic.List[string]]::new()
$lines.Add('RU FULL SEGMENT STABILITY - READ ONLY')
$lines.Add('5 rounds / 2 channels / current source #0 / upstream vs Relay')
$lines.Add('No video data retained; full downloads discarded via NUL.')
$lines.Add('W2022 test cannot determine actual broadcast identity or Samsung decoder performance.')
$lines.Add('')
foreach ($g in ($rows | Group-Object Channel,Route)) {
    $set=@($g.Group)
    $ok=@($set | Where-Object Status -eq 'OK')
    $avg=if($ok.Count){[Math]::Round(($ok | Measure-Object -Property FullDownloadSeconds -Average).Average,2)}else{0}
    $minSpeed=if($ok.Count){[Math]::Round(($ok | Measure-Object -Property AverageKiBPerSecond -Minimum).Minimum,0)}else{0}
    $max=if($ok.Count){[Math]::Round(($ok | Measure-Object -Property FullDownloadSeconds -Maximum).Maximum,2)}else{0}
    $codec=@($set|Select-Object -ExpandProperty HlsCodecs -Unique) -join ','
    $resolution=@($set|Select-Object -ExpandProperty Resolution -Unique) -join ','
    $lines.Add(('{0} {1}: complete segments {2}/{3}; mean {4}s; slowest {5}s; minimum speed {6} KiB/s; HLS CODECS {7}; resolution {8}' -f
        $set[0].Channel,$set[0].Route,$ok.Count,$set.Count,$avg,$max,$minSpeed,$codec,$resolution))
}
$lines.Add('')
$lines.Add('No codec claim is possible if HLS CODECS is NOT_DECLARED.')
$lines.Add('Relay vs upstream times may differ due to CDN, caching and segment timing.')
$lines.Add('3PROXY / CADDY / RELAYS / IPTV+ PLAYLISTS: UNCHANGED')
$lines.Add("TIMINGS: $csv")
[IO.File]::WriteAllLines($summary,$lines,[Text.UTF8Encoding]::new($true))
Write-Host ''
Write-Host '=== FULL SEGMENT TEST COMPLETE ==='
$lines | Where-Object { $_ -match '^Первый |^Суббота ' } | ForEach-Object { Write-Host $_ }
Write-Host "SUMMARY: $summary"
Write-Host "TIMINGS: $csv"
Write-Host 'NO CONFIGURATION CHANGES'
