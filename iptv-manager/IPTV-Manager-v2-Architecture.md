# IPTV Manager v2 — nightly source curation and safe rollouts

Updated: 2026-11-02. Deployment: Windows Server 2022 / PowerShell 7 / Lampac NextGen / Caddy / IPTV+ in Samsung Tizen and Android TV.

## Existing production — protect
- UA M3U: C:\IPTV-Manager\public\playlists\IPTV-UA.m3u (84 channels; 7 groups)
- RU M3U: C:\IPTV-Manager\public\playlists\IPTV-RU-Pilot-v1.m3u (47 channels; 3 groups)
- Combined M3U: C:\IPTV-Manager\public\playlists\IPTV-UA-RU-Pilot-v1.m3u (131 channels)
- Combined XMLTV: C:\IPTV-Manager\public\playlists\IPTV-UA-RU-EPG-Pilot-v1.xml
- Published paths must remain stable when a candidate is promoted.
- Existing EPG tasks and plugin policy remain untouched.
- Existing RU health 6-hour and discovery daily tasks are read-only; any later v2 task superseding the daily discovery must explicitly retire the old task only after validation.

## Findings from actual deployment
- Original discovery tested 260 of 530 indexed streams and promoted 33 based on manifest + 4KB segment only.
- 22 RU streams came from Cinerama. Seven unrelated channel entries resolved to the exact same HLS media playlist at one observation. The same browser later displayed a real channel and a promotional slate at different times. Neither manifest HTTP 200 nor media segment success proves correct programmes.
- New multi-source experiment tested 320 of 631 candidates, got 14 HLS-level successes, zero reliable ID matches to the 47 existing entries. Its matching relied too much on M3U tvg-id and source selection favoured source/order.
- 35 EXTVLCOPT lines in UA M3U must be preserved, as well as URL, id, groups and EPG.

## Sources, trust, and matching
- Primary canonical records: iptv-org API channels.json (id, name, alt_names, country, categories, is_nsfw, closed, replaced_by), streams.json (channel, URL, referrer, user_agent, quality, labels), feeds.json (feed and broadcast languages).
- Secondary curated collection: Free-TV/IPTV official free channels. This source also marks geoblocked/YouTube channel entries.
- Community collections (including ngrch) are discovery-only, never automatically promoted without independent verification and authorization to redistribute.
- Keep manual aliases for unresolved names. Exact canonical ID is strongest; country-aware aliases are next. Name-only fuzzy guesses require review; never automatically merge merely similar names.
- Record each stream with its origin/source, channel ID, independent upstream host, quality, referrer/user-agent, geo labels, last success, last failure, last media URL fingerprint, and explicit content confirmation status.
- Exclude sources that are not legitimately freely playable, protected behind subscriber-only accounts or DRM, and unsafe/inappropriate channels.

## Nightly pipeline — phases
1. Acquire: snapshot each signed or trusted source to a dated staging folder; note failure without erasing previous knowledge. Source-specific fetch limits, TLS/size/time restrictions.
2. Normalize: merge exact channel IDs and trusted aliases, preserve all existing channels and EPG IDs; build per-channel alternatives ranked by source trust, stability, host diversity, quality and required headers.
3. Probe: per-domain concurrency limits, bounded redirects, publicly routable hosts, HLS master/media/segment. Detect geo restriction, repeated errors, common media endpoints among *different* channel IDs. Do not infer real broadcast content from HTTP 200.
4. Verify over time: repeated checks separated by at least 10-15 minutes, including segment progression. Where suitable tooling is installed, sample 30-60 seconds and identify repeated static/slate loops; never label legitimate still images alone as failure.
5. Reconcile: keep last known good candidate until alternatives are independently healthy. Mark questionable streams quarantined (not deleted). Stage a proposed M3U and a diff. Preserve names, groups, id, EXTVLCOPT metadata, ordering.
6. Publish (future opt-in): only whitelisted canonical IDs, only verified replacements, rate-limit maximum changes per run (initial <=3 and <=5% of published channels), enforce UA/RU totals and EPG coverage bounds, backup to C:\ReservLampac, atomic local replace, HTTPS SHA check, automatic rollback; record each change.
7. Report: JSON + human-readable HTML with per-channel selected URL fingerprint, fallback counts, failure category, last-switch reason, and rollback links. Do not display sensitive query tokens.

## Operational safety
- Phase 1 catalog runs in preview mode and NEVER updates the live M3U/EPG.
- Candidate source addresses can include expiring keys; do not commit them to the public GitHub repo. Only script and documentation belong there.
- Start with 47 RU channels; retain 84 UA as control. Keep original groups (7 UA / 3 RU).
- Scheduling suggestion: overnight pipeline starting 04:10 Europe/Kyiv, after current 03:30 discovery, with single-instance lock and bounded maximum execution time; then replace the legacy discovery rather than running two indefinitely. RU 6-hour health check and both EPG jobs stay independently scheduled.
- Stage audit results for several nights before enabling automatic promotion. Never remove all streams because a source or ISP went offline.
- License restrictions must be respected, including simultaneous stream limits for paid sources.

## YouTube live
- Record legitimate official channel live-page URLs as source type YouTube, not as permanent .m3u8 URLs.
- The broadcaster must permit the proposed viewing/embedding workflow. YouTube signed playback URLs can expire; do not build the M3U list from scraped/ephemeral URLs or bypass restrictions.
- In IPTV+, a supported official web/embed playback option can be a separate integration later, without misrepresenting such links as stable HLS.
- Maintain separate availability/compatibility fields for YouTube and conventional HLS.

## Implementation milestones
M1: Catalog-v2 (read-only) downloads official iptv-org API + Free-TV and reports exact alternatives for the existing 47 RU channels.
M2: Canonical alias registry + quality gate + per-host validation and timed replay tests.
M3: Snapshot staging and reviewable diff with incremental promotion and rollback (disabled until validated).
M4: Replace legacy scheduled discovery with nightly v2 task, log retention and a report page.
M5: Optional YouTube official live-source adapter and approved paid/multistream adapters.
