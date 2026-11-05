#requires -Version 7.0
# IPTV Manager: stage First Channel Relay extension. LIVE SYSTEM IS UNCHANGED.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$cs='C:\IPTV-Manager\relay\iptv_hls_relay_v02\IPTV-HLS-Relay-v02.cs'
$original='C:\ReservLampac\IPTVPlus\HLS-Relay-Staging\RU-Relay-Candidates-20261105-084928.json'
$discovery='C:\ReservLampac\IPTVPlus\Discovery\source-discovery-20261103-174853-693718c1.json'
$audit='C:\ReservLampac\IPTVPlus\FirstChannel\First-Alternatives-Audit-20261105-213458.csv'
$ru='C:\IPTV-Manager\public\playlists\IPTV-RU-Pilot-v1.m3u'
$stageRoot='C:\ReservLampac\IPTVPlus\HLS-Relay-Staging'
foreach($file in @($cs,$original,$discovery,$audit,$ru)){
    if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw "Required input is missing: $file"}
}
function Hash16([string]$value){
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($value))).Substring(0,16)
}
function ReplaceOnce([string]$source,[string]$old,[string]$new,[string]$label){
    $count=[regex]::Matches($source,[regex]::Escape($old)).Count
    if($count -ne 1){throw "Unexpected Relay C# source at $label (matches: $count)"}
    return $source.Replace($old,$new)
}
# Only eight candidates already checked through nested HLS and a TS segment.
$approved=[ordered]@{
 '4926FB0AB51C4B1D'=82
 '3E574EFF86739049'=82
 '8DE1DB3CA0B7115B'=82
 'ABF3003403095493'=82
 'B02E062059E3C841'=82
 '3D42F398864964F5'=82
 'F8DD03445E8B7EB6'=82
 'C19585A1A1ED12C7'=84
}
$hosts=@('amtv.tulixcdn.com','cb163385.amazzin.pw','stream8.cinerama.uz')
$names=@{82='Первый';83='Первый -1';84='Первый +2'}
$found=@{}
$pos=0
foreach($line in (Get-Content -LiteralPath $ru -Encoding utf8)){
 if(-not $line.StartsWith('#EXTINF:')){continue}
 $pos++
 if($pos -in @(82,83,84)){$found[$pos]=$line.Substring($line.LastIndexOf(',')+1).Trim()}
}
if($pos -ne 133){throw "Expected 133 RU channels; got $pos"}
foreach($index in $names.Keys){
 if($found[$index] -cne $names[$index]){throw "RU channel index $index changed"}
}
$ruHash=(Get-FileHash -LiteralPath $ru -Algorithm SHA256).Hash
$base=Get-Content -LiteralPath $original -Raw -Encoding utf8|ConvertFrom-Json
if($base.Mode -cne 'STAGING_ONLY' -or $base.AutoPublish -ne $false -or $base.ContentVerified -ne $false -or @($base.Candidates).Count -ne 57 -or $base.RUPlaylistSHA256 -cne $ruHash){
 throw 'Existing private Relay staging baseline is different'
}
if(@($base.Candidates|Select-Object -ExpandProperty Index -Unique).Count -ne 28 -or @($base.Candidates|Where-Object{$_.Index -in @(82,84)}).Count -ne 0){
 throw 'Relay original channel indexes differ from expected'
}
$csv=@(Import-Csv -LiteralPath $audit -Encoding utf8)
$catalog=Get-Content -LiteralPath $discovery -Raw -Encoding utf8|ConvertFrom-Json
if($csv.Count -ne 26 -or @($catalog.Records).Count -ne 1949){throw 'Unexpected discovery or audit baseline'}
$append=[Collections.Generic.List[object]]::new()
foreach($key in $approved.Keys){
 $id=[int]$approved[$key]
 $one=@($csv|Where-Object URLKey -CEQ $key)
 $entries=@($catalog.Records|Where-Object URLKey -CEQ $key)
 $variant=if($id -eq 82){'Первый'}else{'Первый +2'}
 if($one.Count -ne 1 -or $entries.Count -ne 1 -or $one[0].Available -cne 'True' -or $one[0].Status -cne 'TS_SEGMENT_CONFIRMED' -or $one[0].Variant -cne $variant){
  throw "Missing confirmed candidate $key"
 }
 $entry=$entries[0]
 if((Hash16 ([string]$entry.URL)) -cne $key){throw "URL fingerprint mismatch $key"}
 $uri=$null
 if(-not [Uri]::TryCreate([string]$entry.URL,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or $uri.UserInfo -or $uri.DnsSafeHost -notin $hosts -or [string]$entry.Channel -notlike 'Первый*'){
  throw "Unexpected candidate host or name $key"
 }
 $append.Add([pscustomobject][ordered]@{Index=$id;Channel=$names[$id];URL=[string]$entry.URL;URLKey=$key;Route='DIRECT_W2022'})
}
if($append.Count -ne 8 -or @($append|Where-Object Index -eq 82).Count -ne 7 -or @($append|Where-Object Index -eq 84).Count -ne 1){throw 'Candidate distribution mismatch'}
$staged=$base.PSObject.Copy()
$staged.Candidates=@($base.Candidates)+@($append.ToArray())
$staged|Add-Member -MemberType NoteProperty -Name ExpectedChannels -Value 30 -Force
$staged|Add-Member -MemberType NoteProperty -Name ExpectedCandidates -Value 65 -Force
$staged|Add-Member -MemberType NoteProperty -Name FirstChannelPilot -Value 'NOT_PUBLISHED' -Force
$json=ConvertTo-Json -InputObject $staged -Depth 40
$check=$json|ConvertFrom-Json
if(@($check.Candidates).Count -ne 65 -or @($check.Candidates|Select-Object -ExpandProperty Index -Unique).Count -ne 30){throw 'Staged JSON round-trip mismatch'}
foreach($item in $base.Candidates){
 $matching=@($check.Candidates|Where-Object{$_.Index -eq $item.Index -and $_.URLKey -ceq $item.URLKey -and $_.URL -ceq $item.URL -and $_.Route -ceq $item.Route})
 if($matching.Count -ne 1){throw 'Existing candidate not preserved'}
}
# Create NEW source only. Original .cs is not edited or replaced.
$src=[IO.File]::ReadAllText($cs,[Text.Encoding]::UTF8)
$nl=[Environment]::NewLine
$src=ReplaceOnce $src 'namespace IPTVRelayPilot02' 'namespace IPTVRelayPilot03' 'namespace'
$src=ReplaceOnce $src 'using (JsonDocument doc = JsonDocument.Parse(File.ReadAllText(jsonPath, Encoding.UTF8)))' ('int expectedChannels = 0; int expectedCandidates = 0;'+$nl+'            using (JsonDocument doc = JsonDocument.Parse(File.ReadAllText(jsonPath, Encoding.UTF8)))') 'expected declarations'
$src=ReplaceOnce $src 'JsonElement root = doc.RootElement;' ('JsonElement root = doc.RootElement;'+$nl+'                expectedChannels = root.GetProperty("ExpectedChannels").GetInt32();'+$nl+'                expectedCandidates = root.GetProperty("ExpectedCandidates").GetInt32();'+$nl+'                if (expectedChannels < 1 || expectedChannels > 133 || expectedCandidates < expectedChannels || expectedCandidates > 1024)'+$nl+'                    throw new InvalidOperationException("Invalid expected candidate counts");') 'private JSON count fields'
$src=ReplaceOnce $src 'if (channels.Count != 28 || channels.Sum(kv => kv.Value.Count) != 57)' 'if (channels.Count != expectedChannels || channels.Sum(kv => kv.Value.Count) != expectedCandidates)' 'dynamic count check'
$src=ReplaceOnce $src 'throw new InvalidOperationException("Expected exactly 28 channels and 57 candidates");' 'throw new InvalidOperationException("Candidate count differs from private JSON manifest");' 'dynamic count error'
$src=ReplaceOnce $src '\"candidates\":57' '\"candidates\":" + channels.Sum(kv => kv.Value.Count) + "' 'health count'
$src=ReplaceOnce $src 'private readonly string prefix = "http://127.0.0.1:9144/";' 'private readonly string prefix = "http://127.0.0.1:9145/";' 'temporary local-only port'
$src=ReplaceOnce $src 'IPTV HLS RELAY PILOT v0.2 listening' 'IPTV HLS RELAY PILOT v0.3 STAGING listening' 'version label'
$src=ReplaceOnce $src '28 staged channels, secret-path access, local-only, no Caddy, no playlist publication' 'Staged channels, secret-path access, local-only; no Caddy or playlist publication' 'count label'
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$folder=Join-Path $stageRoot ('First-Expansion-'+$stamp)
New-Item -ItemType Directory -Path $folder -Force|Out-Null
$newCs=Join-Path $folder 'IPTV-HLS-Relay-v03-STAGING.cs'
$newJson=Join-Path $folder 'RU-Relay-Candidates-FIRST-STAGING.json'
[IO.File]::WriteAllText($newCs,$src,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($newJson,$json,[Text.UTF8Encoding]::new($false))
Add-Type -Path $newCs -ErrorAction Stop
if((Get-FileHash -LiteralPath $ru -Algorithm SHA256).Hash -cne $ruHash){throw 'RU live playlist changed during staging'}
Write-Host '=== FIRST CHANNEL RELAY EXPANSION STAGED ==='
Write-Host 'COMPILE-ONLY: PASS'
Write-Host 'Original: 28 channels / 57 candidates'
Write-Host 'Staged:   30 channels / 65 candidates'
Write-Host 'Index 82: First live, 7 confirmed TS candidates'
Write-Host 'Index 84: First +2, 1 confirmed TS candidate'
Write-Host 'Index 83: First -1 unchanged'
Write-Host "STAGE_DIRECTORY: $folder"
Write-Host "CS_SHA256: $((Get-FileHash $newCs -Algorithm SHA256).Hash)"
Write-Host "JSON_SHA256: $((Get-FileHash $newJson -Algorithm SHA256).Hash)"
Write-Host 'LIVE 9144 / PUBLISHED PLAYLISTS / CADDY / PLUGIN MANAGER: UNCHANGED'
Write-Host 'FIRST LIVE PLAYBACK: NOT YET VERIFIED'
