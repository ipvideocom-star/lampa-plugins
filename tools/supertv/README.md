# SuperTV — isolated launch pilot

Status: **code only, not installed on the Windows server**.

This folder contains a revised controller for the existing private staging folder:
`C:\IPTV-Manager\data\supertelevidenie\staging\SuperTV-NEW-LaunchPilot-20261128`.

## What it changes

* Reads the **existing** `Manifest.json`, two private M3Us and `Pilot-StreamGate.yaml` produced by the failed v0.1 pilot. Never ships or uploads these private files.
* Confirms input hashes and counts (1895 primary, 1349 backup) without checking 3,718 live streams again.
* Runs a **separate** local-only provider service (127.0.0.1:9191) and StreamGate (127.0.0.1:9187).
* Uses **three signals** for readiness: `/healthz`, `/api/v1/channels` when it exposes a count, and `/playlist.m3u` with explicit byte-array UTF-8 decoding. HTTP 200 alone is not sufficient.
* If the pilot is inconsistent, stops only the processes it spawned and leaves private stdout/stderr logs on the server; it prints no source URLs.
* Does **not** modify the Windows service, public playlists, Caddy, plugin policy or production StreamGate.

## Why we changed the check

The original v0.1 launcher did `[string]$request.Content` and then counted `#EXTINF`. Some PowerShell response types can contain bytes rather than decoded text. The observed `STREAMGATE_CHANNELS: 0` therefore is **not enough to establish an empty catalog**.

Importantly, StreamGate v1.0.0 source calls `LoadInitial` **before opening its HTTP listener**, so a successful response should already have a catalog. If the three counts disagree, the controller stops and requires examination of the pilot's private logs and actual binary version, rather than assuming a startup race.

## Deployment boundary

GitHub is only a **code distribution and review** channel. It cannot execute commands inside this user's Windows Server through this repository alone. An explicitly approved **one-time** local agent or deployment path is needed to end the manual ZIP/PowerShell cycle.

**Never commit:** original `.m3u` playlists, generated provider M3Us, `Manifest.json` containing source URLs, runtime logs, credentials or tokens.

The initial rollout should use `SelfTest` and `Status` before `Start`. Publishing to clients is a separate approval stage, with backup and rollback.
