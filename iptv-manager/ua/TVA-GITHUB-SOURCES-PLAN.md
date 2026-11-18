# TVA GitHub as a durable discovery feed for existing IPTV Manager

**Status:** SOURCE REGISTRY ONLY (review/staging). No server installation or production changes made by this PR. Do not create a second IPTV service, a new scheduled task, or a new M3U output.

## Verified source facts (18 Nov 2026)
- Upstream repo: https://github.com/slava-67/TV/tree/IPTV, default branch `IPTV`.
- At inspection, upstream tree contained **19 M3U files and no published builder scripts or GitHub Actions**. Therefore the upstream author's internal sourcing and automation method is **unknown**; descriptions of a purported algorithm would be speculation.
- Latest observed Git commit: `f4385f9be707...` at **2026-11-18 10:30:54 UTC**, labeled `Add files via upload`; other commits update M3U files.
- A close inventory of four dedicated lists (not a playback check):
  - `ua.m3u`: 275 `#EXTINF` entries; 2 Setanta entries; has EPG header.
  - `sport.m3u`: 182 entries; at least 8 Setanta-labelled entries across different upstream hosts; some are marked TEST or VPN; has EPG header.
  - `kids.m3u`: 56 entries; has EPG header.
  - `poznavatelni.m3u`: 88 entries; has EPG header.
  - **601 entries, not 601 unique working channels.** Overlap, multiple variants, non-UA content, expired links and testing groups are possible. EPG in the upstream header is not proof of a usable complete current guide.
- The user's current published `IPTV-UA-NEW.m3u` baseline remains 158 channels; user's audit found 53 with live EPG. Setanta is not in the known UA baseline inventory. Do not change published playlist on the strength of these listings.

## Files
`tva-github-sources-v1.json` contains **all 19 source file URLs**, grouped by candidate priority:
- **UA_PRIORITY (4)**: dedicated `ua`, `sport`, `kids`, `poznavatelni` feeds.
- **DISCOVERY_ONLY (15)**: broad catalogs, `tva1..tva5`, films, provider, VPN-related catalogs. These are *not* in the primary UA catalog by default. No deletion or blanket rejection; they are searchable for confirmed replacements later.

The manifest references only public *M3U source file* URLs. Do not commit its downloaded stream entries: they may embed time-limited access tokens or provider-specific permissions.

## Integrate into the existing Windows 2022 manager (implementation gate)
The current installed provider has previously been identified as:
`C:\IPTV-Manager\Tools\UA-AutoCatalog\v3\TVA-FeedProvider.psm1`.

Use the existing **`IPTV-Manager-v2-Nightly`** task. Extend the existing TVA provider, not a new PowerShell service/cron/one-off script.

1. Read the manifest as an allowlisted external source registry; reject unknown URL origins/branches, redirects to private hosts, non-M3U contents, oversized files, invalid encoding, and malformed EXTINF pairs.
2. For each source record store (privately, on server) last successful commit/ref, file SHA256, fetch status, fetch time, `#EXTINF` count, and last-good raw snapshot. If one source fails, preserve last-good state; do **not** demote all channels as dead.
3. Parse records with all metadata (`tvg-id`, normalized name, quality suffix, original group, EPG header, logo, source), and retain **every alternative as a candidate**, not a duplicate visible row. Deduplicate only after verified channel identity; different broadcasts/time-shifts must not be collapsed.
4. Correlate candidates to current 158 Ukrainian channels using exact canonical channel identity, then approved aliases. Prioritize restoring missing **Setanta Sports 1, 2, UA, and +** only where source is correctly identified and actually plays; group `TEST` or `VPN` must be reviewed rather than blindly promoted. Avoid use of access-key-like URLs not authorized by the provider.
5. Run bounded quality checks **on Windows 2022 from the actual network**: first validate HLS variant/media manifest and segment continuity, then short video/audio decode for a small changed set. HTTP 200 or video packets alone cannot establish correct channel content. Prefer user's Samsung-playback observation where available; minimize TV re-tests.
6. Produce private proposed candidate table, SHA256 and URL-free audit CSV. Compare playlist inventory (channel counts, unique IDs, metadata), preserve all currently working sources and EPG mappings, and back up to `C:\ReservLampac`.
7. Stage only approved changes with private 158+ delta M3U and effective stream hashes; preserve last-good and **AutoPublish OFF**. Only publish after explicit confirmation and rollback plan. No plugin/Caddy changes unless separately needed.
8. Existing six-hour task `IPTV-Manager-EPG-UA-6h` owns Ukrainian XMLTV; the Github feeds' `url-tvg` headers are evidence candidates, not a command to replace the separate UA EPG.

## Independent operation if the author stops updating
- The repo may stop updating, vanish, change formats, or cease to contain working links. We cannot replicate unknown private feed collection merely by copying its current files.
- We can still retain a **last-good snapshot**, preserve working streams, collect independent source candidates from already configured providers, and use bounded checks to select alternate sources. Warn on feed staleness or significant degradation via the planned unified IPTV Watchdog, without triggering an automatic production rewrite.
- Never claim 24/7 uptime, compatibility, licensing/distribution rights, or a working Setanta stream until validated.

## Rollout gates
1. Review this registry and inspect the installed `TVA-FeedProvider.psm1` implementation before patching it. This provider file is not in this public repo and should not be overwritten from assumptions.
2. Prepare a **diff against the actual installed provider**, plus read-only intake test and rollback/backup. Avoid another separate installer and task.
3. Stage a small quality-assured UA delta (Setanta first, then broken channels) before publishing; retain `IPTV Украина` and `Супертелевидение` separation.
