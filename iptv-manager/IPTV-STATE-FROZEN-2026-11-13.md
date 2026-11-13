# IPTV frozen configuration — 2026-11-13

**Decision:** IPTV work paused deliberately while Lampac Next Generation is updated to 1.90.0 and movie playback is tested.

## Target Samsung configuration (installed server-side, final TV acceptance pending)
- Official Samsung Lampa UID `ymdqqucx` and Samsung MSX Lampa UID `yd7yhpcg`.
- Exactly **three independent IPTV+ clients**, each with its own storage:
  1. **IPTV+** (`iptv_plus`) — original RU/UA pilot playlist, **257** entries (125 UA, 132 RU), previously configured EPG. Original separate files remain 125 UA and 133 RU (1-entry discrepancy is known, not repaired).
  2. **IPTV+ №19** (`iptv_plus_19`) — original user-selected M3U **3276** entries, `#EXTGRP` categories, no native XMLTV or regular tvg-id; keep original source unchanged.
  3. **IPTV+ №14** (`iptv_plus_14`) — newer user-supplied M3U **2710** entries, 12 categories including info, no native XMLTV or tvg-id; keep original source unchanged.
- Separate IPTV PRO, MaxTV, IPTV 3 and community picker variants are **retired on Samsung**. Do not reinstall them.
- **Do not** change Caddy route `/iptv/playlists/*`, IPTV Manager or Plugin Manager policies during Lampac upgrade.
- Preserve Lampa external custom plugins, Source Grid, Likhtar, Samsung setup and the two IPTV+ user-selected lists as currently distributed.
- Two community feeds (#19/#14) should **later** be refreshed as independent sources with safety validation; never merge them automatically or drop channel entries without user approval.
- **Later** optimize the original RU/UA list, prioritizing Ukrainian channels and current EPG. Do not start that work during the Lampac upgrade.

## Server history
- Successful #14 installer report: `READY_THREE_IPTVPLUS_SAMSUNG_14` on 2026-11-13. Both Samsung UIDs verified by policy. 2710 entries, twelve categories.
- Previously successful standalone #19 installer: `READY_IPTVPLUS19_STANDALONE_SAMSUNG`; its source contains 3276 entries.
- Earlier keep-two report: `READY_TWO_IPTVPLUS_ONLY_SAMSUNG`. Third #14 was then added without modifying first two.
- Production Lampac is **C:\\lampacNG-next**, NSSM service `Lampac`; Caddy and plugin policy are separate from the Lampac application folder.

**Acceptance after Lampac 1.90 upgrade:** all three IPTV+ links must remain published and the plugin policy must remain intact, but first acceptance priority is movie playback. Avoid repeated full IPTV tests now.
