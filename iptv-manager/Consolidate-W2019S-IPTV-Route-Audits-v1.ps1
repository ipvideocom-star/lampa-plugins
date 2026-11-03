#requires -Version 5.1
# Offline consolidation of P1 + P2 HLS checks from W2019S.
# No Internet requests; no changes to IPTV Agent/3proxy/Caddy/Lampac/playlists.
# Output only channel metadata, URL fingerprints and source report filenames; never original URLs.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -cne 'W2019S'){throw 'Only run on W2019S'}
$state='C:\IPTV-Agent\state'
$p1Csv=Join-Path $state 'P1-REMOTE-RECHECK-10.csv'
$p2Csv=Join-Path $state 'P2-REMOTE-NEW-75.csv'
$expectedP1Sha='9427A0995BD033F8FEE325B58DF3C902C7BC6716D5E079A298E36B6E7B019B98'
$expectedP2Sha='D3A91C5D11161FCF29B3C5814C1C36DF15A6377D1D4D36DFA3B7DE241DAA11BD'
$p1Initial='P1-W2019S-direct-recheck-20261103-094943-dc261035.json'
$p1Followup='P1-W2019S-vintera8081-recheck-20261103-100625-6d208117.json'
$p2Files=@(
  'P2-W2019S-direct-batch1-20261103-101408-da1454d6.json'
  'P2-W2019S-direct-batch2-20261103-101624-dd70efa1.json'
  'P2-W2019S-direct-batch3-20261103-102020-61ff7ff9.json'
  'P2-W2019S-direct-batch4-20261103-102110-67ae6eb5.json'
  'P2-W2019S-direct-batch5-20261103-102154-1fc65ceb.json'
  'P2-W2019S-direct-batch6-20261103-115537-9bb14a47.json'
  'P2-W2019S-direct-batch7-20261103-115701-8b8dd045.json'
  'P2-W2019S-direct-batch8-20261103-115744-f5dc5c09.json'
)
function Assert-File([string]$p){
  if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing required input: $p"}
}
foreach($p in @($p1Csv,$p2Csv) + @(
  (Join-Path $state $p1Initial),(Join-Path $state $p1Followup)
) + @($p2Files|ForEach-Object {Join-Path $state $_})){
  Assert-File $p
}
if((Get-FileHash -LiteralPath $p1Csv -Algorithm SHA256).Hash -cne $expectedP1Sha -or
   (Get-FileHash -LiteralPath $p2Csv -Algorithm SHA256).Hash -cne $expectedP2Sha){
  throw 'Historical P1/P2 CSV SHA256 mismatch'
}
$p1=@(Import-Csv -LiteralPath $p1Csv -Encoding UTF8)
$p2=@(Import-Csv -LiteralPath $p2Csv -Encoding UTF8)
if($p1.Count -ne 10 -or $p2.Count -ne 75){throw 'P1/P2 CSV row count mismatch'}
function Read-Report([string]$name,[int]$expected,[string]$csvSha){
  $p=Join-Path $state $name
  $o=Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
  if($o.SchemaVersion -ne 1 -or $o.Node -cne 'W2019S' -or
     $o.Route -cne 'DIRECT_W2019S' -or $o.CsvSHA256 -cne $csvSha -or
     @($o.Records).Count -ne $expected -or $o.PublishedPlaylists -cne 'UNCHANGED'){
    throw "Unexpected HLS report structure: $name"
  }
  return $o
}
function Assert-Record($rec,$csvRow,[string]$sourceName){
  if([string]$rec.UrlKey -cne [string]$csvRow.URLKey -or
     [string]$rec.Channel -cne [string]$csvRow.Channel -or
     $rec.Status -notin @('HLS_PROGRESS_OBSERVED','HLS_SEGMENT_OK_NO_PROGRESS_SEEN','FAILED')){
    throw "Report/CSV mismatch in $sourceName"
  }
}
$initial=Read-Report $p1Initial 10 $expectedP1Sha
$followup=Read-Report $p1Followup 2 $expectedP1Sha
$firstByKey=@{}
for($i=0;$i -lt 10;$i++){
  $entry=$initial.Records[$i]
  Assert-Record $entry $p1[$i] $p1Initial
  $key=[string]$entry.UrlKey
  if($firstByKey.ContainsKey($key)){throw "Duplicate initial P1: $key"}
  $firstByKey[$key]=$entry
}
$followByKey=@{}
foreach($rec in $followup.Records){
  $key=[string]$rec.UrlKey
  if(-not $firstByKey.ContainsKey($key) -or $followByKey.ContainsKey($key) -or
     $firstByKey[$key].Status -cne 'FAILED' -or
     $rec.Status -cne 'HLS_PROGRESS_OBSERVED'){
    throw "Unexpected P1 8081 follow-up: $key"
  }
  $p1Row=@($p1|Where-Object {$_.URLKey -ceq $key})
  if($p1Row.Count -ne 1){throw "P1 follow-up key missing/duplicated: $key"}
  Assert-Record $rec $p1Row[0] $p1Followup
  $followByKey[$key]=$rec
}
if($followByKey.Count -ne 2){throw 'Expected exactly two P1 rechecks'}
$combined=New-Object 'System.Collections.Generic.List[object]'
$provenance=New-Object 'System.Collections.Generic.List[object]'
foreach($row in $p1){
  $key=[string]$row.URLKey
  $rec=$firstByKey[$key]
  $source=$p1Initial
  if($followByKey.ContainsKey($key)){
    $rec=$followByKey[$key];$source=$p1Followup
  }
  $combined.Add([pscustomobject]@{
    Priority='P1';Group=[string]$row.Group;Region=[string]$row.Region
    Channel=[string]$row.Channel;URLKey=$key;Status=[string]$rec.Status
    ReportFile=$source
  })
}
for($b=1;$b -le 8;$b++){
  $file=$p2Files[$b-1]
  $expectedCount=if($b -eq 8){5}else{10}
  $report=Read-Report $file $expectedCount $expectedP2Sha
  if([int]$report.BatchNumber -ne $b -or [int]$report.BatchSize -ne $expectedCount){
    throw "P2 batch metadata mismatch: $file"
  }
  $start=($b-1)*10
  for($j=0;$j -lt $expectedCount;$j++){
    $row=$p2[$start+$j];$rec=$report.Records[$j]
    Assert-Record $rec $row $file
    $combined.Add([pscustomobject]@{
      Priority='P2';Group=[string]$row.Group;Region=[string]$row.Region
      Channel=[string]$row.Channel;URLKey=[string]$row.URLKey
      Status=[string]$rec.Status;ReportFile=$file
    })
  }
}
if($combined.Count -ne 85){throw 'Unexpected consolidated row count'}
$success=@($combined|Where-Object {$_.Status -ceq 'HLS_PROGRESS_OBSERVED'})
$uncertain=@($combined|Where-Object {$_.Status -ceq 'HLS_SEGMENT_OK_NO_PROGRESS_SEEN'})
$failed=@($combined|Where-Object {$_.Status -ceq 'FAILED'})
$p1Pass=@($combined|Where-Object {$_.Priority -ceq 'P1' -and $_.Status -ceq 'HLS_PROGRESS_OBSERVED'})
$p2Pass=@($combined|Where-Object {$_.Priority -ceq 'P2' -and $_.Status -ceq 'HLS_PROGRESS_OBSERVED'})
$uniqueChannels=@($success|Select-Object -ExpandProperty Channel -Unique)
if($success.Count -ne 22 -or $uncertain.Count -ne 13 -or $failed.Count -ne 50 -or
   $p1Pass.Count -ne 10 -or $p2Pass.Count -ne 12 -or $uniqueChannels.Count -ne 21){
  throw 'Expected totals 22/13/50, P1=10, P2=12, unique channels=21 not confirmed'
}
$reportHashes=@(
  foreach($file in @($p1Initial,$p1Followup)+$p2Files){
    [pscustomobject]@{File=$file;SHA256=(Get-FileHash -LiteralPath (Join-Path $state $file) -Algorithm SHA256).Hash}
  }
)
$manifest=[ordered]@{
  SchemaVersion=1
  GeneratedUtc=[DateTime]::UtcNow.ToString('o')
  SourceServer='W2019S'
  Route='DIRECT_W2019S'
  Verification='HLS_NETWORK_ONLY_NOT_CONTENT_VERIFIED'
  P1OriginalCsvSHA256=$expectedP1Sha
  P2OriginalCsvSHA256=$expectedP2Sha
  Total=85
  HlsProgressObserved=22
  SegmentOkNoProgress=13
  Failed=50
  SuccessfulUniqueChannelNames=21
  ReportInputs=@($reportHashes)
  Records=@($combined.ToArray())
}
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')
$dest=Join-Path $state ('IPTV-Remote-P1-P2-RouteSummary-'+$stamp+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.json')
$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($manifest|ConvertTo-Json -Depth 12))
$fs=[IO.File]::Open($dest,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$fs.Write($bytes,0,$bytes.Length);$fs.Flush()}finally{$fs.Dispose()}
Write-Host '=== W2019S P1/P2 ROUTE CONSOLIDATION COMPLETE ==='
[pscustomobject]@{
  Total=85;HLSProgress=22;SegmentNoProgress=13;Failed=50
  UniqueHLSChannelNames=21
  P1Progress=10;P2Progress=12
  Report=$dest
  ReportSHA256=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
  IPTVStreamURLsIncluded=$false
  NetworkRequests=0
  ProductionChanges='NONE'
} | Format-List
Write-Host '=== REMOTE HLS-PROGRESS CHANNELS (NOT CONTENT VERIFIED) ==='
$success | Select-Object Priority,Channel,URLKey | Format-Table -AutoSize
