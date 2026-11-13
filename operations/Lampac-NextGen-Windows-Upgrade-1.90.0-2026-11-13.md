# Lampac Next Generation — Windows Server 2022 upgrade to 1.90.0

**Prepared 2026-11-13. This is a runbook, not a claim that the upgrade ran.**

## Release verified
- Official upstream tag: https://github.com/lampac-nextgen/lampac/releases/tag/1.90.0
- Date: 2026-11-13
- Windows archive: `lampac-nextgen.zip` (480369803 bytes)
- GitHub release SHA256: `8d28d2af05a3b035e650459f1a6a4216a0f8e71f20f4f34d853f36a0a36b6e8e`
- Official [Windows/NSSM instructions](https://docs.lampac.dev/deployment/windows), [upgrade guide](https://docs.lampac.dev/maintenance/updates) and [config](https://docs.lampac.dev/configuration/overview).
- Upstream compare 1.83.1..1.90.0 = 43 commits, with GStreamer, Phantom, Gencit, Online, Sync, TimeCode and LordFilm changes. Tag 1.90.0 adds native Apple TV sign-in.
- Require ASP.NET Core Runtime 10.x.

## Production identity and constraints
- Working NSSM service: **Lampac**; app directory `C:\lampacNG-next`; executable `dotnet.exe Core.dll`.
- Core local endpoint `http://127.0.0.1:9118`; Caddy front end `https://lampa.v6.army`.
- **Never** alter the old legacy `C:\lampacNG` directory.
- Backups `C:\ReservLampac`; do not overwrite Caddy, Plex 32400, Tautulli 8181, ViewingStats, plugin policy server, IPTV Manager or LAN networking.
- `init.conf`, `passwd`, `users.json`, `database\tgauth`, `data\ts`, overrides and custom modules must survive.
- **Local patches** to preserve: `module\OnlineRUS\FanCDN\Controller.cs` (refresh stale embed key; marker `refreshedSearch`); `module\TorrServer\Controller.cs` (public view guard marker `TS_PUBLIC_VIEW_GUARD` and 90s timeout); three `manifest.json` files with `enable: true` (TelegramAuth, TelegramAuthBot, AdminPanel).
- The **upstream** FanCDN and TorrServer Controller.cs files and all three relevant manifests have identical Git blobs between 1.83.1 and 1.90.0, so exact local patched Controllers can be carried to the new version after verifying the target matches the official source.
- User instructions dated 2026-10-24 are stored under `C:\ReservLampac\Lampac_NextGen_Инструкция_по_обновлению_Windows.txt` and Library. The earlier proposed SUS/Issues feedback has no verified upstream issue/PR link or recorded acceptance, so it does not block this update.

## Executable package
- Archive created in conversation: `Lampac-NextGen-1.90.0-Windows-SafeUpgrade.zip`.
- Main: `START-LAMPAC-190-UPDATE.cmd`. Checks NSSM, .NET runtime, space, current manifest state; downloads a **pinned** GitHub release and checks SHA256 before extraction. Patches the reviewed source controllers and only the three new manifest `enable` fields in a separate stage. Checks user file conflicts **before** downtime.
- Before replacing, stops the two Lampac watchdog scheduled tasks and NSSM Lampac, backs up critical data and registry under `C:\ReservLampac\LampacUpgrade\<run>\critical-userdata`.
- Moves the **entire previous active installation** to unique `C:\lampacNG-next-OLD-190-<run>`, stages the new build in original path, copies private config/data/overrides but *not* old `module/` wholesale or old binaries, starts service and checks `/version?type=hash` and `/online.js` locally. Attempts auto-rollback if swap/start fails, with separate manual rollback script.
- Optional read-only app audit: `START-LAMPAC-190-AUDIT.cmd` (download and stage; does not touch running service).
- Expected success status: `LAMPAC_1_90_0_UPGRADED_AND_HTTP_HEALTHY`.
- Package passed ZIP integrity and static delimiter/logic checks, **not** a live Windows PowerShell or server runtime test. Do not report as installed until the user runs and shares report.

## Acceptance after update
1. Confirm actual Samsung movie playback through Online with **Spectre/Mirage/Phantom, Filmix**; first 1080p, then 4K HEVC and audio/seek.
2. Confirm telegram UID auth remains bound; ask for CURRENT device UID before UID-dependent server diagnostics.
3. Check GStreamer, TorrServer MatriX, Chrome/CDP and legacy patch guards, public routes still blocked by Caddy, external Plex/Tautulli accessible.
4. Plugin policy and three IPTV+ entries remain untouched (source 257 RU/UA, #19 3276, #14 2710); **IPTV is on hold** until VOD acceptance.
5. Keep backup until tests and potential rollback decision.

IPTV frozen snapshot: [IPTV-STATE-FROZEN-2026-11-13.md](../iptv-manager/IPTV-STATE-FROZEN-2026-11-13.md).
