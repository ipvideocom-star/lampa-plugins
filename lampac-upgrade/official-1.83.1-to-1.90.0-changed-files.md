# Official Lampac 1.83.1 → 1.90.0 source delta inventory

Generated from GitHub tree SHA comparisons of the **two tagged releases**. A path appears once regardless of how many intervening commits edited it. Source-tree changes are **not** a ready-to-apply Windows deployment patch.

| Category | Changed | Added | Removed |
|---|---:|---:|---:|
| Core | 5 | 1 | 0 |
| Modules | 31 | 22 | 0 |
| Online | 2 | 0 | 0 |
| Shared | 3 | 0 | 0 |
| RuntimeDeps | 2 | 1 | 0 |
| Other | 16 | 10 | 0 |

**Totals:** 59 modified, 34 added, 0 removed; 93 in all. Source trees: 2151 blobs (1.83.1), 2185 blobs (1.90.0).

**Key deployment caveat:** `Core.dll` and other compiled binaries in Windows release are not updated by copying edited `.cs` source files from GitHub. For true Lampac 1.90.0 use its compiled runtime, and reconcile user's local modifications by three-way merge (official 1.83.1, actual installed local, official 1.90.0), with backups and validation. Modules may compile dynamically and can have API dependencies.

**Protected local configuration:** `init.conf`, `passwd`, `users.json`, `database`, `data/ts`, Caddy setup, external IPTV Manager, Plugin Manager, ViewingStats, Plex/Tautulli. Never upload contents of protected files into public GitHub.

## Core (6)

| Status | Source path |
|---|---|
| Changed | `Core/Controllers/ApiController.cs` |
| Changed | `Core/Core.csproj` |
| Changed | `Core/Middlewares/ProxyAPI.cs` |
| Changed | `Core/Middlewares/ProxyAPI.Dash.cs` |
| Changed | `Core/Middlewares/ProxyAPI.Utilities.cs` |
| Added | `Core/tests/proxyapi-handlers.cs` |

## Modules (53)

| Status | Source path |
|---|---|
| Changed | `Modules/Community/QRAuth/DenyPageGenerator.cs` |
| Changed | `Modules/Community/QRAuth/README.md` |
| Changed | `Modules/GStreamer/Models/ModuleConf.cs` |
| Changed | `Modules/GStreamer/plugins/gst.js` |
| Changed | `Modules/GStreamer/README.md` |
| Changed | `Modules/GStreamer/Services/GService.cs` |
| Changed | `Modules/GStreamer/Services/GStask.Pipeline.cs` |
| Added | `Modules/GStreamer/tests/playlist.test.cjs` |
| Added | `Modules/GStreamer/tests/source-url.fixture` |
| Added | `Modules/GStreamer/tests/source-url.test.cjs` |
| Changed | `Modules/LampaWeb/ModInit.cs` |
| Added | `Modules/NativeAppleTV/Controllers/AuthController.cs` |
| Added | `Modules/NativeAppleTV/Controllers/ConfirmController.cs` |
| Added | `Modules/NativeAppleTV/manifest.json` |
| Added | `Modules/NativeAppleTV/Models/NativeAppleTVConf.cs` |
| Added | `Modules/NativeAppleTV/ModInit.cs` |
| Added | `Modules/NativeAppleTV/NativeAppleTV.csproj` |
| Added | `Modules/NativeAppleTV/Services/ChallengeStore.cs` |
| Added | `Modules/NativeAppleTV/Services/TokenStore.cs` |
| Changed | `Modules/OnlineAnime/AniDub/ModInit.cs` |
| Changed | `Modules/OnlineAnime/AniDub/README.md` |
| Changed | `Modules/OnlineAnime/Animebesst/Controller.cs` |
| Changed | `Modules/OnlineAnime/AnimeLib/Controller.cs` |
| Changed | `Modules/OnlineAnime/AnimeLib/Model.cs` |
| Changed | `Modules/OnlineAnime/Kodik/Controller.cs` |
| Changed | `Modules/OnlineAnime/Kodik/Service.cs` |
| Changed | `Modules/OnlinePaid/Alloha/Controller.cs` |
| Changed | `Modules/OnlinePaid/Alloha/Model.cs` |
| Changed | `Modules/OnlineRUS/Gencit/Model.cs` |
| Changed | `Modules/OnlineRUS/Gencit/ModInit.cs` |
| Changed | `Modules/OnlineRUS/Gencit/ModuleConf.cs` |
| Changed | `Modules/OnlineRUS/Gencit/Service.cs` |
| Added | `Modules/OnlineRUS/LordFilm/Controller.cs` |
| Added | `Modules/OnlineRUS/LordFilm/init.merge.example.json` |
| Added | `Modules/OnlineRUS/LordFilm/LordFilm.csproj` |
| Added | `Modules/OnlineRUS/LordFilm/manifest.json` |
| Added | `Modules/OnlineRUS/LordFilm/Model.cs` |
| Added | `Modules/OnlineRUS/LordFilm/ModInit.cs` |
| Added | `Modules/OnlineRUS/LordFilm/ModuleConf.cs` |
| Added | `Modules/OnlineRUS/LordFilm/README.md` |
| Added | `Modules/OnlineRUS/LordFilm/Services/LordFilmParser.cs` |
| Added | `Modules/OnlineRUS/LordFilm/Services/LordFilmSession.cs` |
| Changed | `Modules/OnlineRUS/Phantom/Controller.cs` |
| Added | `Modules/OnlineRUS/Phantom/tests/playback-cache.py` |
| Changed | `Modules/Sync/Sync/plugins/bookmark.js` |
| Changed | `Modules/Sync/Sync/plugins/sync_v2/invc-ws.js` |
| Changed | `Modules/Sync/Sync/plugins/sync_v2/sync.js` |
| Changed | `Modules/Sync/Sync/SqlContext.cs` |
| Changed | `Modules/Sync/TimeCode/Controller.cs` |
| Changed | `Modules/Sync/TimeCode/ModInit.cs` |
| Changed | `Modules/Sync/TimeCode/plugin.js` |
| Changed | `Modules/Sync/TimeCode/README.md` |
| Changed | `Modules/Sync/TimeCode/SqlContext.cs` |

## Online (2)

| Status | Source path |
|---|---|
| Changed | `Online/OnlineApi.cs` |
| Changed | `Online/plugin.js` |

## Shared (3)

| Status | Source path |
|---|---|
| Changed | `Shared/Models/Module/ModuleCapabilities.cs` |
| Changed | `Shared/Models/Templates/SegmentTpl.cs` |
| Changed | `Shared/Services/DataArea.cs` |

## RuntimeDeps (3)

| Status | Source path |
|---|---|
| Changed | `Directory.Packages.props` |
| Changed | `NextGen.slnx` |
| Added | `tools/lampac-mcp/LampacMcp.csproj` |

## Other (26)

| Status | Source path |
|---|---|
| Changed | `.github/workflows/format-code.yml` |
| Changed | `.github/workflows/pages.yml` |
| Changed | `.github/workflows/pr-title.yml` |
| Changed | `.github/workflows/release.yml` |
| Changed | `.github/workflows/reusable-build.yml` |
| Changed | `.github/workflows/reusable-docker-build.yml` |
| Changed | `.github/workflows/reusable-upload-release-assets.yml` |
| Changed | `.github/workflows/test-build.yml` |
| Added | `.github/workflows/test-tools-lampac-mcp.yml` |
| Changed | `CONTRIBUTING.md` |
| Changed | `Dockerfile` |
| Changed | `docs/api/online.mdx` |
| Changed | `docs/docs.json` |
| Changed | `docs/modules/gstreamer.mdx` |
| Added | `docs/modules/native-apple-tv.mdx` |
| Changed | `docs/modules/online.mdx` |
| Changed | `site/package-lock.json` |
| Changed | `site/package.json` |
| Added | `tools/lampac-mcp/Contracts.cs` |
| Added | `tools/lampac-mcp/LampacConfig.cs` |
| Added | `tools/lampac-mcp/LampacTools.cs` |
| Added | `tools/lampac-mcp/ModuleStore.cs` |
| Added | `tools/lampac-mcp/PanelClient.cs` |
| Added | `tools/lampac-mcp/ProcessRunner.cs` |
| Added | `tools/lampac-mcp/Program.cs` |
| Added | `tools/lampac-mcp/README.md` |

