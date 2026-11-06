#requires -Version 5.1
# Read-only W2019S vantage point: independently verify full Saturday HLS segments.
# Public feed URLs only; never modifies 3proxy, firewall, playlists or services.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
Write-Host '=== W2019S DIRECT SATURDAY IPTV: FULL SEGMENT PROBE ==='
Write-Host '3proxy is NOT used or modified. No video is saved.'
if(-not(Get-Command curl.exe -ErrorAction SilentlyContinue)){throw 'curl.exe not installed'}
$root=Join-Path $env:ProgramData 'IPTV-Manager-Diagnostics'
New-Item -ItemType Directory -Path $root -Force|Out-Null
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$folder=Join-Path $root $stamp
New-Item -ItemType Directory -Path $folder -Force|Out-Null
$report=Join-Path $folder 'Saturday-W2019S-Direct.csv'
$summary=Join-Path $folder 'Saturday-W2019S-Summary.txt'
$sha=[Security.Cryptography.SHA256]::Create()
function Fingerprint([string]$s) {
 $bytes=[Text.Encoding]::UTF8.GetBytes($s)
 return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').Substring(0,16)
}
function IsPublicUrl([string]$value) {
 $uri=$null
 if(-not [Uri]::TryCreate($value,[UriKind]::Absolute,[ref]$uri)){return $false}
 if($uri.Scheme -notin @('http','https') -or $uri.UserInfo){return $false}
 if($uri.DnsSafeHost -notmatch '\.'){return $false}
 try {
  $ips=[Net.Dns]::GetHostAddresses($uri.DnsSafeHost)
  if($ips.Count -lt 1){return $false}
  foreach($ip in $ips){
   if([Net.IPAddress]::IsLoopback($ip)){return $false}
   if($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork){
    $b=$ip.GetAddressBytes()
    if($b[0] -in @(0,10,127) -or $b[0] -ge 224 -or
       ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
       ($b[0] -eq 192 -and $b[1] -eq 168) -or
       ($b[0] -eq 169 -and $b[1] -eq 254) -or
       ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127) -or
       ($b[0] -eq 198 -and $b[1] -in @(18,19))){return $false}
   }elseif($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6){
    $b=$ip.GetAddressBytes()
    if($ip.IsIPv6LinkLocal -or $ip.IsIPv6SiteLocal -or $ip.IsIPv6Multicast -or
       ($b[0] -band 254) -eq 252){return $false}
   }else{return $false}
  }
  return $true
 }catch{return $false}
}
function CurlFetch([string]$url,[bool]$media,[string]$agent,[string]$referer) {
 $temporary=Join-Path $folder ([guid]::NewGuid().ToString('N')+'.tmp')
 $args=@('--silent','--globoff','--noproxy','*','--connect-timeout','4',
   '--max-time',$(if($media){'18'}else{'12'}),
   '--max-filesize',$(if($media){'16777216'}else{'3145728'}),
   '--output',$(if($media){'NUL'}else{$temporary}),
   '--write-out','VALUE|%{http_code}|%{time_total}|%{size_download}')
 if($agent -and $agent.Length -lt 240 -and $agent -notmatch '[\r\n]'){$args+=@('--user-agent',$agent)}
 if($referer -and $referer.Length -lt 500 -and $referer -notmatch '[\r\n]'){$args+=@('--referer',$referer)}
 $args+=$url
 try{
  $output=@(& curl.exe @args 2>$null)
  $exitCode=$LASTEXITCODE
  $match=@($output|Where-Object{[string]$_ -like 'VALUE|*'}|Select-Object -Last 1)
  if($match.Count -eq 0){return [pscustomobject]@{Ok=$false;Code='000';Exit=$exitCode;Seconds=0;Bytes=0;Text=''}}
  $parts=([string]$match[0])-split '\|'
  if($parts.Count -ne 4){throw 'Unexpected curl report'}
  $ci=[Globalization.CultureInfo]::InvariantCulture
  $seconds=[double]::Parse($parts[2],$ci)
  $size=[double]::Parse($parts[3],$ci)
  $ok=$exitCode -eq 0 -and $parts[1] -eq '200' -and $size -gt 0
  $content=''
  if(-not $media -and $ok -and (Test-Path -LiteralPath $temporary)){
   $content=[IO.File]::ReadAllText($temporary)
   if(-not $content.TrimStart([char]0xFEFF).StartsWith('#EXTM3U')){$ok=$false;$content=''}
  }
  return [pscustomobject]@{Ok=$ok;Code=$parts[1];Exit=$exitCode;Seconds=$seconds;Bytes=[int64]$size;Text=$content}
 }finally{Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}
}
$feeds=@(
 [pscustomobject]@{Name='NGRCH-RU';Url='https://ngrch.github.io/iptv/ru.m3u'},
 [pscustomobject]@{Name='DENXVO';Url='https://raw.githubusercontent.com/denxvofficial/IPTV/main/iptv.m3u'},
 [pscustomobject]@{Name='IPTVORG-RU';Url='https://iptv-org.github.io/iptv/countries/ru.m3u'},
 [pscustomobject]@{Name='IPTVORG-RUS';Url='https://iptv-org.github.io/iptv/languages/rus.m3u'}
)
$candidates=[Collections.Generic.List[object]]::new()
$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($feed in $feeds){
 $f=CurlFetch $feed.Url $false '' ''
 if(-not $f.Ok){Write-Host ("FEED {0}: HTTP={1} EXIT={2}; skipped" -f $feed.Name,$f.Code,$f.Exit);continue}
 $name='';$agent='';$referer='';$matches=0
 foreach($raw in ($f.Text -split '\r?\n')){
  $line=$raw.Trim()
  if($line.StartsWith('#EXTINF:')){
   $name=$line.Substring($line.LastIndexOf(',')+1).Trim()
   $agent='';$referer=''
   continue
  }
  if($line -match '^#EXTVLCOPT:http-user-agent=(.*)$'){$agent=$Matches[1];continue}
  if($line -match '^#EXTVLCOPT:http-referrer=(.*)$'){$referer=$Matches[1];continue}
  if(-not $name -or $line.StartsWith('#') -or $line -notmatch '^https?://'){continue}
  $normalized=($name.ToLowerInvariant() -replace '\s*(?:hd|fhd|sd|uhd|4k|1080p|720p)\s*$','').Trim()
  if($normalized -match '^\u0441\u0443\u0431\u0431\u043e\u0442\u0430!?$' -and (IsPublicUrl $line)){
   $matches++
   if($seen.Add($line)){
    $uri=[Uri]$line
    $candidates.Add([pscustomobject]@{
     Url=$line;Host=$uri.DnsSafeHost;Key=(Fingerprint $line)
     Feed=$feed.Name;Agent=$agent;Referer=$referer
    })
   }
  }
  $name=''
 }
 Write-Host ("FEED {0}: HTTP=200 matching entries={1}" -f $feed.Name,$matches)
}
$chosen=[Collections.Generic.List[object]]::new()
$hostCounts=@{}
# Select up to 8 distinct URLs, at most 2 per origin host.
foreach($c in $candidates){
 if($chosen.Count -ge 8){break}
 $key=$c.Host.ToLowerInvariant()
 $n=if($hostCounts.ContainsKey($key)){$hostCounts[$key]}else{0}
 if($n -ge 2){continue}
 $hostCounts[$key]=$n+1
 $chosen.Add($c)
}
Write-Host ("Unique public Saturday URLs={0}; testing={1}" -f $candidates.Count,$chosen.Count)
$results=[Collections.Generic.List[object]]::new()
foreach($c in $chosen){
 $current=$c.Url
 $response=$null
 $errorText=''
 $segmentList=[Collections.Generic.List[object]]::new()
 for($level=0;$level -lt 3;$level++){
  if(-not(IsPublicUrl $current)){$errorText='URL_NOT_PUBLIC';break}
  $response=CurlFetch $current $false $c.Agent $c.Referer
  if(-not $response.Ok){$errorText=('HLS_HTTP_'+$response.Code+'_EXIT_'+$response.Exit);break}
  $variant=''
  $lines=@($response.Text -split '\r?\n')
  for($i=0;$i -lt $lines.Count;$i++){
   $line=$lines[$i].Trim()
   if($line.StartsWith('#EXT-X-KEY:') -and $line -notmatch 'METHOD=NONE'){$errorText='ENCRYPTED';break}
   if($line.StartsWith('#EXT-X-BYTERANGE:')){$errorText='BYTERANGE_NOT_SUPPORTED';break}
   if($line.StartsWith('#EXT-X-STREAM-INF:') -and $i+1 -lt $lines.Count -and -not $variant){
    $v=$lines[$i+1].Trim()
    if($v -and -not $v.StartsWith('#')){$variant=$v}
   }
   if($line.StartsWith('#EXTINF:') -and $i+1 -lt $lines.Count){
    $next=$lines[$i+1].Trim()
    if($next -and -not $next.StartsWith('#')){
     $secs=0.0
     $rawDuration=($line.Substring(8)-split ',')[0]
     [void][double]::TryParse($rawDuration,
       [Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$secs)
     $segmentUrl=([Uri]::new([Uri]$current,$next)).AbsoluteUri
     if(IsPublicUrl $segmentUrl){$segmentList.Add([pscustomobject]@{Url=$segmentUrl;Duration=$secs})}
    }
   }
  }
  if($errorText){break}
  if($segmentList.Count -ge 2){break}
  if(-not $variant){$errorText='TOO_FEW_SEGMENTS';break}
  $current=([Uri]::new([Uri]$current,$variant)).AbsoluteUri
 }
 $sample=@()
 if(-not $errorText -and $segmentList.Count -ge 2){
  $sample=@($segmentList[[Math]::Max(0,$segmentList.Count-3)],$segmentList[$segmentList.Count-2])
 }
 $pass=0
 if($sample.Count -eq 2){
  for($idx=0;$idx -lt 2;$idx++){
   $seg=$sample[$idx]
   $r=CurlFetch $seg.Url $true $c.Agent $c.Referer
   $ratio=if($r.Ok -and $r.Seconds -gt 0 -and $seg.Duration -gt 0){$seg.Duration/$r.Seconds}else{0}
   $good=$r.Ok -and $ratio -ge 1.5
   if($good){$pass++}
   $results.Add([pscustomobject]@{
    Host=$c.Host;Feed=$c.Feed;URLKey=$c.Key;Segment=$idx+1;Http=$r.Code
    CurlExit=$r.Exit;Seconds=[Math]::Round($r.Seconds,2);Bytes=$r.Bytes
    MediaDuration=[Math]::Round($seg.Duration,2);RealtimeRatio=[Math]::Round($ratio,2)
    Pass=$good;Error=''
   })
  }
 }else{
  if(-not $errorText){$errorText='NO_TESTABLE_MEDIA'}
  $results.Add([pscustomobject]@{
   Host=$c.Host;Feed=$c.Feed;URLKey=$c.Key;Segment=0;Http=if($response){$response.Code}else{'000'}
   CurlExit=if($response){$response.Exit}else{-1};Seconds=0;Bytes=0;MediaDuration=0
   RealtimeRatio=0;Pass=$false;Error=$errorText
  })
 }
 Write-Host ('SOURCE {0} key={1}: full segments PASS={2}/2; issue={3}' -f
   $c.Host,$c.Key,$pass,$(if($errorText){$errorText}else{'none'}))
}
$results|Export-Csv -LiteralPath $report -NoTypeInformation -Encoding UTF8
$winners=@($results|Group-Object URLKey|Where-Object{
 @($_.Group).Count -eq 2 -and @($_.Group|Where-Object Pass).Count -eq 2
})
$text=[Collections.Generic.List[string]]::new()
$text.Add('W2019S SATURDAY IPTV: DIRECT FROM REMOTE SITE')
$text.Add('No 3proxy usage. No video retained. Two full segments >=1.5x real time required.')
$text.Add('Not compared with identical W2022 URLs unless URLKey matches a local report.')
$text.Add("Sources found=$($candidates.Count); tested=$($chosen.Count); passing=$($winners.Count)")
foreach($w in $winners){
 $minRatio=($w.Group|Measure-Object RealtimeRatio -Minimum).Minimum
 $text.Add(('PASS: host={0}; URLKey={1}; minimum ratio={2}' -f
   $w.Group[0].Host,$w.Group[0].URLKey,$minRatio))
}
if($winners.Count -eq 0){$text.Add('NO_PASS: this remote vantage point found no confirmed fast Saturday stream.')}
$text.Add("DETAILS: $report")
$text.Add('3PROXY / FIREWALL / ROUTER / CADDY / IPTV: UNCHANGED')
[IO.File]::WriteAllLines($summary,$text,[Text.UTF8Encoding]::new($true))
Write-Host ''
Write-Host '=== W2019S SATURDAY PROBE FINISHED ==='
$text|Where-Object{$_ -match '^(Sources found|PASS:|NO_PASS:)'}|ForEach-Object{Write-Host $_}
Write-Host "SUMMARY: $summary"
Write-Host "DETAILS: $report"
Write-Host 'NO CHANGES MADE'
$sha.Dispose()
