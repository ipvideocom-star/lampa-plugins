#requires -Version 5.1
# W2019S P1 IPTV HLS recheck. Does NOT use or modify 3proxy/IPTV Agent/API.
# Network requests: public internet HTTP(S), bounded HLS manifests and one short segment per channel.
# Disk: one unique JSON report under IPTV-Agent\state; temporary bounded curl files removed.
[CmdletBinding()]
param([ValidateRange(8,30)][int]$TimeoutSeconds=15,[ValidateRange(5,30)][int]$RecheckSeconds=10)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
if($env:COMPUTERNAME -cne 'W2019S'){throw 'This script is restricted to W2019S'}
$csv='C:\IPTV-Agent\state\P1-REMOTE-RECHECK-10.csv'
$state='C:\IPTV-Agent\state'
$csvSha='9427A0995BD033F8FEE325B58DF3C902C7BC6716D5E079A298E36B6E7B019B98'
$expected=@('144E5ACC08C7235F','CA89360B01F3C0F5','2FADE45EC80760D2',
'F01F2D5CACFCED3E','29E98B6BB1D0DE16','56555A9506001E27',
'3B04BB4230BB7838','EAD6E44153726FEF','5C6E0F81CF5381BE',
'46D4A65B7B5274A3')
if(-not(Test-Path -LiteralPath $csv -PathType Leaf)){throw "Input CSV missing: $csv"}
if(-not(Test-Path -LiteralPath $state -PathType Container)){throw 'Agent state folder missing'}
if((Get-FileHash -LiteralPath $csv -Algorithm SHA256).Hash -cne $csvSha){throw 'P1 CSV hash mismatch'}
$rows=@(Import-Csv -LiteralPath $csv -Encoding UTF8)
if($rows.Count -ne 10){throw 'Unexpected P1 row count'}
function Hash16([string]$s){
  $sha=[Security.Cryptography.SHA256]::Create()
  try{return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($s))).Replace('-','').Substring(0,16)}
  finally{$sha.Dispose()}
}
function Is-PublicV4([Net.IPAddress]$ip){
  if($ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){return $false}
  $b=$ip.GetAddressBytes()
  if($b[0] -in @(0,10,127) -or $b[0] -ge 224){return $false}
  if($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127){return $false}
  if($b[0] -eq 169 -and $b[1] -eq 254){return $false}
  if($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31){return $false}
  if($b[0] -eq 192 -and $b[1] -in @(0,168)){return $false}
  if($b[0] -eq 198 -and $b[1] -in @(18,19,51)){return $false}
  if($b[0] -eq 203 -and $b[1] -eq 0 -and $b[2] -eq 113){return $false}
  return $true
}
function Get-ValidatedAddress([Uri]$uri){
  if(-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http','https') -or
     $uri.UserInfo -or $uri.Host -match '(?i)(^localhost$|\.(local|lan|internal|home|test|invalid|onion)$)' -or
     $uri.Host -notmatch '^[a-zA-Z0-9.-]+$' -or $uri.Port -notin @(80,443,8080)){
    throw 'UNSAFE_MEDIA_URI'
  }
  $ips=@([Net.Dns]::GetHostAddresses($uri.Host)|Where-Object {
    $_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork
  })
  if($ips.Count -eq 0){throw 'DNS_NO_A_RECORD'}
  foreach($ip in $ips){if(-not(Is-PublicV4 $ip)){throw 'NONPUBLIC_MEDIA_IP'}}
  return $ips[0].ToString()
}
function Read-Pinned([Uri]$uri,[int]$maxBytes,[string]$agent,[string]$referer,[switch]$segment){
  $ip=Get-ValidatedAddress $uri
  $file=[IO.Path]::GetTempFileName()
  try{
    $args=@('--noproxy','*','--silent','--show-error','--http1.1',
      '--connect-timeout','6','--max-time',[string]$TimeoutSeconds,
      '--max-redirs','0','--proto','=http,https',
      '--resolve',("{0}:{1}:{2}" -f $uri.Host,$uri.Port,$ip),
      '--max-filesize',[string]$maxBytes,
      '--output',$file,'--write-out','%{http_code}')
    if($segment){$args+=@('--range','0-563')}
    if($agent){$args+=@('--user-agent',$agent)}
    if($referer){$args+=@('--referer',$referer)}
    for($n=0;$n -lt 2;$n++){
      $a=@($args)
      if($n -eq 1){$a+='--ignore-content-length';[IO.File]::WriteAllBytes($file,[byte[]]@())}
      $a+=$uri.AbsoluteUri
      $old=$ErrorActionPreference
      try{$ErrorActionPreference='Continue';$code=& curl.exe @a 2>$null;$exit=$LASTEXITCODE}
      finally{$ErrorActionPreference=$old}
      $http=0
      if("$code" -match '^\d{3}$'){$http=[int]$code}
      $size=(Get-Item -LiteralPath $file).Length
      if($n -eq 0 -and $segment -and $exit -eq 63 -and $http -eq 200 -and $size -eq 0){continue}
      $cap=($n -eq 1 -and $segment -and $exit -eq 63 -and $http -eq 200 -and $size -eq $maxBytes)
      if($exit -ne 0 -and -not $cap){
        if($exit -eq 28){throw 'TIMEOUT'}
        if($exit -eq 6){throw 'DNS_ERROR'}
        if($exit -in @(35,51,58,60,77,83)){throw 'TLS_ERROR'}
        throw "CURL_EXIT_$exit"
      }
      if($http -lt 200 -or $http -ge 300){throw "HTTP_$http"}
      $bytes=[IO.File]::ReadAllBytes($file)
      if($bytes.Length -gt $maxBytes){throw 'RESPONSE_TOO_LARGE'}
      return $bytes
    }
    throw 'RANGE_READ_FAILED'
  }finally{Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue}
}
function Get-Media([Uri]$url,[string]$agent,[string]$referer){
  for($i=0;$i -lt 3;$i++){
    $bytes=Read-Pinned $url 262144 $agent $referer
    $txt=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
    if(-not $txt.StartsWith('#EXTM3U')){throw 'NOT_HLS'}
    $lines=@($txt -split '\r?\n'|ForEach-Object {$_.Trim()})
    if($txt -match '#EXT-X-STREAM-INF:'){
      $variant=''
      for($j=0;$j -lt $lines.Count-1;$j++){
        if($lines[$j] -match '^#EXT-X-STREAM-INF'){
          for($k=$j+1;$k -lt $lines.Count;$k++){
            if($lines[$k] -and -not $lines[$k].StartsWith('#')){$variant=$lines[$k];break}
          }
          break
        }
      }
      if(-not $variant){throw 'NO_HLS_VARIANT'}
      $url=[Uri]::new($url,$variant);continue
    }
    if($txt -notmatch '#EXTINF:'){throw 'NO_MEDIA_SEGMENTS'}
    return [pscustomobject]@{Uri=$url;Text=$txt;Lines=$lines}
  }
  throw 'HLS_NESTING_LIMIT'
}
function Last-Segment($media){
  $entries=@($media.Lines|Where-Object {$_ -and -not $_.StartsWith('#')})
  if($entries.Count -eq 0){throw 'NO_SEGMENT_URL'}
  return [Uri]::new([Uri]$media.Uri,[string]$entries[-1])
}
function Probe($row){
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $status='FAILED';$reason='';$bytes=0
  try{
    $agent=[string]$row.UserAgent
    $referer=[string]$row.Referrer
    $first=Get-Media ([Uri]$row.URL) $agent $referer
    $segment=Last-Segment $first
    $prefix=Read-Pinned $segment 564 $agent $referer -segment
    $bytes=$prefix.Length
    if($bytes -eq 0){throw 'EMPTY_MEDIA_SEGMENT'}
    $isTs=($bytes -ge 377 -and $prefix[0] -eq 0x47 -and
           $prefix[188] -eq 0x47 -and $prefix[376] -eq 0x47)
    Start-Sleep -Seconds $RecheckSeconds
    $second=Get-Media ([Uri]$first.Uri) $agent $referer
    $firstLast=(Last-Segment $first).AbsoluteUri
    $secondLast=(Last-Segment $second).AbsoluteUri
    $seq1=[regex]::Match($first.Text,'(?m)^#EXT-X-MEDIA-SEQUENCE:(\d+)')
    $seq2=[regex]::Match($second.Text,'(?m)^#EXT-X-MEDIA-SEQUENCE:(\d+)')
    $progress=($firstLast -cne $secondLast -or
      ($seq1.Success -and $seq2.Success -and $seq1.Groups[1].Value -cne $seq2.Groups[1].Value))
    if($progress){$status='HLS_PROGRESS_OBSERVED'}
    else{$status='HLS_SEGMENT_OK_NO_PROGRESS_SEEN'}
    if(-not $isTs){$reason='SEGMENT_PREFIX_NOT_MPEGTS; inspect codecs later'}
  }catch{
    $reason=$_.Exception.Message
    if($reason.Length -gt 160){$reason=$reason.Substring(0,160)}
  }finally{$sw.Stop()}
  return [pscustomobject]@{
    Channel=[string]$row.Channel;UrlKey=[string]$row.URLKey
    Status=$status;Seconds=[Math]::Round($sw.Elapsed.TotalSeconds,2)
    SegmentBytes=$bytes;Reason=$reason
  }
}
$actualKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($r in $rows){
  $key=[string]$r.URLKey
  if($r.Priority -cne 'P1' -or $r.Group -cne 'RU-New' -or
     $key -cnotmatch '^[A-F0-9]{16}$' -or
     (Hash16 ([string]$r.URL)) -cne $key -or
     -not $actualKeys.Add($key) -or
     $key -cnotin $expected){throw 'P1 source row validation failed'}
  foreach($h in @([string]$r.UserAgent,[string]$r.Referrer)){
    if($h.Length -gt 512 -or $h -match '[\x00-\x1F\x7F]'){throw 'Unsafe HTTP headers'}
  }
}
if($actualKeys.Count -ne 10){throw 'Missing P1 approved source'}
Get-Command curl.exe -ErrorAction Stop|Out-Null
Write-Host '=== W2019S DIRECT HLS P1 RECHECK (10 STREAMS) ==='
Write-Host '3proxy: NOT USED; IPTV Agent: NOT CHANGED; network: direct only'
$list=New-Object 'System.Collections.Generic.List[object]'
foreach($row in $rows){
  $p=Probe $row
  $list.Add($p)
  Write-Host ('{0} | {1} | {2:N1}s | {3}' -f $p.Channel,$p.Status,$p.Seconds,$p.Reason)
}
$now=Get-Date -Format 'yyyyMMdd-HHmmss'
$dst=Join-Path $state ("P1-W2019S-direct-recheck-$now-"+[guid]::NewGuid().ToString('N').Substring(0,8)+'.json')
$report=[ordered]@{
  SchemaVersion=1;CreatedUtc=[DateTime]::UtcNow.ToString('o')
  Node='W2019S';Route='DIRECT_W2019S';CsvSHA256=$csvSha
  Records=@($list.ToArray());PublishedPlaylists='UNCHANGED'
}
$json=ConvertTo-Json -InputObject $report -Depth 7
$stream=[IO.File]::Open($dst,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{
  $b=[Text.UTF8Encoding]::new($false).GetBytes($json)
  $stream.Write($b,0,$b.Length);$stream.Flush()
}finally{$stream.Dispose()}
Write-Host '=== P1 W2019S RECHECK SUMMARY ==='
$list|Group-Object Status|Select-Object Name,Count|Format-Table -AutoSize
Write-Host "Report: $dst"
Write-Host 'Services, Caddy, 3proxy, production playlists: UNCHANGED'
