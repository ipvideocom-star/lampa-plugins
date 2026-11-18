# IPTV Manager — Ukrainian EPG live-coverage review v1.3

**Scope:** UA 158-channel release only. 18 November 2026 reference: 53 channels with present-time EPG, 105 without. This is a read-only component designed to run beside the existing `IPTV-Manager-EPG-UA-6h` updater. It does **not** install tasks, modify the 6-hour pipeline, M3U, published EPG, Caddy, Policy Server, streams, or RU.

## What it does

1. Verifies that the local published UA playlist still has exactly 158 unique channel `tvg-id` values and the candidate ledger corresponds to 105 currently missing channels.
2. Reads the **actual published XMLTV**, counts channels with a valid programme **in progress now** (not archive and not future-only).
3. Tries two public, HTTPS, explicit, allowlisted sources:
   - `https://epgshare01.online/epgshare01/epg_ripper_UA1.xml.gz`
   - `https://free-epg.de/api/epg/ua.xml.gz`
4. For 63 **unapproved alias candidates** in `UA_EPG_CANDIDATES_READONLY_2026-11-18.csv`, verifies that source XMLTV *channel IDs* and current/next-seven-days programmes exist. It also checks whether FreeEPG publishes a **direct exact-ID** match among the 105. Missing/offline sources remain `UNAVAILABLE`, **not** "zero EPG".
5. Rejects titles such as `No Data`, dates with invalid/missing timezone, expired programmes, DTD/external entities, and oversized responses. Requires channel identity review even when XMLTV contains a real programme; regional stations require explicit review.
6. Produces `UA-EPG-COVERAGE-LIVE-CANDIDATES-URL-FREE.csv` and `summary.json` under `C:\IPTV-Manager\data\ua-autocatalog\v3\epg-audit\review-*`. Downloaded XMLTV/XMLTV gzip is removed. Reports have **no video URLs/tokens**.

## Installation / execution on Windows Server 2022

This is a permanent read-only audit component, *not* another Windows scheduled task. Put the `.ps1` and `.csv` side by side in `C:\IPTV-Manager\Tools\UA-Manager\`. Use **PowerShell 7** as Administrator or a user who can read the files and write the audit directory.

```
pwsh -NoProfile -File 'C:\IPTV-Manager\Tools\UA-Manager\Invoke-UA-EPG-Coverage-Audit-v1.3.ps1' -SelfTest
pwsh -NoProfile -File 'C:\IPTV-Manager\Tools\UA-Manager\Invoke-UA-EPG-Coverage-Audit-v1.3.ps1'
```

**Do not add this component to the existing 6-hour scheduled task yet.** After reviewing real candidate programmes and channel identities, integrate vetted mapping rows into the existing guarded 6-hour generator, preserving last-known-good and obtaining separate approval before a production EPG change.

## Safety and limitations

- No access to the user's Windows Server from this conversation. Script is source-inspected and contains a runtime `-SelfTest`; its execution on the user's server and real 2026-11-18 guide content are **not verified** here.
- All 63 aliases are hypotheses, not authorized assignments. `LIVE_PROGRAMMES_IDENTITY_REVIEW_REQUIRED` explicitly means **NOT approved**. Do not infer new published EPG coverage from the candidate count.
- Current EPG coverage may be different by the time the script runs. The observed baseline is recalculated from the published XMLTV.
- Broadcaster versus supplier-inserted advertising is a separate, deferred stream provenance task; this audit does not touch streams or implement a relay.