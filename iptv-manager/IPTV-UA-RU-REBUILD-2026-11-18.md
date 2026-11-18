# 18 NOV 2026 18:17 — UA CATEGORY v1.1 STAGING COMPLETE / NEXT RELEASE GATE

**User Windows PowerShell results:** `Invoke-UA-Manager-Review-v1.1.ps1 -StageCategories -AdditionalEpgAudit` SELFTEST PASS; original M3U SHA256 `EE71310DDE9C890EF8854A035473C197340D5610047732D963D284B10802867E`; 158 channels, 0 duplicate IDs, 131 rule matches, **43 category-only group moves privately staged** at `C:\IPTV-Manager\data\ua-autocatalog\v3\manager-review\review-20261118-181702-a260cf5b\IPTV-UA-CATEGORIES-STAGED.m3u` with manifest `UA-CATEGORY-STAGE-REPORT.json`. UA EPG remains 53/158, missing 105; TVA snapshot 13.7 hours old. No public M3U/EPG/Policy/RU changed.

**Important release blocker discovered and addressed in prepared guarded release script:** existing `C:\IPTV-Manager\Tools\UA-Managed\Update-UA-Managed-EPG-v1.ps1` `Assert-OnlyEPGHeaderDiff` compares the original verified-source M3U and public M3U line-by-line beyond EXTM3U header. Publishing only changed group-title/EXTGRP would otherwise break EVERY six-hour EPG update. The stage-only candidate MUST NOT be published in isolation. A versioned guarded release helper `Publish-UA-Categories-Guarded-v1.ps1` is prepared for local operator execution; it verifies old public SHA, stage report/candidate SHA, exactly 43 `group-title` moves, all other lines unchanged, patches only the EPG updater's source-comparison guard to tolerate group metadata while refusing every change to IDs, streams, labels and other metadata, parses the patched updater, function-tests it against candidate, backs up both files under `C:\ReservLampac\IPTV-Manager\UA-Managed\ua-categories-*`, replaces both atomically, HTTPS SHA verifies M3U, and rolls back on failure. No user-server application confirmed; no scheduled tasks created. Do NOT claim the category release completed until successful operator log.

**EPG optional-source problem:** `https://iptv-org.github.io/epg/guides/ua/tvgid.ua.epg.xml` returns HTTP 404. Reviewer now correctly states `AdditionalEpgAuditStatus=UNAVAILABLE`, meaning 0 additional matches is NOT evidence of exhaustion. Replace with a tested live candidate (FreeEPG / XMLTV service etc.) in a future read-only audit; keep exact-ID and identity gates, no auto merge. Existing EPGShare/OpenEPG remain unchanged.

**Main acceptance:** Samsung Lampa user tested approximately 20 UA streams, all worked despite Chrome errors; do not demote Samsung-working streams due to Chrome-only HLS. Independent IPTV #19, #14 and RU untouched; playlist AutoPublish OFF.

---

# UA MANAGER AUDIT — ACTUAL 2026-11-18 RESULTS, AND V1.1 STAGING

**User server report** `review-20261118-180142-b46a9914`, read-only:
- 158 published UA channels; 9 source groups; duplicate tvg-ids **zero**.
- 127 exact IDs recognized by category rules v1.0, **39** group changes proposed; 31 IDs remain unchanged for manual content review.
- Current group distribution: Загальні 60, Новини 15, Кіно та серіали 20, Спорт 12, Пізнавальні 8, Розваги 16, Регіональні 9, Дитячі 6, Музика 12.
- Proposed v1.0 grouping: Загальні 33, Новини 13, Кіно та серіали 22, Спорт 12, Пізнавальні 18, Розваги 16, Регіональні 25, Дитячі 6, Музика 13.
- EPG current and next-7-days **53/158**; missing **105**, including regional 22, movies 18, main 18, knowledge 10, music 10, news 8, entertainment 8, sport 8, kids 3.
- TVA provider snapshot exists, 13.4 hours old. No streams probed, M3U and EPG unchanged, no policy/RU changes.
- Optional third XMLTV source `https://iptv-org.github.io/epg/guides/ua/tvgid.ua.epg.xml`: `AdditionalExactEpgCandidates=0` **does not indicate a successful search**, because `AdditionalCandidateCsv` was empty. The v1 diagnostic swallowed download/parse failure; this is corrected in the staged v1.1 module to distinguish `CHECKED`, `UNAVAILABLE`, `NOT_REQUESTED`.
- Uploaded `IPTV-Samsung-Audit-257(1).txt` contains historical **257-channel combined UA/RU data**, and is NOT the acceptance or current-playback ledger for the newly published 158-UA M3U; do not mix counts or use it to alter RU.

**Category policy updated in GitHub:** `iptv-manager/ua/UA-Category-Overrides-v1.json`, version 1.1.0, 131 exact channel IDs. Four added unambiguous health/religious-educational mappings `366TV.ua`, `EWTNUkraine.ua`, `Glas.ua`, `HopeChannelUkraine.ua` → Пізнавальні. With the supplied current 158-UA snapshot this predicts **43 category-only changes**, 27 IDs unchanged/unclassified. This is a candidate **NOT YET applied** to production playlist.
- Staged v1.1 revision of the existing manager review module has optional `-StageCategories` plus mandatory previous playlist SHA; it privately produces a candidate M3U changing only `group-title` and `#EXTGRP` metadata with per-line integrity checks, never publishes. No new Scheduled Task. Client-side UI category correction is already deployed and independent of source M3U.
- Next gate: validate staging candidate and diff, then request/perform safe metadata-only replacement under user approval while preserving original stream URLs, EPG, existing #19/#14 and AutoPublish OFF. EPG source discovery and TVA alternatives require separate QA and content review before any merging.

---

# PROGRESS 2026-11-18 — Stage UA category and EPG readiness (no publication)

Samsung user test: about 20/20 sampled channels play, including Chrome-failing sports. Preserve 158 M3U and do not treat browser failure as source failure.

Created centralized exact-ID policy: iptv-manager/ua/UA-Category-Overrides-v1.json. Rules include 127 of 158 known IDs across the existing nine categories; 31 ambiguous IDs remain unchanged. Examples ICTV/ICTV2 -> General, Dacha/Rybalka/Trofei -> Knowledge; the TV marathon is News; separate Maincast Sport/Cybersport. Source names are preserved and no client/plugin settings altered by this staging.

Created documentation: iptv-manager/ua/README.md. Prepared a permanent read-only audit bundle UA-Manager-Review-v1-READONLY.zip for local server execution. The tool reads the *actual published* UA M3U and current EPG, reports URL-free per-channel current/proposed categories, live/future guide, missing guide, TVA provider freshness, and optionally stages exact-ID candidates from tvgid.ua XMLTV. No outputs are live/published; no automatic guide merge or stream replacement.

Next step after user-server audit: inspect all 158 category diffs (not just an approximate offline list), review potential true EPG matches for current 105 uncovered channels, then stage coherent source changes to existing AutoCatalog and EPG 6h pipeline. After successful selftests, integrate UA watchdog in existing Nightly task; no duplicate Windows Scheduled Tasks. AutoPublish OFF, user-approval required for public stream/EPG/Caddy changes. #19/#14 and RU unchanged.

---
# UA SAMSUNG ACCEPTANCE UPDATE AND CATEGORY RULES — 2026-11-18

**Samsung acceptance evidence:** user personally tested about 20 Ukrainian streams in Samsung Lampa and found all played, including many sport channels that fail in Chrome. The previous statement that 158-UA was a failed playback release **is no longer valid globally**; Samsung is the primary acceptance client, Chrome is an auxiliary client whose HLS/CORS/network behavior differs. This test DOES NOT demonstrate all 158 play continuously or that Chrome has been fixed. Keep Chrome `manifestLoadError` as a separate browser-compatibility backlog; do not remove working Samsung channels merely because of Chrome-only failures.

**Category corrections implemented in existing global plugin**, `iptv-plus/iptv-ua-managed-v1.3.1.js` (GitHub commit `3d686566b6575f250832bda884fd6192a6369b15`) using `correctUaChannelGroups()` immediately after M3U parse, prior to grouping. It resolves the EXISTING nine source groups by matching the actual available group labels; applies exact canonical EPG channel IDs plus conservative whole-name matches:
- Main broadcast: 1+1, 2+2, ICTV, ICTV2, Inter, STB, Novyi Channel, TET, Pershyi to existing `Загальні` group.
- Knowledge/lifestyle: Dacha, Rybalka, Trofei, Nauka, Terra, Fauna, KusKus plus unambiguous hunting/fishing names to existing `Пізнавальні` group.
- Nonmatching channels retain their source `group-title`; 1+1 Марафон remains News; sports remain sports.
- No new categories, stream changes, tvg-id changes, source URL changes, EPG edits, M3U publication, Policy Server edits or Windows task edits. Synthetic tests: 12 channels, 8 expected group changes, idempotent rerun 0, all non-group fields unchanged. Actual full 158-channel classification diff not yet tested because model has no on-server M3U access.

**Source-of-truth follow-up:** UI rule is immediately available in the JS plugin source, but old UA AutoCatalog `Group-UA()` on the Windows server still needs durable category correction when its source script is available for editing. Avoid blind changes to a server-only file; source categories need one canonical mapper or shared rule table in IPTV Manager and a report of all 158 categories without stream URLs. Do not infer source categories from a handful of names. New TVA channels should pass this categorization gate on ingestion.

**Other unchanged scope:** global to all valid UIDs; IPTV #19 and #14 untouched, RU on hold. 53/158 current EPG coverage remains a separate improvement project; nightly provider feed update is not automatic stream publication. Chrome HLS errors are plausible browser CORS/mixed-content/network/player differences; need isolate from Samsung native/media playback before altering streams.

---

# CRITICAL UA RELEASE QA FAILURE — 2026-11-18, user Chrome playback test

**User evidence:** the globally delivered IPTV Украина now exposes 158 channels in Chrome; only 1+1 observed working by user, many other channels fail with HLS `manifestLoadError fatal true`. Treat this release as **FAILED playback acceptance** even though plugin/EPG deployment succeeded. Do not advertise 158 "working" or schedule auto-promotion.

Sports read-only audit: 12/12 HTTP200/206, 7 with m3u8 signature but no tested child manifests or segments, 5 without valid HLS signature (Maincast Sport, Sport1, Sport2, Sport3, Suspilne Sport), one XSport missing browser-Origin CORS; importantly **ffprobe was NOT FOUND** and 0/12 had video tested in the current audit. Further check for mixed-content HTTP stream URLs under HTTPS Lampa, browser-origin mismatch, CORS on variant/segments, signed expired URLs, geo restrictions, media decoder compatibility, alternate URLs and content identity across **all 158**, not just sports. HTTP200 and CORS header on one response are not playback proof.

**Confirmed categorization defect from `Invoke-UA-AutoCatalog-v3.ps1`:** `Group-UA()` uses a name+original-group regex and defaults unmatched to `Загальні`, with no words for `Дача`, fishing or hunting. `Дача` belongs in `Пізнавальні`; hunting/fishing likewise under `Пізнавальні` per user's preference. Need explicit category overrides, tests and a review of all 158 before next publication. The verified-preview builder COPYied `$ch.Category` from AutoCatalog unchanged. Do not patch only public M3U: correct source category rules then stage/release cleanly.

**Change policy:** existing public URL, EPG, other plugin settings (#19, #14) and RU remain unchanged until all-stream compatibility gate and reviewed category diff pass; user permits removal of obsolete trial IPTV+ registrations, but keep requested #19/#14. Playlist AutoPublish remains OFF. Develop an integrated durable manager check/watchdog rather than more standalone scripts. Improve verified-channel QA to include browser-valid HTTPS, master and segment fetch, actual media packet decode and repeat probes; quarantine the others.

---

# UA SPORTS PLAYBACK INCIDENT — 2026-11-18

**Observed on Chrome Lampa by user:** the new global `IPTV Украина` menu now loads a 158-entry playlist; `1+1` plays, but multiple sport channels fail: Dynamo Kyiv TV, DV Sport (user-reported name), Sport 3 and Maincast Sport; browser HLS player reports `manifestLoadError` and `fatal: true`. No Samsung testing requested.

**Root problem in promotion criteria:** the 158 entries were selected by `ffprobe` seeing video packets from the Windows Server. That is not proof of live browser HLS manifest + segment access, correct CORS/referrer/UA headers, content identity, or ongoing availability. Never claim 158 playable.

**Relevant prior TVA source audit:** Dynamo Kyiv TV HD (1080p/h264, 25 video packets), Sport 3 Ukraine (1080p/h264, 24 packets) and Maincast Кіберспорт (1080p/h264, 50 packets) have viable *candidates*, but only pending channel-identity and Lampa playback checks. In particular Maincast Кіберспорт ≠ necessarily Maincast Sport. Do not silently swap or promote.

**Immediate next action:** Run one URL-free **batch** sports diagnostic against existing `C:\IPTV-Manager\public\playlists\IPTV-UA-NEW.m3u`, including HTTP status and content type, manifest signature, browser Origin/CORS headers, bounded ffprobe metadata. Separate server-only errors from Chrome CORS and missing segment issues. Never expose stream URL/query token in chat/logs. Preserve stable working channels, EPG, #19/#14 and all RU. Avoid manual channel-by-channel Samsung tests.

**Required publishing gate going forward:** provisional stream selection → timed repeat media/manifest probes → HTTP/CORS/media segment check from actual client origin → content identity review → release-stage QA + rollback → explicit approval before changing public UA M3U. Maintain continuous alternative monitoring and last-good. AutoPublish remains OFF. EPG 53/158 is a separate coverage issue.

---

# 18 NOV — CHROME LEGACY-REGISTRY CONFLICT AND FIX

User Chrome Lampa showed **17 registered and 17 loaded IPTV-related scripts**, including both `iptv-plus-v1.2.0-settings-fix.js` / `iptv-plus-v1.2.1-auto-refresh.js`, many legacy autosetup scripts pointing to `IPTV-UA-RU-Relay-v02-257.m3u`, both independent IPTV #19/#14, and the new `iptv-ua-managed-v1.3.1.js` loaded last. The old script initializes global `window.lampa_iptv_plus_ready` first, so the new IPTV Украина plugin is skipped by its duplicate guard.

**Fix deployed to existing public GitHub Pages plugin** `iptv-plus/iptv-ua-managed-v1.3.1.js` on 18 Nov (commit `e5ef86876c06735852ff2d115353cb9572597718`). A safe, idempotent migration executes BEFORE that guard and removes ONLY 10 exact obsolete `iptv-plus/` filenames and the retired `iptv-compare/iptv-samsung-compare-loader-v12.js` from each client's `Lampa.Plugins` registry. It backs up entries in local Lampa Storage key `iptv_ua_legacy_plugins_backup_20261118`. It never removes independent #19/#14 URLs, Community19 loaders, plugin-manager-test-v2.js or unrelated plugins; does not touch UID policy or IPTV M3U/EPG. Verified with JS syntax check and mocked Lampa.Plugins get/remove tests. Since old scripts already executed on the current page, **restart Lampa, allow new source to load and migrate local registry, then restart again** for new primary code to win. On Chrome use hard refresh to bypass cache when appropriate. Server policy may still re-register legacy entries; if regression occurs, inspect policy/extra auto-registration source before more modifications. No user device acceptance yet.

---

# ACTUAL USER-SERVER INSTALL RESULT — 18 NOVEMBER 2026 14:55 KYIV

**v1.2 UA Managed Cutover: SUCCESS per PowerShell installation log.** First primary `iptv_plus` policy entry globally replaced by `IPTV Украина`; primary UID exclusion list empty. Policy API synthetic UID tests `UA_GLOBAL_VERIFY_01` and `UA_GLOBAL_VERIFY_02` passed. All unrelated policies and separate IPTV #19 and #14 preserved. No RU playlists altered; no new Scheduled Tasks; AutoPublish OFF.

New first-playlist endpoints:
- `https://lampa.v6.army/iptv/playlists/IPTV-UA-NEW.m3u` — private-source-derived 158 channel, 9-category UA snapshot (video-packet observed earlier; Samsung verification pending).
- `https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-NEW.xml` — newly generated reviewed EPG from EPGShare and OpenEPG with 53/158 channels having current program, 4,528 current/future entries, historical-only channels 0. All 53 have 'LiveNow=True' at time of generation; 105 lack mappings.
- Existing task `IPTV-Manager-EPG-UA-6h` was extended with guarded EPG updater; next actual scheduled refresh still needs log confirmation.
- Successful backup directory: `C:\ReservLampac\IPTV-Manager\UA-Managed\cutover-20261118-145546-1de765ce`.

**Strict status:** This is a server-side deployment success, not yet acceptance on Samsung/Android. Direct public URL fetch was unavailable to ChatGPT, so no independent external HTTPS validation; installer-reported results are the current evidence. NIGHTLY TVA feed refresh and automatic playlist channel promotion are separate; playlist AutoPublish remains OFF. Do not claim daily M3U rebuild or full EPG coverage. Setanta Sports candidate verification still pending. Before any future upgrade preserve IPTV #19/#14, and do not start RU work without user-supplied sources.

---
# 2026-11-18 CUTOVER FAILURE AND CORRECTIVE PACKAGE v1.2

**Actual v1.1 execution:** offline selftest PASS, preflight PASS (158 UA channels, 9 groups, primary `iptv_plus`, global exclusion list empty), EPGShare and OpenEPG downloads OK, then install aborted. Exact message: "Only the private UA Verified preview folder is accepted as M3U input." Installer printed rollback success but the post-rollback server state has not been independently verified.

**Root cause:** `Update-UA-Managed-EPG-v1.ps1` incorrectly passed the new public `IPTV-UA-NEW.m3u` into a shadow EPG generator intentionally restricted to `C:\IPTV-Manager\data\ua-autocatalog\v3\verified-preview\...`.

**Corrective artifact:** `UA-Managed-Cutover-v1.2-ALL-UIDs-FIX.zip`; SHA256 `1FB453896AAE84E2622EE57A5B4F5305A081686A87039C20C225FEB1CAD1E4F0`. Updater checks public NEW M3U identical to the approved private 158-channel source except EXTM3U EPG header, then passes the private source to the original guarded generator. Installer adds regression selftest, rollback of deployed helper files. ZIP integrity and static checks PASS; on-server PowerShell syntax/runtime still need validation. **Never run v1.1 again.** Release scope remains primary UA globally to all UIDs, preserving separate #19 and #14 and all RU artifacts. Normal user-side cutover backup from failed attempt: `C:\ReservLampac\IPTV-Manager\UA-Managed\cutover-20261118-144440-13c57be1`.

---

# UPDATE — UA AVAILABLE TO ALL UIDs (2026-11-18)

The user has now explicitly approved **global Plugin Policy Server delivery** of the new primary **IPTV Украина** plugin to ALL valid Lampa UIDs across Samsung, Android TV, and other clients. This replaces the former Samsung-only scope for the first managed IPTV plugin. The legacy IPTV #19 and IPTV #14 plugin entries and all other plugins (including their own `exclude_uids`) remain unchanged.

**Server package v1.1:** `UA-Managed-Cutover-v1.1-ALL-UIDs.zip` supersedes v1. After successful guarded UA M3U+EPG publication, change only `plugins.iptv_plus` in `C:\ReservLampac\PluginManager\plugins.json` to `enabled=true`, `name=IPTV Украина`, `url=https://ipvideocom-star.github.io/lampa-plugins/iptv-plus/iptv-ua-managed-v1.3.1.js`, and **`exclude_uids=[]`**. Check the live Policy Server endpoint `127.0.0.1:9131/plugin-manager/policy?uid=...` with two non-user synthetic UIDs and roll back on failure. Keep backups and original scheduled tasks; restart Lampa clients to refresh plugin loading.

Note: per-UID policy exclusion hides plugin distribution but does NOT cryptographically revoke access to already-known publicly served M3U URLs. To revoke actual streams, implement server-side authentication/authorization on the Caddy route separately. Do not infer that a client is denied from a missing sidebar item alone.

No server cutover has been executed by ChatGPT. Source package is prepared; run and observe the installer on Windows Server before claiming deployment or functionality. UA source nightly refresh, automatic promotion to M3U, and Samsung playback acceptance are distinct gates. RU is still ON HOLD.

---

# ACTIVE RELEASE INSTRUCTION — 18 NOV 2026

**Target Samsung side menu: THREE entries, not one or two.**
1. **IPTV Украина** — replaces ONLY the original/first IPTV+ (`iptv_plus`) and loads a NEW managed UA-only M3U with categories and a separate UA-only XMLTV.
2. **IPTV №19** — existing 3,276-entry user playlist remains fully unchanged.
3. **IPTV №14** — existing 2,710-entry user playlist remains fully unchanged.

No RU build, no RU playlist selection, no removal of #19/#14. Prior plans below are superseded where they conflict. Names are tentative. User has explicitly authorized the UA-first replacement, with rollback and existing Plugin Policy Server.

**Prepared public plugin:** `iptv-plus/iptv-ua-managed-v1.3.1.js` with primary plugin ID `iptv_plus`, one sidebar menu entry `IPTV Украина`, fixed `/iptv/playlists/IPTV-UA-NEW.m3u` + `IPTV-UA-EPG-NEW.xml` and automatic M3U reload while open. User #19/#14 instances do not share this plugin ID.

**Prepared server cutover package:** `UA-Managed-Cutover-v1.zip` is a user-executed bundle: PowerShell syntax selftest, preflight policy/layout inspection, backup to `C:\ReservLampac\IPTV-Manager\UA-Managed`, new distinct UA M3U (158 previously ffprobe-verified candidates, nine categories), new current/future EPG, HTTPS checksum checks, guarded extension to existing EPG UA 6h script, and finally selective `iptv_plus` plugin URL/name policy update. Rollback supported. This bundle has not been run on the user's Windows server; production remains unchanged pending execution.

**Honest limitations:** 158 video-packet observations do not prove identity or continuous availability. Reviewed historical snapshot has 39 EPGShare identity-reviewed plus 12 OpenEPG matches = 51/158, not the 67 suspect shadow entries. Regeneration fetches fresh sources and applies quality guards; actual count will change. TVA provider fetches source M3Us nightly and retains last good, but a safe pipeline for automatically promoting revised stream URLs into the NEW UA M3U has not been completed yet. Setanta Sports 1 and 2 appear in TVA source lists but have no verified video/content identity or licensing confirmation and are NOT included automatically. User's goal of daily source selection, refresh and reliable backups remains on the implementation roadmap — do not claim completed.

---

# CURRENT PHASE OVERRIDE — 2026-11-18 (USER INSTRUCTION)

**ONLY UA NOW. RU WORK IS ON HOLD.**

This overrides the older "build both independent M3U files now" plan below.

1. Replace the current/legacy Samsung Lampa **IPTV+** menu experience with the new, independent Ukrainian collection maintained by UA AutoCatalog/TVA/EPG. User-facing menu label is provisional **IPTV Украина**; final label pending user approval.
2. Remove old/duplicated IPTV menu entries from active distribution during the controlled UA cutover, with backup and rollback. **Do not delete source playlist files**, notably #14 and #19, since the user may choose either as the basis for RU later.
3. **Do not assemble, test, stage, publish, modify or choose the new RU playlist at this time.** Future RU will use specific sources/files supplied by the user; no inferred feed (such as iptv-org), no copying old RU pilot, no autonomous selection of #14 vs #19.
4. The preview two-entry plugin developed earlier is **NOT approved for deployment as-is**. For the interim UA-only release, ensure exactly one IPTV menu entry, with the new UA playlist. The second RU entry must be absent until explicitly requested.
5. `IPTV-Dual-Fresh-Stage-v1.zip` and its RU staging procedure are **withdrawn**; do not run/install them.
6. Keep production untouched until Ukrainian playlist, reviewed UA EPG, and plugin policy migration have passed checks and user approves the actual cutover. Nightly TVA provider and the existing source maintenance are retained.

---
# Earlier planning history (superseded where conflicting)

# 2026-11-18 — NEW IPTV build for Lampa: exactly two M3U files, one IPTV+ instance

**This decision supersedes** `IPTV-STATE-FROZEN-2026-11-13.md` and `TVA-MAIN-IPTVPLUS-INTEGRATION-2026-11-17.md` for future migration work. Older files document historical installations only.

## Approved target architecture
1. **One** IPTV+ codebase, but **exactly two sidebar menu items** in Samsung Lampa: provisional **IPTV Украина** and **IPTV Россия** (final names pending user approval). Neither the generic IPTV+ menu entry nor any extra cloned IPTV+ / IPTV 19 / IPTV 14 entry should remain. Do **not** deploy IPTV 3, MaxTV, IPTV PRO, or three cloned IPTV+ instances.
2. Clicking **IPTV Украина** directly opens the UA list, and clicking **IPTV Россия** directly opens the RU list. **No inner region picker** and no combined M3U. The two sidebar entries share one plugin implementation but maintain separate settings/state.
3. These choices load two **independent newly generated** M3U files, with separate identities, groups, playlist refresh and XMLTV association. Do not merge UA+RU and do not ingest the old combined/pilot/community lists as the new collections.
4. New **UA** list is rebuilt from the UA AutoCatalog canonical channels, source discovery, Media Verify and approved alternates (including TVA). Existing 158 video-packet-verified preview is candidate material, **not yet approved production**. Resolve historical catalog counts 194 vs 224 and source identity before publishing.
5. New **RU** list is built independently from verified RU channels/source inventory, not a renamed old 85/133/2710/3276-entry list. Preserve the previously selected preference for major Russian-language channels, avoid irrelevant far-flung regional channels.
6. EPG: UA-only XMLTV in its own channel-ID namespace from reviewed real current/future entries (no past archive, max seven days). EPG v2.6 67-channel shadow preview includes questionable mappings; exclude/resolve those before release. RU list should use reliable per-source guide mappings where verified; do not generate a large independent RU EPG unless required.
7. The existing IPTV Manager and TVA provider/nightly hooks continue serving source acquisition, health and last-good snapshots, not automatic channel publication. GitHub stores only public scripts/docs, never private stream URLs or UID tokens.

## Plugin implementation
- The existing `iptv-plus-v1.2.1-auto-refresh.js` has only one `iptv_plus_playlist` setting. It cannot serve two independent playlists without code changes.
- New **STAGING-ONLY** source: `iptv-plus/iptv-plus-v1.3.0-dual-ua-ru-PREVIEW.js`. Single plugin identity `iptv_plus`, two separate top-level menu entries (not toolbar country buttons) and settings keys `iptv_plus_ua_playlist`, `iptv_plus_ru_playlist`, `iptv_plus_ua_epg`, `iptv_plus_ru_epg`, `iptv_plus_region`. It intentionally ignores legacy combined playlist settings. It has passed JS syntax validation only; no TV/UAT test or production plugin policy change has occurred.
- The existing Policy Server will eventually distribute **one** new plugin and its two URLs to Samsung, automatically. No manual entry of URLs/UID on the TV. Do not hardcode a Samsung UID in GitHub.

## Replacement procedure (never blind-delete)
1. Reconcile on-server catalog state and derive the two fresh, independently validated M3U previews. Per-channel stable IDs, categories, URL requirements, content-identity review, fallback candidates, and guide validity.
2. Test preview plugin against new preview files without changing the live Plugin Policy Server.
3. Stage Caddy served HTTPS aliases for the two M3U files and UA XMLTV; verify MIME, SHA256, XMLTV tvg-id matching and reload behavior.
4. Back up active Plugin Policy Server and Samsung client storage state insofar as technically feasible; then remove the old **managed IPTV entries only** (combined pilot/experimental and clones 19/14, legacy autosetup hooks), and replace with one IPTV+ v1.3 plugin. Do not affect Source Grid, Likhtar or other Lampa plugins. Old server files remain for rollback, but must not appear in the new UI.
5. Perform one brief final acceptance on Samsung Tizen: menu items exactly two, UA and RU opening directly and independently, categories and channel playback work, UA EPG current/future, refresh behaves; verify Android secondary.
6. Enable controlled deployment only after explicit user approval. Keep AutoPublish OFF until separately approved, use backup, atomic file switch, validation, rollback.
7. Follow with IPTV Manager Watchdog for sources, ffprobe health, alternate verification, EPG schedules, logos, HTTPS and meaningful Telegram alerts.

## Current blockers
- New RU build and identity/stream verification are not yet complete.
- UA catalog 194 vs 224 conflict; 158 preliminary video observations, not guaranteed channel identity.
- Clean approved UA guide release is not complete.
- Policy Server on the user's Windows Server is not directly accessible here; no menu/policy changes have been performed.
- Samsung plugin preview has NOT been tested on a real TV.

**Current production state unchanged** until release gates are passed and user authorizes the cutover.

## UI correction on 2026-11-18
The user explicitly rejected the single sidebar entry with an internal country selector. Desired final Samsung menu has exactly two entries: **IPTV Украина** and **IPTV Россия** (working labels only, not yet approved); each opens its matching independently generated M3U. This revision was implemented in the staging-only plugin source and verified for JS syntax. Do not install it to production until separate UA/RU M3U and policy migration are ready.


## Progress — first fresh UA/RU staging module (2026-11-18)
- A private on-server builder package `IPTV-Dual-Fresh-Stage-v1.zip` has been prepared for PowerShell 7. Source module installs to `C:\IPTV-Manager\Tools\DualRelease\Stage-IPTV-Dual-Fresh-v1.ps1`. Package remains staging-only and must pass runtime PowerShell ParseFile and offline SelfTest on the server before any network work.
- UA input: existing private **158-channel verified-preview** from UA AutoCatalog v3, no legacy published UA list. Validate IDs, duplication and provenance.
- RU input: **fresh upstream** `https://raw.githubusercontent.com/iptv-org/iptv/master/streams/ru.m3u`, not old RU pilots or user community lists. Filter a curated national/thematic allowlist; never treat regional/time-shift channels as interchangeable.
- Run ffprobe on at most 100 RU candidate URLs by default, concurrency 3 and timeout 15 seconds. Only video >=3 observed packets with a video resolution is eligible for private RU staging. Quarantine exact URL reuse across multiple channel IDs. No content-identity assertion from packets.
- Outputs stay private in `C:\IPTV-Manager\data\dual-iptv-staging\release-*\IPTV-UA-NEW-STAGED.m3u` and `IPTV-RU-NEW-STAGED.m3u`; URL-free `report.json`, `RU-MEDIA-REVIEW-URL-FREE.csv` and `RU-PRIORITY-CHANNELS-URL-FREE.csv`.
- This is **not** final publication. It does not clean or activate EPG, change Samsung policy, activate the two sidebar entries or touch old tasks. Successful staging must be reviewed, RU coverage expanded as needed and clean UA EPG built separately before controlled cutover.
