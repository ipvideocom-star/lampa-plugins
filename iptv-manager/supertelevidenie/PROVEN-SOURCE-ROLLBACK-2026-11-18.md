# Супертелевидение — возврат на работающий источник

**Причина:** 18 ноября 2026 пользователь протестировал выбранный из двенадцати плейлистов свежий #18 (3952 записей) и сообщил, что на Samsung он загружается дольше, многие каналы не работают и в целом работает хуже ранее проверенных независимых Community #14/#19.

**Решение:** считать выбор #18 по числу записей/EPG/оформлению ошибкой. Не пытаться чинить несколько тысяч потенциально нестабильных stream URL по одному. Предпочесть ранее работавший **старый #19 от 13 ноября**, НЕ новый #19 от 18 ноября, с резервом #14.

## Исходники на собственном Windows Server 2022
- #19 оригинал: SHA256 `6F9495E47524E7889C5A169C94E2E44D22ACB3467C3548DEC796AE88B53C6FD4`, 3276 записей, `Community-19-*.m3u` в `C:\IPTV-Manager\public\playlists`.
- #14 оригинал: SHA256 `F44561F6FD3ABD77AF81BC737221FB24A1077465264EB557CF42C917FCAD8BE6`, 2710 записей, `Community-14-*.m3u`.
- Existing Supertelevidenie test install manifest under `C:\ReservLampac\IPTV-Manager\Supertelevidenie\test-enable-*/manifest.json`; original test source #18 published to separate nonce-named M3U and loaded by isolated `iptv_plus_super` JS. Policy entry `iptv_supertelevidenie_test_v1`.

## Rollback procedure
Switch only the **content of the Supertelevidenie M3U**, not its filename, JS/component namespace, menu, M3U URL, or policy.
1. Confirm current installed test manifest, unchanged JS and active policy; validate old #19 published source by exact SHA.
2. Remove exactly two promotional M3U entries while preserving all remaining #19 stream URLs, groups (`#EXTGRP` supported by IPTV+ v1.2.2), order, and metadata. Expected 3274 remaining entries.
3. Before touching web publication, back up existing Super M3U to timestamped `C:\ReservLampac\IPTV-Manager\Supertelevidenie\switch-*/supertelevidenie.before.m3u`.
4. Atomic replacement of the existing Super M3U, verify local and public HTTPS SHA256. On failure, restore backed-up original. Record manifest with before/after hashes, source identity, counts and rollback state. Do not print stream URLs or commit private M3U.
5. After PASS, fully restart Samsung Lampa; test a few main channels for load times/content. Then, if desired, remove old extra #14/#19 *menu entries* in a separate guarded release; do not remove their source files until after acceptance.
6. Rollback last switch from recorded manifest, requiring currently published SHA match, retaining independent IPTV Украина and related tasks.

**Constraints:** No change to IPTV Украина (158), its EPG/6-hour generator, TVA source registry, Lampac, Caddy routes, plugin policy, scheduled tasks, RU Manager, or old #14/#19 original sources. No extra scheduled job or automatic source promotion. Old #19 may eventually expire; user playback validates outcome.

**Implementation artifact in conversation:** `Supertelevidenie_SWITCH_TO_PROVEN_19_v1.zip` contains PowerShell 7 switch/rollback and CMD launchers. Server execution is not yet confirmed.
