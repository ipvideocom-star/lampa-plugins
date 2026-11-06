#requires -Version 7.0
<#
Read-only next-step check for the current 85-channel RU IPTV pilot.
Uses existing diagnostic CSV files and two neutral HTTP/HTTPS requests
through the installed 3proxy. Does not print credentials, proxy URLs,
IPTV upstream URLs or relay tokens. Does not alter any configuration.
#>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$PSNativeCommandUseErrorActionPreference = $false

$dir = 'C:\ReservLampac\IPTVPlus\RU-Network-Diagnostics'
$routesFile = Join-Path $dir 'RU-Route-Map-85-20261106-022031.csv'
$timingFile = Join-Path $dir 'RU-Path-Timings-20261106-022031.csv'
$starter = 'C:\IPTV-Manager\relay\iptv_hls_relay_v02\Start-IPTV-HLS-Relay-v02.ps1'

foreach ($f in @($routesFile,$timingFile,$starter)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "Missing input: $f" }
}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'curl.exe missing' }

$routes = @(Import-Csv -LiteralPath $routesFile -Encoding UTF8)
$timings = @(Import-Csv -LiteralPath $timingFile -Encoding UTF8)
if ($routes.Count -ne 85 -or $timings.Count -ne 56) {
    throw 'Previous CSV file sizes are unexpected; no network requests made'
}
$startSource = Get-Content -LiteralPath $starter -Raw -Encoding UTF8
$match = [regex]::Match($startSource, '(?m)\[string\]\$ProxyUrl\s*=\s*''(?<value>https?://[^'']+)''')
if (-not $match.Success) { throw 'Existing 3proxy settings not found; no network requests made' }
$proxyAddress = $match.Groups['value'].Value

function CheckNeutral {
    param([string]$Url,[string]$Mode)
    $params = @('--silent','--globoff','--max-redirs','0','--connect-timeout','3','--max-time','8',
                '--output','NUL','--write-out','STATUS|%{http_code}|%{time_starttransfer}')
    if ($Mode -eq 'PROXY') { $params += @('--proxy',$proxyAddress) }
    else { $params += @('--noproxy','*') }
    $params += $Url
    $lines = @(& curl.exe @params 2>$null)
    $code = $LASTEXITCODE
    $metric = @($lines | Where-Object { [string]$_ -match '^STATUS\|\d{3}\|' } | Select-Object -Last 1)
    if ($metric.Count -eq 0) { return "HTTP=000 EXIT=$code TTFB=n/a" }
    $parts = ([string]$metric[0]) -split '\|'
    return "HTTP=$($parts[1]) EXIT=$code TTFB=$($parts[2])s"
}

Write-Host '=== RU IPTV: EXISTING ROUTES + 3PROXY CONTROL ==='
Write-Host 'All requests are read-only; credentials and stream URLs are hidden.'
Write-Host ''
foreach ($target in @(
    @{Kind='HTTPS';Url='https://example.com/'},
    @{Kind='HTTP';Url='http://example.com/'}
)) {
    foreach ($mode in @('DIRECT','PROXY')) {
        $result = CheckNeutral -Url $target.Url -Mode $mode
        Write-Host ("Neutral {0,-5} {1,-6} {2}" -f $target.Kind,$mode,$result)
    }
}

$relay = @($routes | Where-Object { $_.ClientURLType -eq 'RELAY' }).Count
$direct = @($routes | Where-Object { $_.ClientURLType -eq 'CLIENT_DIRECT' }).Count
Write-Host ''
Write-Host "Actual pilot: via Relay=$relay, directly to Samsung=$direct"
Write-Host 'Targeted channels (actual playlist route vs stage-only source test):'
foreach ($id in @(180,184,189,190,196,200,205,206,214,218,222,225,226,227,235,239,243)) {
    $row = @($routes | Where-Object { [int]$_.PlaylistIndex -eq $id })
    if ($row.Count -ne 1) { throw "Unexpected mapping for playlist index $id" }
    $good = @($timings | Where-Object {
        [int]$_.PlaylistIndex -eq $id -and $_.TestedRoute -eq 'DIRECT_W2022' -and
        $_.ManifestHTTP -eq '200' -and $_.SegmentStatus -in @('OK','PARTIAL')
    }).Count
    Write-Host ('{0:000} {1,-18} CLIENT={2,-14} STAGE_GOOD={3}' -f $id,$row[0].Channel,$row[0].ClientURLType,$good)
}
Write-Host ''
Write-Host 'NOTE: STAGE_GOOD is not proof of speed or content on Samsung.'
Write-Host 'NOTE: HTTP 403 may come from 3proxy permissions OR the upstream service.'
Write-Host 'CADDY / PLAYLIST / RELAYS / 3PROXY: UNCHANGED'
