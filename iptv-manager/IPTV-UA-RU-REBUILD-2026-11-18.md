# 2026-11-18 — NEW IPTV build for Lampa: exactly two M3U files, one IPTV+ instance

**This decision supersedes** `IPTV-STATE-FROZEN-2026-11-13.md` and `TVA-MAIN-IPTVPLUS-INTEGRATION-2026-11-17.md` for future migration work. Older files document historical installations only.

## Approved target architecture
1. **One** IPTV+ plugin in the Samsung Lampa side menu, on both Samsung official Lampa and MSX where applicable. Do **not** deploy IPTV 3, MaxTV, IPTV PRO, or several cloned IPTV+ instances.
2. Inside IPTV+, the user chooses **🇺🇦 Украина** or **🇷🇺 Россия**.
3. These choices load two **independent newly generated** M3U files, with separate identities, groups, playlist refresh and XMLTV association. Do not merge UA+RU and do not ingest the old combined/pilot/community lists as the new collections.
4. New **UA** list is rebuilt from the UA AutoCatalog canonical channels, source discovery, Media Verify and approved alternates (including TVA). Existing 158 video-packet-verified preview is candidate material, **not yet approved production**. Resolve historical catalog counts 194 vs 224 and source identity before publishing.
5. New **RU** list is built independently from verified RU channels/source inventory, not a renamed old 85/133/2710/3276-entry list. Preserve the previously selected preference for major Russian-language channels, avoid irrelevant far-flung regional channels.
6. EPG: UA-only XMLTV in its own channel-ID namespace from reviewed real current/future entries (no past archive, max seven days). EPG v2.6 67-channel shadow preview includes questionable mappings; exclude/resolve those before release. RU list should use reliable per-source guide mappings where verified; do not generate a large independent RU EPG unless required.
7. The existing IPTV Manager and TVA provider/nightly hooks continue serving source acquisition, health and last-good snapshots, not automatic channel publication. GitHub stores only public scripts/docs, never private stream URLs or UID tokens.

## Plugin implementation
- The existing `iptv-plus-v1.2.1-auto-refresh.js` has only one `iptv_plus_playlist` setting. It cannot serve two independent playlists without code changes.
- New **STAGING-ONLY** source: `iptv-plus/iptv-plus-v1.3.0-dual-ua-ru-PREVIEW.js`. Single plugin identity `iptv_plus`, two country buttons in the toolbar and settings keys `iptv_plus_ua_playlist`, `iptv_plus_ru_playlist`, `iptv_plus_ua_epg`, `iptv_plus_ru_epg`, `iptv_plus_region`. It intentionally ignores legacy combined playlist settings. It has passed JS syntax validation only; no TV/UAT test or production plugin policy change has occurred.
- The existing Policy Server will eventually distribute **one** new plugin and its two URLs to Samsung, automatically. No manual entry of URLs/UID on the TV. Do not hardcode a Samsung UID in GitHub.

## Replacement procedure (never blind-delete)
1. Reconcile on-server catalog state and derive the two fresh, independently validated M3U previews. Per-channel stable IDs, categories, URL requirements, content-identity review, fallback candidates, and guide validity.
2. Test preview plugin against new preview files without changing the live Plugin Policy Server.
3. Stage Caddy served HTTPS aliases for the two M3U files and UA XMLTV; verify MIME, SHA256, XMLTV tvg-id matching and reload behavior.
4. Back up active Plugin Policy Server and Samsung client storage state insofar as technically feasible; then remove the old **managed IPTV entries only** (combined pilot/experimental and clones 19/14, legacy autosetup hooks), and replace with one IPTV+ v1.3 plugin. Do not affect Source Grid, Likhtar or other Lampa plugins. Old server files remain for rollback, but must not appear in the new UI.
5. Perform one brief final acceptance on Samsung Tizen: menu item exactly one, UA and RU independent selections, categories and channel playback work, UA EPG current/future, refresh behaves; verify Android secondary.
6. Enable controlled deployment only after explicit user approval. Keep AutoPublish OFF until separately approved, use backup, atomic file switch, validation, rollback.
7. Follow with IPTV Manager Watchdog for sources, ffprobe health, alternate verification, EPG schedules, logos, HTTPS and meaningful Telegram alerts.

## Current blockers
- New RU build and identity/stream verification are not yet complete.
- UA catalog 194 vs 224 conflict; 158 preliminary video observations, not guaranteed channel identity.
- Clean approved UA guide release is not complete.
- Policy Server on the user's Windows Server is not directly accessible here; no menu/policy changes have been performed.
- Samsung plugin preview has NOT been tested on a real TV.

**Current production state unchanged** until release gates are passed and user authorizes the cutover.
