# Supertelevidenie #24 as-is — original groups (2026-11-19)

## User decision
After comparing 12 playlists against the **old #19 from 13 Nov**, choose **new #24 from 18 Nov** as the closest match by original categories/order, **without removing ads or QR overlays** in this trial. Do not reuse the problematic #18 or blindly switch to old #19.

## Source file — supplied privately, do NOT commit
`18.11.2026@community_content (24).m3u8` from the user's Telegram archive.

- SHA256: `F333EE2BADC8E14EC30D59CCB938A1B605EFF68ADAD078695A367A35840088AF`
- 3982 M3U entries, **including** two promotional `ИНФО` records (first two entries).
- 3981 `#EXTGRP` group markers and 24 distinct categories (23 non-`ИНФО`).
- Most stream URLs are plain HTTP; keeping the raw M3U does not solve HTTPS browser mixed-content or upstream buffering. Native Samsung/Android playback is the target trial.
- **No channel content, URL or QR masking is applied.** A QR code burned into source video cannot be removed by changing M3U text.

The old #19 reference has 3276 entries; old host `edmonst.net` is absent in the new #24 streams. Similar names, group/order metadata do not prove same CDN, same video quality or working streams. User observed that #18 was worse, not that #24 is verified.

## IPTV+ isolated loader
`iptv-plus/supertelevidenie-original-groups-v1.js` is cloned from pinned `iptv-plus-v1.2.2-hierarchy-preview.js` at `ed653d9c...`. It:
- uses isolated component/storage `iptv_plus_super` and `lampa_iptv_super_ready` guard (no collision with Ukrainian IPTV+);
- reads the *exact* original M3U groups extracted by the existing `#EXTGRP` and `group-title` parser;
- displays category sidebar in the M3U appearance order without country/topic recategorization;
- uses one server-injected placeholder `__SUPER_PLAYLIST_URL__` that the private Windows installer replaces with existing Supertelevidenie M3U URL. The raw URL and stream secrets are **not** in GitHub;
- keeps search, recent, favorites, original channel order, and all playback behavior.

V8 syntax validation: PASS. Real Samsung/Android client test: PENDING.

## Deployment (not auto-published)
The installer/rollback package is generated in the working conversation as
`Supertelevidenie_24_ASIS_ORIGINAL_GROUPS_INSTALL_v1.zip`.

The user runs `START-SUPERTELEVIDENIE-24.cmd` on Windows Server 2022.
The installer:
1. validates source SHA, 3982 entries, 24 original groups, two intact promo records;
2. matches the actual active Super plugin policy and initial `test-enable-*` manifest rather than guessing random Caddy file names;
3. backs up current Super M3U and `plugins.json` to `C:\ReservLampac\IPTV-Manager\Supertelevidenie\switch24-*`;
4. downloads this JS from an **immutable commit SHA**, fills the published Super M3U URL, saves it under a new private JS file and verifies HTTPS hash;
5. atomically replaces **only** the Super M3U with the user's raw #24 file, verifies public SHA;
6. updates **only** the `iptv_supertelevidenie_test_v1` policy record JS URL; other plugin records must remain semantically unchanged;
7. retains the old JS and M3U backups for rollback. No scheduled tasks or services changed.

Rollback: `START-ROLLBACK-SUPERTELEVIDENIE-24.cmd`, guarded on current published SHA and policy URL.

**Before continuing:** Need `RESULT: SUPERTELEVIDENIE_24_ASIS_GROUPS_PASS` from the user's server, then one client acceptance check of original categories and several primary channels. AutoPublish OFF; no changes to `IPTV Украина`.
