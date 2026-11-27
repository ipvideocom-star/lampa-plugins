#Requires -Version 7.0
# Local synthetic StreamGate integration test: no real streams or provider tokens.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$StreamGateExe)
$ErrorActionPreference='Stop'
$root=Join-Path $env:RUNNER_TEMP 'supertv-mock-pilot'
New-Item -ItemType Directory -Path $root -Force | Out-Null
$srcRoot=Join-Path $env:GITHUB_WORKSPACE 'tools\supertv'
Copy-Item -LiteralPath (Join-Path $srcRoot 'Serve-Local-Providers.ps1') -Destination $root -Force
$primary=[Collections.Generic.List[string]]::new()
$reserve=[Collections.Generic.List[string]]::new()
$primary.Add('#EXTM3U');$reserve.Add('#EXTM3U')
for($i=1;$i -le 1895;$i++){
  $sid='super-' + $i.ToString('x24')
  $header=('#EXTINF:-1 tvg-id="{0}" group-title="Mock",Mock Channel {1}' -f $sid,$i)
  $url=('https://example.invalid/stream/{0}.m3u8' -f $i)
  $primary.Add($header);$primary.Add($url)
  if($i -le 1349){
    $reserve.Add($header)
    $reserve.Add(('https://backup.example.invalid/stream/{0}.m3u8' -f $i))
  }
}
$pf=Join-Path $root 'Provider-Primary-PRIVATE.m3u'
$rf=Join-Path $root 'Provider-Reserve-PRIVATE.m3u'
[IO.File]::WriteAllLines($pf,$primary,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllLines($rf,$reserve,[Text.UTF8Encoding]::new($false))
$manifest=@{
  'Provider-Primary-PRIVATE.m3u SHA256'=(Get-FileHash $pf -Algorithm SHA256).Hash
  'Provider-Reserve-PRIVATE.m3u SHA256'=(Get-FileHash $rf -Algorithm SHA256).Hash
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'Manifest.json') -Encoding UTF8
$yaml=@'
config_version: 1
server:
  listen: "127.0.0.1:9187"
  public_base_url: "http://127.0.0.1:9187"
  shutdown_timeout: 10s
providers:
  - id: newsuper_primary
    type: m3u
    url: "http://127.0.0.1:9191/primary.m3u"
    priority: 10
    refresh_interval: 24h
    headers: {}
    allowed_hosts: ["127.0.0.1"]
    allow_private_networks: true
  - id: newsuper_reserve
    type: m3u
    url: "http://127.0.0.1:9191/reserve.m3u"
    priority: 20
    refresh_interval: 24h
    headers: {}
    allowed_hosts: ["127.0.0.1"]
    allow_private_networks: true
proxy:
  connect_timeout: 5s
  response_header_timeout: 10s
  idle_conn_timeout: 90s
  resource_ttl: 30m
  max_playlist_bytes: 4194304
cache:
  enabled: true
  segment_ttl: 30s
  fetch_timeout: 30s
  max_object_bytes: 16777216
  memory:
    max_size_bytes: 67108864
    max_entries: 3000
  disk:
    enabled: false
    directory: "data/cache"
    max_size_bytes: 268435456
    max_entries: 1000
stream:
  share_transport_streams: true
  subscriber_buffer: 16
  read_buffer_bytes: 32768
health:
  check_interval: 24h
  check_timeout: 5s
  failure_threshold: 2
  recovery_threshold: 1
  max_concurrent_checks: 1
observability:
  metrics_enabled: false
  pprof_enabled: false
  admin_listen: "127.0.0.1:9188"
xtream_output:
  enabled: false
  username: ""
  password: ""
logging:
  level: warn
'@
[IO.File]::WriteAllText((Join-Path $root 'Pilot-StreamGate.yaml'),$yaml,[Text.UTF8Encoding]::new($false))
$controller=Join-Path $srcRoot 'Run-NewSuperTV-Pilot-v0.2.ps1'
try {
  & $controller -Action SelfTest -Root $root -StreamGateExe $StreamGateExe
  & $controller -Action Start -Root $root -StreamGateExe $StreamGateExe
  $health=Invoke-RestMethod -Uri 'http://127.0.0.1:9187/healthz' -TimeoutSec 10
  if($health.channels -ne 1895 -or $health.sources -ne 3244 -or $health.healthy_providers -ne 2){
    throw "MOCK_MERGE_WRONG: channels=$($health.channels), sources=$($health.sources), providers=$($health.healthy_providers)"
  }
  Write-Host 'RESULT: MOCK_INTEGRATION_PASS; CHANNELS=1895 SOURCES=3244'
} finally {
  & $controller -Action Stop -Root $root -StreamGateExe $StreamGateExe
}
