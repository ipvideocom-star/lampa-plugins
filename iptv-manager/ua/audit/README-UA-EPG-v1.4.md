# UA IPTV EPG live audit v1.4 — read-only

## Result of v1.3 on Windows Server 2022 (18 Nov 2026)
- Baseline published XMLTV: **53/158** with current programmes.
- **26** previously uncovered UA channels have provisional EPGShare-UA1 guide IDs with real current programmes. These are **not approved mapping assignments** or published EPG additions.
- EPGShare UA1: **OK**, 1,219 guide channel IDs.
- FreeEPG-UA: **UNAVAILABLE**, gzip decompression error. That is NOT a finding of no EPG.
- No M3U, published EPG, RU, streams, policy, tasks, or Caddy changed.

## v1.4 change
`Invoke-UA-EPG-Coverage-Audit-v1.4.ps1` is a permanent read-only audit component, not a new scheduled task. It reads the same local published M3U and XMLTV and uses the same 105-channel **URL-free** ledger from v1.3.

Fixes/diagnostics:
1. Makes HTTP automatic decompression explicitly disabled and requests `Accept-Encoding: identity`.
2. Inspects actual payload magic and accepts only genuine gzip-compressed XMLTV or genuine plain XMLTV; recognizes at most two gzip layers, with bounded downloads and decompression. Rejects HTML / error responses despite HTTP 200.
3. Distinguishes a bad body from a successful XMLTV read; optional source failures stay `UNAVAILABLE`.
4. Captures source XMLTV channel display-names and sample real programme titles to aid **manual identity review** of live candidate IDs.
5. Prints current candidates in the console and writes updated URL-free CSV and JSON files.

### Running on Windows Server 2022

Keep `UA_EPG_CANDIDATES_READONLY_2026-11-18.csv` beside the new script under `C:\IPTV-Manager\Tools\UA-Manager\`; that ledger already exists after v1.3 install.

```powershell
$script = 'C:\IPTV-Manager\Tools\UA-Manager\Invoke-UA-EPG-Coverage-Audit-v1.4.ps1'
pwsh -NoProfile -File $script -SelfTest
pwsh -NoProfile -File $script
```

Outputs are under `C:\IPTV-Manager\data\ua-autocatalog\v3\epg-audit\review-*`:
- `UA-EPG-COVERAGE-LIVE-CANDIDATES-URL-FREE.csv` — per-channel guide names, programme samples and review states.
- `summary.json` — baseline, count, source status and payload format.

**No candidate is approved automatically.** The next gate is identity review, especially channels with different regional schedules, plus validation of current and future programmes. Only after review should guarded staged integration be designed for the **existing** `IPTV-Manager-EPG-UA-6h` generator. Keep last-good and AutoPublish OFF; production EPG changes require separate approval. No RU changes.

### Validation status
v1.3 PowerShell selftest and full read-only run passed on the user server. v1.4 source has been inspected, but **v1.4 has not yet been run on the user server**. If FreeEPG still fails after format detection, inspect its reported error rather than retrying blindly or counting it as zero.
