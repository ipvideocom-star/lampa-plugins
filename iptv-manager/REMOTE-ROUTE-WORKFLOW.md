# IPTV route verification workflow

Use this repository for versioned PowerShell scripts only. Keep stream URL CSVs, service credentials, tokens, and runtime reports on the user's servers.

## Locations

- Windows Server 2022: `C:\IPTV-Manager` for active IPTV files; `C:\ReservLampac\IPTVPlus\RouteComparison` for reports and backup batches.
- Windows Server 2019 (W2019S): `C:\IPTV-Agent`; input CSV at `C:\IPTV-Agent\state\P1-REMOTE-RECHECK-10.csv`.
- 3proxy at `192.168.88.34:33128` is the existing proxy program, not three independent proxy routes. Leave its current domain allowlist unchanged.

## Current batch

The 10-row P1 CSV was validated on W2019S. It has SHA256 `9427A0995BD033F8FEE325B58DF3C902C7BC6716D5E079A298E36B6E7B019B98`. Check streams through the W2019S direct internet path only; do not modify 3proxy, nightly jobs, Caddy, or published playlists.

Next runs: P2 75 previously untested URLs; P3 31 previously unsuccessful URLs. Each batch is a local-only file, not a repository artifact.
