#requires -Version 7.0
# IPTV Manager v2: one read-only catalog -> HLS audit -> RU shortlist cycle.
# Does NOT create/change scheduled tasks, live M3U, EPG, Lampac, Caddy or plugins.
[CmdletBinding()]
param(
    [ValidateRange(8,35)][int]$TimeoutSeconds=19,
    [ValidateRange(5,30)][int]$RecheckSeconds=12,
    [ValidateRange(1,6)][int]$Concurrency=4
)
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$root='C:\ReservLampac\IPTVPlus\CatalogV2'
$nightRoot=Join-Path $root 'Nightly'
$ruFile='C:\IPTV-Manager\public\playlists\IPTV-RU-Pilot-v1.m3u'
$uaFile='C:\IPTV-Manager\public\playlists\IPTV-UA.m3u'
$combinedFile='C:\IPTV-Manager\public\playlists\IPTV-UA-RU-Pilot-v1.m3u'
$build=Join-Path $root 'Build-IPTV-Catalog-v2.ps1'
$auditScript=Join-Path $root 'Audit-IPTV-Catalog-v2-Candidates-v2.ps1'
$rank=Join-Path $root 'Rank-IPTV-RU-Alternatives-v1.ps1'
$started=[DateTime]::UtcNow
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
New-Item -ItemType Directory -Path $nightRoot -Force | Out-Null
$logFile=Join-Path $nightRoot ('run-'+$runId+'.log')
$lockFile=Join-Path $nightRoot 'nightly.lock'
$lock=$null
$transcript=$false
try{
    try{
        $lock=[IO.FileStream]::new($lockFile,[IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    }catch{
        throw 'A second IPTV Manager v2 cycle is already running'
    }
    Start-Transcript -LiteralPath $logFile -ErrorAction Stop | Out-Null
    $transcript=$true
    Write-Host '=== IPTV MANAGER V2: READ-ONLY NIGHTLY PIPELINE ==='
    Write-Host "Run ID: $runId"
    Write-Host 'Automatic publication: DISABLED'
    foreach($file in @($ruFile,$uaFile,$combinedFile)){
        if(-not (Test-Path -LiteralPath $file -PathType Leaf)){
            throw "Missing published playlist: $file"
        }
    }
    $hashes=[ordered]@{}
    foreach($file in @($ruFile,$uaFile,$combinedFile)){
        $hashes[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    }
    $required=@(
        [pscustomobject]@{Path=$build;Needle='CANONICAL CATALOG BUILT (NOT PUBLISHED)'}
        [pscustomobject]@{Path=$auditScript;Needle='CANDIDATE AUDIT V2: COMPLETE (NO PUBLICATION)'}
        [pscustomobject]@{Path=$rank;Needle='IPTV RU ALTERNATIVE SHORTLIST: COMPLETE (NOT PUBLISHED)'}
    )
    $scriptHashes=[ordered]@{}
    foreach($item in $required){
        if(-not (Test-Path -LiteralPath $item.Path -PathType Leaf)){
            throw "Missing required module: $($item.Path)"
        }
        $content=Get-Content -LiteralPath $item.Path -Raw -Encoding UTF8
        if(-not $content.Contains($item.Needle)){
            throw "Unknown module version: $($item.Path)"
        }
        $scriptHashes[(Split-Path $item.Path -Leaf)]=(
            Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash
    }
    function Get-NewReport {
        param([string]$Prefix,[DateTime]$Since,[string]$ExpectedStatus)
        $matches=@(
            Get-ChildItem -LiteralPath $root -Directory -Filter ($Prefix+'-*') |
                Where-Object {$_.CreationTimeUtc -ge $Since.AddSeconds(-2)} |
                Sort-Object CreationTimeUtc -Descending
        )
        if($matches.Count -ne 1){
            throw "Expected one new $Prefix folder, found $($matches.Count)"
        }
        $report=Join-Path $matches[0].FullName 'report.json'
        if(-not (Test-Path -LiteralPath $report -PathType Leaf)){
            throw "Missing $Prefix report: $report"
        }
        $data=Get-Content -LiteralPath $report -Raw -Encoding UTF8 |
            ConvertFrom-Json -AsHashtable
        if($data.Status -and $data.Status -ne $ExpectedStatus){
            throw "Unexpected $Prefix report status: $($data.Status)"
        }
        if($Prefix -eq 'audit' -and $data.Mode -ne $ExpectedStatus){
            throw "Unexpected audit report mode: $($data.Mode)"
        }
        return [pscustomobject]@{
            Directory=$matches[0].FullName
            Report=$report
            Data=$data
        }
    }
    Write-Host '=== STEP 1 / 3: REFRESH SOURCE CATALOG ==='
    $t=[DateTime]::UtcNow
    & $build
    if(-not $?){throw 'Catalog module failed'}
    $catalog=Get-NewReport 'catalog' $t 'READ_ONLY_CATALOG'
    $catalogPath=[string]$catalog.Data.CatalogPath
    if(-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)){
        throw 'Catalog builder did not produce channel-catalog.json'
    }
    if($catalog.Data.BaselineSha256 -ne $hashes[$ruFile]){
        throw 'Catalog and published RU hash mismatch'
    }
    Write-Host '=== STEP 2 / 3: NETWORK TEST ALTERNATIVES ==='
    $t=[DateTime]::UtcNow
    & $auditScript -CatalogPath $catalogPath -TimeoutSeconds $TimeoutSeconds -RecheckSeconds $RecheckSeconds -Concurrency $Concurrency
    if(-not $?){throw 'HLS candidate audit failed'}
    $audit=Get-NewReport 'audit' $t 'NETWORK_ONLY_NOT_CONTENT_VERIFIED'
    if($audit.Data.CatalogPath -ne $catalogPath -or
       $audit.Data.ProductionRUHash -ne $hashes[$ruFile]){
        throw 'HLS audit does not correspond to this source catalog'
    }
    Write-Host '=== STEP 3 / 3: GENERATE CHANNEL SHORTLIST ==='
    $t=[DateTime]::UtcNow
    & $rank -CatalogPath $catalogPath -AuditReportPath $audit.Report
    if(-not $?){throw 'RU shortlist module failed'}
    $shortlist=Get-NewReport 'shortlist' $t 'SHORTLIST_NETWORK_ONLY_NO_PUBLICATION'
    if($shortlist.Data.InputCatalog -ne $catalogPath -or
       $shortlist.Data.InputNetworkAudit -ne $audit.Report){
        throw 'RU shortlist was built from unexpected inputs'
    }
    foreach($file in $hashes.Keys){
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $hashes[$file]){
            throw "A published playlist changed during this nightly run: $file"
        }
    }
    $history=Join-Path $nightRoot 'candidate-history.jsonl'
    $recorded=[DateTime]::UtcNow.ToString('o')
    $date=[DateTime]::UtcNow.ToString('yyyy-MM-dd')
    $records=[Collections.Generic.List[string]]::new()
    foreach($result in @($audit.Data.Results)){
        $records.Add(([ordered]@{
            RunId=$runId
            Utc=$recorded
            UtcDate=$date
            ChannelId=[string]$result.Id
            Channel=[string]$result.Channel
            UrlHash=[string]$result.UrlHash
            Host=[string]$result.Host
            Status=[string]$result.Status
            HlsProgressObserved=($result.Status -eq 'HLS_PROGRESS_OBSERVED')
            MediaUriHash=[string]$result.MediaUriHash
            ContentVerified=$false
        } | ConvertTo-Json -Compress -Depth 4))
    }
    if($records.Count -ne [int]$audit.Data.Total){
        throw 'History entry count differs from network audit total'
    }
    [IO.File]::AppendAllText($history,
        (($records.ToArray() -join [Environment]::NewLine)+[Environment]::NewLine),
        [Text.UTF8Encoding]::new($false))
    # Repeat network success over distinct dates; this is NOT content validation.
    $cutoff=[DateTime]::UtcNow.AddDays(-7)
    $rolling=[Collections.Generic.List[object]]::new()
    foreach($line in [IO.File]::ReadLines($history,[Text.Encoding]::UTF8)){
        if(-not $line.Trim()){continue}
        $h=$line | ConvertFrom-Json -AsHashtable
        if(-not $h.HlsProgressObserved){continue}
        $dt=[DateTime]::Parse([string]$h.Utc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind)
        if($dt -lt $cutoff){continue}
        $rolling.Add([pscustomobject]@{
            Key=([string]$h.ChannelId+'|'+[string]$h.UrlHash)
            Date=[string]$h.UtcDate
        })
    }
    $repeat=0
    foreach($group in ($rolling | Group-Object Key)){
        if(@($group.Group.Date | Sort-Object -Unique).Count -ge 2){$repeat++}
    }
    $summary=[ordered]@{
        RunId=$runId
        Status='COMPLETED_NO_PUBLICATION'
        StartedUtc=$started.ToString('o')
        EndedUtc=[DateTime]::UtcNow.ToString('o')
        SourceCatalog=$catalogPath
        NetworkAuditReport=$audit.Report
        ChannelShortlistReport=$shortlist.Report
        CatalogAlternativeURLs=[int]$catalog.Data.TotalAlternativeURLs
        CandidatesTested=[int]$audit.Data.Total
        HlsSegmentResponses=[int]$audit.Data.HlsSegmentOk
        HlsProgressObserved=[int]$audit.Data.ProgressObserved
        SharedMediaRouteGroups=[int]$audit.Data.SharedRouteGroups
        WorkingChannelCoverage=47-[int]$shortlist.Data.ChannelsWithoutPassingAlternatives
        ShortlistedReviewEntries=[int]$shortlist.Data.ReviewEntries
        NetworkOKTwoOrMoreNightsLast7Days=$repeat
        RealTVVerified=0
        PublishedPlaylistSHA256=$hashes
        ModulesSHA256=$scriptHashes
        HistoryFile=$history
        LogFile=$logFile
        AutoPublish='DISABLED'
        ScheduledTaskChanges='NONE'
    }
    $summaryPath=Join-Path $nightRoot ('summary-'+$runId+'.json')
    [IO.File]::WriteAllText($summaryPath,($summary|ConvertTo-Json -Depth 9),
        [Text.UTF8Encoding]::new($false))
    $latest=Join-Path $nightRoot 'latest-success.json'
    $tmp=Join-Path $nightRoot ('latest-'+$runId+'.tmp')
    [IO.File]::WriteAllText($tmp,($summary|ConvertTo-Json -Depth 9),
        [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $latest -Force
    Write-Host '=== NIGHTLY RUN SUMMARY ==='
    [pscustomobject]@{
        CatalogAlternatives=$summary.CatalogAlternativeURLs
        CandidatesTested=$summary.CandidatesTested
        HlsProgressObserved=$summary.HlsProgressObserved
        WorkingChannelCoverage=$summary.WorkingChannelCoverage
        ReviewEntries=$summary.ShortlistedReviewEntries
        MultipleNightNetworkOK=$summary.NetworkOKTwoOrMoreNightsLast7Days
        Summary=$summaryPath
        History=$history
        Log=$logFile
        LivePlaylists='UNCHANGED'
        AutoPublish='OFF'
        TaskSchedule='NOT_MODIFIED'
    } | Format-List
    Write-Host 'IPTV MANAGER V2 NIGHTLY CYCLE: COMPLETE (READ ONLY)'
}catch{
    Write-Host '=== NIGHTLY RUN FAILED ==='
    Write-Host $_.Exception.Message
    throw
}finally{
    if($transcript){Stop-Transcript | Out-Null}
    if($lock){$lock.Dispose()}
}
