#requires -Version 7.0
# IPTV Manager v2 — shortlist successful RU alternatives by CHANNEL and HOST.
# Input: one catalog and one network audit report. No publication, no scheduling.
# This is not a proof of the correct programme or a safe automatic swap.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$CatalogPath,
  [Parameter(Mandatory=$true)][string]$AuditReportPath
)
$ErrorActionPreference='Stop'
$root='C:\ReservLampac\IPTVPlus\CatalogV2'
$ru='C:\IPTV-Manager\public\playlists\IPTV-RU-Pilot-v1.m3u'
$base=(Resolve-Path -LiteralPath $root -ErrorAction Stop).ProviderPath
$cat=(Resolve-Path -LiteralPath $CatalogPath -ErrorAction Stop).ProviderPath
$auditPath=(Resolve-Path -LiteralPath $AuditReportPath -ErrorAction Stop).ProviderPath
foreach($p in @($cat,$auditPath)){
    if(-not $p.StartsWith($base+[IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)){
        throw "Input must be within $root"
    }
}
if(-not (Test-Path -LiteralPath $ru -PathType Leaf)){throw 'RU published playlist missing'}
$ruHash=(Get-FileHash -LiteralPath $ru -Algorithm SHA256).Hash
$catalog=@(Get-Content -LiteralPath $cat -Raw -Encoding UTF8 |
    ConvertFrom-Json -AsHashtable)
$audit=Get-Content -LiteralPath $auditPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -AsHashtable
$catalogReportPath=Join-Path (Split-Path $cat -Parent) 'report.json'
$catalogReport=Get-Content -LiteralPath $catalogReportPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -AsHashtable
if($catalog.Count -ne 47 -or
   $catalogReport.Status -ne 'READ_ONLY_CATALOG' -or
   $catalogReport.BaselineSha256 -ne $ruHash -or
   $audit.Mode -ne 'NETWORK_ONLY_NOT_CONTENT_VERIFIED' -or
   $audit.ProductionRUHash -ne $ruHash -or
   $audit.CatalogPath -ne $cat){
    throw 'Audit/catalog/live RU baseline mismatch; cannot shortlist'
}
$checked=@($audit.Results)
if($checked.Count -lt 1 -or $checked.Count -gt 500){throw 'Invalid audit results count'}
function Safe-Text([string]$s) {
    return ($s -replace '[\r\n"]',' ').Trim()
}
$shortlist=[Collections.Generic.List[object]]::new()
$summary=[Collections.Generic.List[object]]::new()
$rows=[Collections.Generic.List[string]]::new()
$rows.Add('#EXTM3U')
foreach($channel in $catalog) {
    $alternatives=@($channel.Alternatives)
    $success=@(
        $checked | Where-Object {
            $_.Id -eq $channel.Id -and
            $_.Channel -eq $channel.Name -and
            $_.Status -eq 'HLS_PROGRESS_OBSERVED' -and
            $_.MediaUriHash
        }
    )
    $available=[Collections.Generic.List[object]]::new()
    foreach($result in $success){
        $matching=@(
            $alternatives | Where-Object {
                $_.URLHash -eq $result.UrlHash -and
                $_.Host -eq $result.Host -and
                $_.Source -eq $result.Source
            }
        )
        if($matching.Count -ne 1){throw "Missing or ambiguous catalog candidate for $($channel.Name)"}
        $match=$matching[0]
        if($match.URL -eq $null -or $match.URL -eq ''){throw 'Empty candidate URL'}
        $score=100
        if($result.Host -cne $channel.CurrentHost){$score+=25}
        if(-not $match.UserAgent -and -not $match.Referrer){$score+=10}
        if([int]$result.Segments -ge 6){$score+=5}
        # Internal network ranking only, NOT broadcaster/content verification.
        $available.Add([pscustomobject]@{
            Channel=$channel.Name
            CanonicalId=$channel.Id
            CurrentHost=$channel.CurrentHost
            AlternativeHost=$result.Host
            Source=$result.Source
            Url=$match.URL
            UrlHash=$result.UrlHash
            MediaUriHash=$result.MediaUriHash
            Score=$score
            HeadersRequired=([bool]$match.UserAgent -or [bool]$match.Referrer)
            UserAgent=[string]$match.UserAgent
            Referrer=[string]$match.Referrer
            HlsProgressSeen=$true
            RealTVVerified=$false
            ConsecutiveNightsVerified=0
        })
    }
    $seenHost=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $chosen=[Collections.Generic.List[object]]::new()
    foreach($candidate in ($available | Sort-Object Score -Descending)){
        if($seenHost.Add($candidate.AlternativeHost)){
            $chosen.Add($candidate)
        }
        if($chosen.Count -ge 2){break}
    }
    $distinctHosts=@($available | Where-Object {
        $_.AlternativeHost -cne $channel.CurrentHost
    } | Select-Object -ExpandProperty AlternativeHost -Unique)
    $summary.Add([pscustomobject]@{
        Channel=$channel.Name
        CurrentHost=$channel.CurrentHost
        WorkingURLs=$available.Count
        IndependentHosts=@($distinctHosts).Count
        ReviewSelections=$chosen.Count
    })
    $position=0
    foreach($candidate in $chosen){
        $position++
        $shortlist.Add($candidate)
        $display=Safe-Text ("$($channel.Name) [ALT $position - $($candidate.AlternativeHost)]")
        $id=Safe-Text ([string]$channel.Id)
        $rows.Add('#EXTINF:-1 tvg-id="'+$id+'" group-title="RU / Альтернативы (тест)",'+$display)
        if($candidate.UserAgent){
            $rows.Add('#EXTVLCOPT:http-user-agent='+($candidate.UserAgent -replace '[\r\n]',' '))
        }
        if($candidate.Referrer){
            $rows.Add('#EXTVLCOPT:http-referrer='+($candidate.Referrer -replace '[\r\n]',' '))
        }
        $rows.Add($candidate.Url)
    }
}
if((Get-FileHash -LiteralPath $ru -Algorithm SHA256).Hash -ne $ruHash){
    throw 'Published RU playlist changed while ranking'
}
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$folder=Join-Path $root ('shortlist-'+$stamp)
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$reviewM3u=Join-Path $folder 'RU-ALTERNATIVES-REVIEW-NOT-PUBLISHED.m3u'
$reviewJson=Join-Path $folder 'RU-candidate-shortlist.json'
$summaryJson=Join-Path $folder 'report.json'
$nl=[Environment]::NewLine
[IO.File]::WriteAllText($reviewM3u,($rows -join $nl)+$nl,
    [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($reviewJson,($shortlist | ConvertTo-Json -Depth 9),
    [Text.UTF8Encoding]::new($false))
$covered=@($summary | Where-Object {$_.WorkingURLs -gt 0})
$remaining=@($summary | Where-Object {$_.WorkingURLs -eq 0})
[IO.File]::WriteAllText($summaryJson,([ordered]@{
    Status='SHORTLIST_NETWORK_ONLY_NO_PUBLICATION'
    ReportedUtc=[DateTime]::UtcNow.ToString('o')
    RuBaselineSha256=$ruHash
    InputCatalog=$cat
    InputNetworkAudit=$auditPath
    SourceChannels=47
    WorkingURLs=@($checked | Where-Object Status -eq 'HLS_PROGRESS_OBSERVED').Count
    CoveredChannels=$covered.Count
    ChannelsWithoutPassingAlternatives=$remaining.Count
    ReviewEntries=$shortlist.Count
    ReviewM3u=$reviewM3u
    ShortlistJson=$reviewJson
    RankedChannels=@($summary)
    AutomaticPublish='DISABLED'
} | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Host '=== CHANNEL-CENTRIC SUMMARY (NOT RAW URL COUNT) ==='
$summary | Where-Object {$_.WorkingURLs -gt 0} |
    Sort-Object WorkingURLs -Descending |
    Format-Table Channel,WorkingURLs,IndependentHosts,ReviewSelections,CurrentHost -AutoSize
Write-Host '=== NETWORK SHORTLIST ==='
[pscustomobject]@{
    BaselineRU=47
    ChannelsWithWorkingAlternatives=$covered.Count
    ChannelsStillWithoutWorkingAlternatives=$remaining.Count
    ShortlistedUniqueHostAlternatives=$shortlist.Count
    Report=$summaryJson
    ReviewPlaylist=$reviewM3u
    ShortlistJson=$reviewJson
    Publication='NONE'
    AutomaticReplacement='DISABLED'
} | Format-List
Write-Host 'IPTV RU ALTERNATIVE SHORTLIST: COMPLETE (NOT PUBLISHED)'
