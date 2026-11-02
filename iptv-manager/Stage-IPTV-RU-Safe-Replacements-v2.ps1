#requires -Version 7.0
# IPTV Manager v2: stage up to 3 RU replacements, never publish.
# v2: match each channel by (canonical id, exact title, original URL hash),
# NOT by canonical tvg-id alone; duplicates are valid across channel variants.
# Requires repeated independent HLS success across distinct UTC dates.
# Stages full RU and UA+RU M3U preserving every original channel line,
# all UA #EXTVLCOPT, order, names, groups, IDs, EPG and fallback sources.
# NEVER claims HLS==real TV; human programme review remains required.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CatalogPath,
    [Parameter(Mandatory=$true)][string]$AuditReportPath,
    [ValidateRange(1,3)][int]$MaxReplacements=3,
    [ValidateRange(2,7)][int]$RequiredDistinctDays=2
)
$ErrorActionPreference='Stop'
$root='C:\ReservLampac\IPTVPlus\CatalogV2'
$production='C:\IPTV-Manager\public\playlists'
$ruFile=Join-Path $production 'IPTV-RU-Pilot-v1.m3u'
$uaFile=Join-Path $production 'IPTV-UA.m3u'
$combinedFile=Join-Path $production 'IPTV-UA-RU-Pilot-v1.m3u'
$historyFile=Join-Path $root 'Nightly\candidate-history.jsonl'
$rootResolved=(Resolve-Path -LiteralPath $root).ProviderPath
function Safe-Input([string]$p){
    $path=(Resolve-Path -LiteralPath $p -ErrorAction Stop).ProviderPath
    if(-not $path.StartsWith(($rootResolved.TrimEnd('\')+'\'),
        [StringComparison]::OrdinalIgnoreCase)){
        throw "Input is outside $root"
    }
    return $path
}
function Read-M3u([string]$file){
    $all=[IO.File]::ReadAllLines($file,[Text.Encoding]::UTF8)
    if($all.Count -lt 3 -or
       $all[0].TrimStart([char]0xFEFF) -cne '#EXTM3U'){
        throw "Invalid M3U playlist $file"
    }
    $entries=[Collections.Generic.List[object]]::new()
    $block=[Collections.Generic.List[string]]::new()
    $header=''
    for($i=1;$i -lt $all.Count;$i++){
        $line=$all[$i].Trim()
        if(-not $line){continue}
        if($line.StartsWith('#EXTINF:')){
            if($header){throw "Unclosed EXTINF in $file"}
            $header=$line
            $block.Clear()
            $block.Add($line)
            continue
        }
        if($line.StartsWith('#')){
            if(-not $header){throw "Unexpected M3U directive before channel in $file"}
            $block.Add($line)
            continue
        }
        if(-not $header){throw "URL without EXTINF in $file"}
        $idMatch=[regex]::Match($header,'(?i)tvg-id="([^"]+)"')
        $id=if($idMatch.Success){($idMatch.Groups[1].Value -split '@')[0]}else{''}
        $uri=$null
        if(-not [Uri]::TryCreate($line,[UriKind]::Absolute,[ref]$uri)){
            throw "Invalid channel URL in $file"
        }
        $block.Add($line)
        $entries.Add([pscustomobject]@{
            Name=$header.Substring($header.LastIndexOf(',')+1).Trim()
            Id=$id
            Host=$uri.DnsSafeHost.ToLowerInvariant()
            URL=$line
            Lines=@($block.ToArray())
        })
        $header=''
        $block.Clear()
    }
    if($header){throw "Incomplete channel in $file"}
    return ,$entries
}
function FileHash([string]$file){
    return (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
}
function Write-M3u([string]$path,[object[]]$entries){
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add('#EXTM3U')
    foreach($entry in $entries){
        foreach($line in $entry.Lines){$lines.Add([string]$line)}
    }
    $nl=[Environment]::NewLine
    [IO.File]::WriteAllText($path,($lines -join $nl)+$nl,
        [Text.UTF8Encoding]::new($false))
}
$catalogPath=Safe-Input $CatalogPath
$auditPath=Safe-Input $AuditReportPath
$catalog=@(Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -AsHashtable)
$audit=Get-Content -LiteralPath $auditPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -AsHashtable
if($catalog.Count -ne 47 -or
   $audit.Mode -ne 'NETWORK_ONLY_NOT_CONTENT_VERIFIED' -or
   $audit.CatalogPath -ne $catalogPath){
    throw 'Network audit and 47-channel catalog mismatch'
}
$hashes=[ordered]@{}
foreach($f in @($ruFile,$uaFile,$combinedFile)){
    if(-not (Test-Path -LiteralPath $f -PathType Leaf)){throw "Published file missing $f"}
    $hashes[$f]=FileHash $f
}
$catalogReportPath=Join-Path (Split-Path $catalogPath -Parent) 'report.json'
$catalogReport=Get-Content -LiteralPath $catalogReportPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -AsHashtable
if($catalogReport.BaselineSha256 -ne $hashes[$ruFile] -or
   $audit.ProductionRUHash -ne $hashes[$ruFile]){
    throw 'Published RU changed relative to source reports'
}
$ru=(Read-M3u $ruFile).ToArray()
$ua=(Read-M3u $uaFile).ToArray()
$combined=(Read-M3u $combinedFile).ToArray()
if($ru.Count -ne 47 -or $ua.Count -ne 84 -or $combined.Count -ne 131){
    throw "Published playlist totals unexpected: RU=$($ru.Count) UA=$($ua.Count) ALL=$($combined.Count)"
}
$expected=@($ua)+@($ru)
for($i=0;$i -lt $combined.Count;$i++){
    if(($combined[$i].Lines -join [char]10) -cne
       ($expected[$i].Lines -join [char]10)){
        throw "Combined playlist differs at channel index $i"
    }
}
$uaHttpHeaders=@($ua | ForEach-Object {$_.Lines} |
    Where-Object {$_ -match '^#EXTVLCOPT:'}).Count
if($uaHttpHeaders -ne 35){throw "Expected 35 UA EXT/VLC options, found $uaHttpHeaders"}
function IdentityKey([string]$id,[string]$name,[string]$urlHash){
    # The catalog currently uses a 12-character SHA256 URL fingerprint.
    # The title is deliberately exact (case-sensitive identity is not required).
    return $id+'|'+$name+'|'+$urlHash
}
function URLHash([string]$url){
    return [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes($url))).Substring(0,12)
}
$byRecord=[Collections.Generic.Dictionary[string,object]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$idOccurrences=[Collections.Generic.Dictionary[string,int]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach($channel in $catalog){
    if(-not $channel.Name -or -not $channel.CurrentURLHash){
        throw 'Missing exact channel title or source fingerprint in catalog'
    }
    $key=IdentityKey ([string]$channel.Id) ([string]$channel.Name) ([string]$channel.CurrentURLHash)
    if($byRecord.ContainsKey($key)){
        throw "Duplicate exact channel record: $($channel.Name); URL hash $($channel.CurrentURLHash)"
    }
    $byRecord[$key]=$channel
    $id=[string]$channel.Id
    if($id){
        if(-not $idOccurrences.ContainsKey($id)){$idOccurrences[$id]=0}
        $idOccurrences[$id]++
    }
}
$duplicateIds=@($idOccurrences.Keys | Where-Object {$idOccurrences[$_] -gt 1} |
    Sort-Object)
Write-Host '=== CATALOG IDENTITIES ==='
Write-Host "Total channel records: $($byRecord.Count)"
Write-Host "Canonical IDs appearing on multiple records: $($duplicateIds.Count)"
if($duplicateIds.Count -gt 0){
    $duplicateIds | ForEach-Object {
        [pscustomobject]@{CanonicalId=$_;Records=$idOccurrences[$_]}
    } | Format-Table -AutoSize
}
foreach($current in $ru){
    $key=IdentityKey ([string]$current.Id) ([string]$current.Name) (URLHash $current.URL)
    if(-not $byRecord.ContainsKey($key)){
        throw "Exact RU channel entry not found in catalog: $($current.Name)"
    }
}
$history=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
$historyLines=0
if(Test-Path -LiteralPath $historyFile -PathType Leaf){
    foreach($raw in [IO.File]::ReadLines($historyFile,[Text.Encoding]::UTF8)){
        if(-not $raw.Trim()){continue}
        $item=$raw | ConvertFrom-Json -AsHashtable
        $historyLines++
        if($historyLines -gt 25000){throw 'History unexpectedly large'}
        if(-not $item.HlsProgressObserved -or
            -not $item.ChannelId -or -not $item.UrlHash){continue}
        $utc=[DateTime]::Parse([string]$item.Utc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind)
        if($utc -lt [DateTime]::UtcNow.AddDays(-7)){continue}
        # Nightly history contains channel name; bind a URL to its exact
        # source channel, not merely a potentially shared tvg-id.
        if(-not $item.Channel){continue}
        $key=[string]$item.ChannelId+'|'+[string]$item.Channel+'|'+[string]$item.UrlHash
        if(-not $history.ContainsKey($key)){
            $history[$key]=[Collections.Generic.HashSet[string]]::new(
                [StringComparer]::Ordinal)
        }
        [void]$history[$key].Add($utc.ToString('yyyy-MM-dd'))
    }
}
$duplicates=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$success=@($audit.Results | Where-Object {
    $_.Status -eq 'HLS_PROGRESS_OBSERVED' -and $_.MediaUriHash
})
foreach($group in ($success | Group-Object MediaUriHash)){
    $distinctChannels=@($group.Group | ForEach-Object {
        [string]$_.Id+'|'+[string]$_.Channel
    } | Sort-Object -Unique)
    if($distinctChannels.Count -gt 1){
        [void]$duplicates.Add($group.Name)
    }
}
$eligible=[Collections.Generic.List[object]]::new()
$pending=[Collections.Generic.List[object]]::new()
foreach($current in $ru){
    $currentHash=URLHash $current.URL
    $recordKey=IdentityKey ([string]$current.Id) ([string]$current.Name) $currentHash
    if(-not $byRecord.ContainsKey($recordKey)){
        throw "Catalog record mismatch for $($current.Name)"
    }
    $entry=$byRecord[$recordKey]
    if(-not $current.Id){continue}
    foreach($result in $success){
        if($result.Id -ne $current.Id -or
           $result.Channel -cne $current.Name){continue}
        if($result.MediaUriHash -and $duplicates.Contains($result.MediaUriHash)){
            continue
        }
        $matches=@($entry.Alternatives | Where-Object {
            $_.URLHash -eq $result.UrlHash -and
            $_.Host -eq $result.Host -and
            $_.Source -eq $result.Source
        })
        if($matches.Count -ne 1){continue}
        $alt=$matches[0]
        if($alt.URL -eq $current.URL -or $alt.Host -eq $current.Host){continue}
        $requiresHeaders=([bool]$alt.UserAgent -or [bool]$alt.Referrer)
        $key=$current.Id+'|'+$current.Name+'|'+[string]$alt.URLHash
        $days=if($history.ContainsKey($key)){$history[$key].Count}else{0}
        $flaggedCurrent=($current.Host -match '(^|\.)(cinerama\.uz|skygo\.mn)$')
        $reason=if($idOccurrences.ContainsKey($current.Id) -and
            $idOccurrences[$current.Id] -gt 1){
            # Repeated IDs can denote variants. Current nightly history
            # cannot prove which variant produced a matching feed.
            'SHARED_CANONICAL_ID_REQUIRES_MAPPING'
        }elseif($requiresHeaders){
            'CLIENT_HEADERS_NOT_VERIFIED'
        }elseif(-not $flaggedCurrent){
            'CURRENT_SOURCE_NOT_MARKED_UNHEALTHY'
        }elseif($days -lt $RequiredDistinctDays){
            'NEED_MORE_DISTINCT_NIGHTS'
        }else{
            'READY_FOR_PROGRAMME_REVIEW'
        }
        $proposal=[pscustomobject]@{
            Channel=$current.Name
            ChannelId=$current.Id
            RecordKey=$recordKey
            CurrentURLHash=$currentHash
            CurrentHost=$current.Host
            CandidateHost=$alt.Host
            CandidateUrl=[string]$alt.URL
            CandidateUrlHash=[string]$alt.URLHash
            Source=$alt.Source
            PassingDistinctNights=$days
            RequiredDistinctNights=$RequiredDistinctDays
            HeadersNeeded=$requiresHeaders
            Status=$reason
            RealProgrammeVerified=$false
            CurrentStreamBrokenConfirmed=$false
            AutomaticPublicationAllowed=$false
        }
        if($reason -eq 'READY_FOR_PROGRAMME_REVIEW'){
            $eligible.Add($proposal)
        }else{
            $pending.Add($proposal)
        }
    }
}
# Propose at most three distinct current channels with independent upstream.
$selected=[Collections.Generic.List[object]]::new()
$seenChannels=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($candidate in ($eligible | Sort-Object PassingDistinctNights -Descending)){
    if($selected.Count -ge $MaxReplacements){break}
    if($seenChannels.Add($candidate.RecordKey)){$selected.Add($candidate)}
}
$previewRu=[Collections.Generic.List[object]]::new()
foreach($current in $ru){
    $key=IdentityKey ([string]$current.Id) ([string]$current.Name) (URLHash $current.URL)
    $candidate=@($selected | Where-Object {$_.RecordKey -ceq $key})
    if($candidate.Count -gt 1){
        throw "Ambiguous source swap for $($current.Name)"
    }
    if($candidate.Count -eq 1){
        $lines=@($current.Lines)
        $lines[$lines.Count-1]=$candidate[0].CandidateUrl
        $previewRu.Add([pscustomobject]@{
            Name=$current.Name;Id=$current.Id;Lines=$lines
        })
    }else{$previewRu.Add($current)}
}
$previewAll=@($ua)+@($previewRu.ToArray())
if($previewRu.Count -ne 47 -or $previewAll.Count -ne 131){
    throw 'Staged playlist counts changed unexpectedly'
}
foreach($p in $hashes.Keys){
    if((FileHash $p) -ne $hashes[$p]){throw "Active playlist changed while staging $p"}
}
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$dir=Join-Path $root ('replacement-preview-'+$stamp)
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$ruPreview=Join-Path $dir 'RU-47-REPLACEMENT-PREVIEW.m3u'
$allPreview=Join-Path $dir 'UA-RU-131-REPLACEMENT-PREVIEW.m3u'
$report=Join-Path $dir 'report.json'
Write-M3u $ruPreview $previewRu.ToArray()
Write-M3u $allPreview $previewAll
[IO.File]::WriteAllText($report,([ordered]@{
    Status='PREVIEW_ONLY_NO_PUBLICATION'
    CreatedUtc=[DateTime]::UtcNow.ToString('o')
    RuBaselineSHA256=$hashes[$ruFile]
    UaBaselineSHA256=$hashes[$uaFile]
    CombinedBaselineSHA256=$hashes[$combinedFile]
    CurrentRU=47;CurrentUA=84;CurrentCombined=131
    UA_HTTP_OptionsPreserved=$uaHttpHeaders
    NetworkHistoryRows=$historyLines
    MinimumPassingDays=$RequiredDistinctDays
    SharedCanonicalIds=@($duplicateIds)
    ChannelIdentity='Exact ID + title + original URL fingerprint'
    ReviewCandidates=@($selected)
    PendingCandidates=@($pending)
    ReportOnlyCandidates=@($eligible)
    RuPreview=$ruPreview
    CombinedPreview=$allPreview
    AutomaticPublishing='DISABLED'
} | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
foreach($p in $hashes.Keys){
    if((FileHash $p) -ne $hashes[$p]){throw "Active playlist changed while writing report $p"}
}
Write-Host '=== SOURCE SWAP CANDIDATES: HUMAN REVIEW REQUIRED ==='
$selected | Select-Object Channel,CurrentHost,CandidateHost,PassingDistinctNights |
    Format-Table -AutoSize
Write-Host '=== WAITING FOR ADDITIONAL EVIDENCE ==='
$pending | Group-Object Status | Select-Object Count,Name |
    Format-Table -AutoSize
Write-Host '=== PREVIEW SUMMARY ==='
[pscustomobject]@{
    CurrentRU=47;CurrentUA=84;CurrentCombined=131
    IndependentCandidateSwaps=$selected.Count
    PendingOrUnsupported=$pending.Count
    HistoryRows=$historyLines
    MinimumPassingDays=$RequiredDistinctDays
    SharedCanonicalIds=$duplicateIds.Count
    UaHttpOptionsPreserved=$uaHttpHeaders
    Report=$report
    StagedRU=$ruPreview
    StagedCombined=$allPreview
    RealProgrammeValidation='REQUIRED'
    PublishedFiles='UNCHANGED'
    AutoPublish='OFF'
} | Format-List
Write-Host 'IPTV V2 REPLACEMENT STAGING V2: COMPLETE (NOT PUBLISHED)'
