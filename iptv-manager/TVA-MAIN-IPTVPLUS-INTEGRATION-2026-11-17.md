# TVA → UA AutoCatalog → main IPTV+ | integration status (2026-11-17)

## Goal
Deliver a stable Ukrainian/Russian main playlist in the existing `iptv_plus` Lampa client on Samsung Tizen, with Ukrainian EPG, monitored backups, and no manual TV URL entry. Preserve the separate `iptv_plus_19` (3,276 entries) and `iptv_plus_14` (2,710 entries), and existing RU source policies.

## Current installation (Windows Server 2022)
- TVA primary M3U endpoints: `https://tva.org.ua/ip/sam/ua.m3u`, `https://tva.org.ua/ip/sport.m3u`, `https://tva.org.ua/ip/sam/poznavatelni.m3u`, `https://tva.org.ua/ip/sam/kids.m3u`.
- Author's GitHub mirror: `https://raw.githubusercontent.com/slava-67/TV/IPTV/{ua,sport,poznavatelni,kids}.m3u` (site/mirror may differ temporarily).
- `C:\IPTV-Manager\Tools\UA-AutoCatalog\v3\TVA-FeedProvider.psm1` installed and synchronized. Tracks SHA256 and last-good copies, no publication.
- `Invoke-TVA-Refresh-Nightly-v1.ps1` invoked by the EXISTING `IPTV-Manager-v2-Nightly` task around 04:35 Europe/Kyiv. Existing task configuration was unchanged. First scheduled run after the hook installation still requires observation.
- TVA candidate audit: 615 feed entries, 89 reviewed identity candidates, 80 distinct ffprobe runs, 72 positive video-packet observations; one positive had only a single packet. Twelve positive URLs have exact name matches for nine IDs. A positive ffprobe observation is NOT proof of channel identity, 24/7 uptime, Samsung support, or distribution rights.
- Private URLs and access tokens remain exclusively on the server; never commit them here.
- Baseline UA v3 catalog count 194 vs later 224 needs reconciliation before publishing.
- UA 158-channel verified-video preview is STAGED. EPG v2.6 has 67 shadow channels but 16 questionable EPGShare mappings are held (8 suspect regional, 3 generic, 5 other review); do not publish this XML unchanged.

## Continuous reserve registry, v1
The installable PowerShell package `TVA-ReserveRegistry-v1-Lampa-Readiness.zip` creates a local registry that correlates the prior reviewed row IDs with the private audit file, ffprobe report and latest TVA snapshots by exact stream URL SHA256, feed and channel name. It is hooked into the existing nightly TVA runner; no new Scheduled Task. Changed/missing URLs are held for re-verification, aliases held for content identity checks. All registry files remain local; only URL-free diagnostics may be shared. Installer must back up the runner to `C:\ReservLampac\IPTV-Manager\TVA-ReserveRegistry` and pass offline selftests.

## Next release gates
1. Observe the first actual nightly TVA refresh and registry reconciliation; revalidate stale/missing URLs.
2. Reconcile canonical 194 vs 224, and lock the 158 verified main-UA IDs; do not conflate URL entries with canonical channels.
3. Produce filtered, current/future-only UA XMLTV using reviewed high-confidence mappings; schedule through the existing `IPTV-Manager-EPG-UA-6h`, without a new task.
4. Stage a new *main IPTV+* combined UA/RU release with stable HTTPS URLs and unchanged #19/#14 clients. Validate MIME/Caddy/TVG-ID/EPG mapping, SHA256, backups, and rollback.
5. After explicit user approval and Samsung acceptance, promote staged main release atomically; never auto-publish unreviewed sources.

## Non-negotiable safety
Do not change production M3U/EPG/Caddy/Lampac services or Samsung plugin policy without review/approval; no automatic switching on new TVA sources; keep verified last-good; no extra Windows tasks; bounded network and media tests; do not merge separate RU EPG into UA EPG.