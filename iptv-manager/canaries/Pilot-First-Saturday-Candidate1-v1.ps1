#requires -Version 7.0
# Reversible pilot: ONLY channels 206 (First) and 235 (Saturday).
[CmdletBinding()]
param([switch]$Rollback)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$PSNativeCommandUseErrorActionPreference = $false
$pilot = 'C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\IPTV-UA-RU-Relay-v02-257-STAGING-NOT-PUBLISHED.m3u'
$stageDir = 'C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\First-Expansion-20261105-215516-d198e6bb'
$stage = Join-Path $stageDir 'RU-Relay-Candidates-FIRST-STAGING.json'
$cs02 = 'C:\IPTV-Manager\relay\iptv_hls_relay_v02\IPTV-HLS-Relay-v02.cs'
$cs03 = Join-Path $stageDir 'IPTV-HLS-Relay-v03-STAGING.cs'
$root = 'C:\ReservLampac\IPTVPlus\RU-Pilot-Canaries\First-Saturday-Candidate1'
$stateFile = Join-Path $root 'active-state.json'
function HashFile([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash }
function StateWrite($o) { [IO.File]::WriteAllText($stateFile,(ConvertTo-Json -InputObject $o -Depth 6),[Text.UTF8Encoding]::new($false)) }

if ($Rollback) {
    if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { throw 'No previous installation state.' }
    $s = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($s.Status -ne 'ACTIVE') { throw 'The pilot is not active.' }
    if ((HashFile $pilot) -cne $s.AfterHash) { throw 'Pilot changed after installation. Refusing unsafe rollback.' }
    if ((HashFile $s.Backup) -cne $s.BeforeHash) { throw 'Backup checksum mismatch.' }
    $id=[guid]::NewGuid().ToString('N').Substring(0,8)
    $tmp=Join-Path (Split-Path $pilot -Parent) "IPTV-Rollback-$id.tmp"
    $rb=Join-Path $root "IPTV-Replaced-During-Rollback-$id.bak"
    try {
        Copy-Item -LiteralPath $s.Backup -Destination $tmp -ErrorAction Stop
        [IO.File]::Replace($tmp,$pilot,$rb)
        if ((HashFile $pilot) -cne $s.BeforeHash) { throw 'Rollback verification FAILED.' }
        $s.Status='ROLLED_BACK'
        StateWrite $s
        Write-Host '=== PILOT ROLLBACK VERIFIED ==='
        Write-Host 'First and Saturday restored; all other channels unchanged.'
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    return
}

foreach ($f in @($pilot,$stage,$cs02,$cs03)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "Missing required file: $f" }
}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'curl.exe not found' }
if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
    $oldState=Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($oldState.Status -eq 'ACTIVE') { throw 'Canary is already active.' }
}
foreach ($cs in @($cs02,$cs03)) {
    if (-not [IO.File]::ReadAllText($cs).Contains('context.Request.QueryString["candidate"]')) {
        throw 'Existing Relay source selector differs from verified code.'
    }
}
foreach ($port in @(9144,9145)) {
    if (@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue).Count -eq 0) {
        throw "Required Relay port $port is not listening."
    }
}
$conf=Get-Content -LiteralPath $stage -Raw -Encoding UTF8 | ConvertFrom-Json
if ($conf.Mode -ne 'STAGING_ONLY' -or @($conf.Candidates).Count -ne 65) { throw 'Unexpected staging inputs.' }
$targets=@(
    [pscustomobject]@{I=206;R=82;N='Первый';Port=9145},
    [pscustomobject]@{I=235;R=111;N='Суббота';Port=9144}
)
foreach ($t in $targets) {
    $choices=@($conf.Candidates | Where-Object { [int]$_.Index -eq $t.R })
    if ($choices.Count -lt 2 -or [string]$choices[1].Route -ne 'DIRECT_W2022') {
        throw "Candidate #1 is missing or not direct at playlist channel $($t.I)."
    }
}
$original=[IO.File]::ReadAllText($pilot,[Text.Encoding]::UTF8)
$parts=[regex]::Split($original,'(?<=\n)')
$counter=0
$updated=@{}
for ($i=0; $i -lt $parts.Count; $i++) {
    $line=$parts[$i].Trim()
    if ($line.StartsWith('#EXTINF:')) {
        $counter++
        if ($counter -in @(206,235)) {
            $t=@($targets | Where-Object I -eq $counter)[0]
            if ($line.Substring($line.LastIndexOf(',')+1).Trim() -cne $t.N) {
                throw "Unexpected channel name at position $counter."
            }
        }
        continue
    }
    if ($counter -notin @(206,235) -or $line -notmatch '^https?://') { continue }
    if ($updated.ContainsKey($counter)) { throw "Duplicate channel URL $counter." }
    $t=@($targets | Where-Object I -eq $counter)[0]
    $uri=$null
    if (-not [Uri]::TryCreate($line,[UriKind]::Absolute,[ref]$uri) -or
        $uri.Scheme -ne 'https' -or $uri.DnsSafeHost -cne 'lampa.v6.army' -or
        $uri.AbsolutePath -notmatch "^/iptv-relay/p/[0-9a-f]{64}/channel/$($t.R)\.m3u8$" -or
        $uri.Query -match '(?i)(?:[?&])candidate=') {
        throw "Unexpected protected Relay URL at position $counter."
    }
    $newUrl=$line+$(if($line.Contains('?')){'&candidate=1'}else{'?candidate=1'})
    $nl=if($parts[$i].EndsWith(([string][char]13+[string][char]10))){[string][char]13+[string][char]10}
        elseif($parts[$i].EndsWith([string][char]10)){[string][char]10}else{''}
    $parts[$i]=$newUrl+$nl
    $updated[$counter]=$newUrl
}
if ($counter -ne 257 -or $updated.Count -ne 2) { throw 'Expected 257 entries and exactly two modifications.' }
$replacement=$parts -join ''
if ([regex]::Matches($replacement,'(?m)^#EXTINF:').Count -ne 257) { throw 'Playlist count verification failed.' }

function FetchM3u([string]$url) {
    $out=Join-Path $env:TEMP ('HLS-Check-'+[guid]::NewGuid().ToString('N')+'.m3u8')
    try {
        $status=@(& curl.exe --silent --noproxy '*' --resolve 'lampa.v6.army:443:127.0.0.1' --max-time 25 --max-filesize 262144 --output $out --write-out '%{http_code}' $url)
        if ($LASTEXITCODE -ne 0 -or [string]$status[-1] -ne '200' -or -not (Test-Path -LiteralPath $out)) { throw 'Alternative HTTPS manifest request FAILED.' }
        $body=[IO.File]::ReadAllText($out)
        if (-not $body.TrimStart([char]0xFEFF).StartsWith('#EXTM3U')) { throw 'Response is not HLS.' }
        return $body
    } finally { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
}
function CheckVideo([string]$url) {
    $body=FetchM3u $url
    $base=$url
    if ($body.Contains('#EXT-X-STREAM-INF')) {
        $next=$false;$v=''
        foreach($line in ($body -split '\r?\n')) {
            $line=$line.Trim()
            if ($line.StartsWith('#EXT-X-STREAM-INF')){$next=$true;continue}
            if ($next -and $line -and -not $line.StartsWith('#')){$v=$line;break}
        }
        if (-not $v) { throw 'Master HLS variant missing.' }
        $base=([Uri]::new([Uri]$url,$v)).AbsoluteUri
        if (([Uri]$base).DnsSafeHost -cne 'lampa.v6.army') { throw 'Unexpected variant origin.' }
        $body=FetchM3u $base
    }
    $next=$false;$seg=''
    foreach($line in ($body -split '\r?\n')) {
        $line=$line.Trim()
        if ($line.StartsWith('#EXTINF:')){$next=$true;continue}
        if ($next -and $line -and -not $line.StartsWith('#')){$seg=$line;break}
    }
    if (-not $seg) { throw 'Media segment missing.' }
    $segUri=[Uri]::new([Uri]$base,$seg)
    if ($segUri.Scheme -ne 'https' -or $segUri.DnsSafeHost -cne 'lampa.v6.army' -or
        $segUri.AbsolutePath -notmatch '^/iptv-relay/p/[0-9a-f]{64}/r/[0-9a-f-]{36}$') { throw 'Unexpected segment origin.' }
    $out=Join-Path $env:TEMP ('TS-Check-'+[guid]::NewGuid().ToString('N')+'.bin')
    try {
        $status=@(& curl.exe --silent --noproxy '*' --resolve 'lampa.v6.army:443:127.0.0.1' --max-time 20 --max-filesize 8192 --range '0-1503' --output $out --write-out '%{http_code}' $segUri.AbsoluteUri)
        if ($LASTEXITCODE -ne 0 -or [string]$status[-1] -notin @('200','206') -or -not (Test-Path -LiteralPath $out)) { throw 'Segment HTTPS probe FAILED.' }
        $bytes=[IO.File]::ReadAllBytes($out)
        if ($bytes.Length -lt 564) { throw 'Segment prefix too short.' }
        $ok=$false
        for($i=0;$i -le [Math]::Min(187,$bytes.Length-377);$i++){
            if($bytes[$i] -eq 71 -and $bytes[$i+188] -eq 71 -and $bytes[$i+376] -eq 71){$ok=$true;break}
        }
        if(-not $ok){throw 'No MPEG-TS sync in alternative segment.'}
    } finally { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
}

Write-Host '=== IPTV+ TWO-CHANNEL SAFE PILOT ==='
foreach ($t in $targets) {
    CheckVideo $updated[$t.I]
    Write-Host ("{0}: candidate #1 HLS+TS PASS via existing Relay {1}" -f $t.N,$t.Port)
}
New-Item -ItemType Directory -Path $root -Force | Out-Null
$id=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$backup=Join-Path $root "Pilot-before-$id.bak"
$temp=Join-Path (Split-Path $pilot -Parent) "Pilot-candidate-$id.tmp"
$replacedBak=Join-Path $root "Pilot-replaced-$id.bak"
$failedTemp=Join-Path (Split-Path $pilot -Parent) "Pilot-failure-restore-$id.tmp"
$failedBak=Join-Path $root "Pilot-failure-replaced-$id.bak"
$raw=[IO.File]::ReadAllBytes($pilot)
$bom=$raw.Length -ge 3 -and $raw[0] -eq 239 -and $raw[1] -eq 187 -and $raw[2] -eq 191
$oldHash=HashFile $pilot
Copy-Item -LiteralPath $pilot -Destination $backup -ErrorAction Stop
if ((HashFile $backup) -cne $oldHash -or [IO.File]::ReadAllText($pilot,[Text.Encoding]::UTF8) -cne $original) { throw 'Backup or concurrent-change verification failed.' }
[IO.File]::WriteAllText($temp,$replacement,[Text.UTF8Encoding]::new([bool]$bom))
$didReplace=$false
try {
    [IO.File]::Replace($temp,$pilot,$replacedBak)
    $didReplace=$true
    if ([IO.File]::ReadAllText($pilot,[Text.Encoding]::UTF8) -cne $replacement) { throw 'Published pilot verification failed.' }
    StateWrite ([pscustomobject]@{Status='ACTIVE';BeforeHash=$oldHash;AfterHash=(HashFile $pilot);Backup=$backup;Created=(Get-Date).ToString('o')})
    Write-Host '=== TWO-CHANNEL CANARY INSTALLED ==='
    Write-Host '206 Первый -> candidate #1 via 9145'
    Write-Host '235 Суббота -> candidate #1 via 9144'
    Write-Host 'Other 255 channels unchanged.'
    Write-Host "Backup: $backup"
    Write-Host 'NEXT: check only Первый (correct language/content) and Суббота on Samsung IPTV+.'
    Write-Host '3PROXY / CADDY / RELAYS / PRODUCTION LISTS: UNCHANGED'
} catch {
    if ($didReplace) {
        Copy-Item -LiteralPath $backup -Destination $failedTemp -ErrorAction Stop
        [IO.File]::Replace($failedTemp,$pilot,$failedBak)
        if ((HashFile $pilot) -cne $oldHash) { throw 'Automatic rollback FAILED; examine backup.' }
        Write-Host 'AUTOMATIC ROLLBACK VERIFIED.'
    }
    throw
} finally {
    Remove-Item -LiteralPath $temp,$failedTemp -Force -ErrorAction SilentlyContinue
}
