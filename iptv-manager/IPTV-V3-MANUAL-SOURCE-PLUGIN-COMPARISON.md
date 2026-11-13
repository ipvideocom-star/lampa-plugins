# IPTV v3 — выбор плагина до выбора плейлиста (10.11.2026)

## Решение пользователя

1. Пользователь **сам выбирает** M3U и проверяет его на своём ПК, с домашнего IP через VLC (или другой проигрыватель).
2. Пользователь **сам выбирает** внешний EPG/XMLTV. Никакого обязательного самодельного EPG-агрегатора, самовольных подмен потоков, автоматического подбора альтернатив или пересборки M3U.
3. **Сначала сравниваем IPTV-плагины Lampa:** до четырёх пунктов в левом меню, каждому — одинаковый действующий тестовый M3U. Там, где поддерживается, назначается и одинаковый внешний EPG. Затем пользователь выбирает **один** плагин.
4. Только **после выбора плагина** пользователь присылает собственноручно проверенные M3U и EPG, которые мы публикуем без изменения содержимого, с проверкой доступности и резервной копией.
5. Автоматическое переключение настроек Samsung — только через существующий Plugin Manager / UID. Официальная Lampa и MSX на одном Samsung; других клиентов не менять.

## Текущее состояние (снимок, не новая публикация)

- В Samsung через Auto Setup v11 используется тестовый M3U `IPTV-Samsung-TEST-v22.m3u` (257 записей).
- EPG: `IPTV-Samsung-Guide-v22.xml`, разовая публикация, актуальность в последующие дни **не гарантирована**.
- Сохранены прежние live плейлисты, пилот HLS Relay, исходники и резервные копии.
- Не изменять `C:\lampacNG-next`, Caddy, task scheduler, действующий `plugins.json` до тестов и создания backup.

## Кандидаты для теста (не установлены этим документом)

| № | Вариант | Источник | Пользовательская M3U | Внешняя EPG | Риски / наблюдения |
|---|---|---|---|---|---|
| 1 | IPTV+ (контроль) | наша текущая конфигурация, 1.2.x | да | да, текущий XMLTV | оставить без изменений |
| 2 | MaxTV | https://github.com/maks-mk/lampatv, pinned JS `https://cdn.jsdelivr.net/gh/maks-mk/lampatv@15f9841b568fb1c6cca97aa1dcb3a615918d06c0/tv.js` | да | **требует проверки**: текущий код использует API `epg.rootu.top` | собственный пункт меню `MaxTV`, имена и storage в namespace `max_iptv`; внешний EPG не обещать |
| 3 | Lampa IPTV (smackftw) | https://github.com/smackftw/lampa_iptv, `dist/lampa-iptv.js` | да | да: Custom URL или EPG из M3U | исходник `src/index.js` автоматически открывает IPTV при старте — нужно отключить этот побочный эффект в тестовой копии; меню `IPTV` можно переименовать |
| 4 | резерв | `https://plugin.rootu.top/tv.js` — независимый кандидат после проверки кода | вероятно да | нужно подтвердить | не устанавливать без source audit; возможно использует `epg.rootu.top` |

**CUB IPTV исключён по предыдущему решению пользователя.**


## Фактическая конфигурация после успешной установки сравнения v1.2 (10.11.2026)

Серверный отчёт `RESULT: READY_FOR_THREE_PLUGIN_SAMSUNG_TEST` подтвердил, что policy entry `iptv_compare_v12` добавлена, а Policy Server выдаёт её двум UID Samsung. Это **не** подтверждает, что все JS реально запустились на телевизоре (Samsung пока не проверен).

| Клиент | Хранимый параметр | Назначенное значение |
|---|---|---|
| IPTV+ | `iptv_plus_playlist` | `https://lampa.v6.army/iptv/playlists/IPTV-Samsung-TEST-v22.m3u` (через существующий Auto Setup v11) |
| IPTV+ | `iptv_plus_epg` | `https://lampa.v6.army/iptv/playlists/IPTV-Samsung-Guide-v22.xml` (v11) |
| MaxTV | `max_iptv_list_url_0` | тот же `IPTV-Samsung-TEST-v22.m3u` |
| MaxTV | EPG | **не настраивается на тот же XMLTV**: upstream MaxTV использует `epg.rootu.top/api/epg` и не содержит конфигурации custom XMLTV |
| IPTV 3 | `liptv_m3u_url` | тот же `IPTV-Samsung-TEST-v22.m3u` |
| IPTV 3 | `liptv_epg_url` / `liptv_epg_source` | тот же `IPTV-Samsung-Guide-v22.xml` / `custom` |

Все параметры вторичных клиентов назначает загрузчик `iptv-compare/iptv-samsung-compare-loader-v12.js`, с условием UID по прежним двум fingerprints и **без** замены пользовательских custom URLs. Назначение происходит **на клиенте при запуске Lampa**, не непосредственно в настройках телевизора с сервера.

**Ограничение честного сравнения:** плейлист и видео одинаковы, но сравнение EPG одинаковым XMLTV возможно только между IPTV+ и IPTV 3. EPG MaxTV считается отдельной функциональностью этого клиента, а не ошибкой EPG v22. Дополнительные постоянные `IPTV-UA.m3u` и `IPTV-RU-Pilot-v1.m3u` намеренно не подключены одновременно: исходные MaxTV и IPTV 3 рассчитаны на один URL на источник в данной конфигурации. Сам комбинированный файл уже объединяет RU и UA.

Действующая программа v22 является **статическим** XMLTV и устаревает. В сравнительном эксперименте использовать как контроль совместимости и не оценивать точность эфирного расписания без свежего файла.

## Порядок технических действий

1. Проверить код плагинов на Samsung/Tizen и MSX: отдельные Component/Menu IDs, независимый Storage, отсутствие автоперехвата начального экрана и конфликтов горячих кнопок в режиме просмотра другого плагина.
2. Зафиксировать минимальный набор для теста: IPTV+ + MaxTV + Lampa IPTV. Если четвёртый безопасен и совместим — добавить.
3. Подготовить отдельные UID-scoped loader/adapter, но **не удалять** нынешний v11, Likhtar, Source Grid и другие плагины.
4. Использовать тот же **существующий** тестовый плейлист v22 (без правки URL видеопотоков), а внешний EPG v22 — только там, где плагин умеет; пометить его устаревшую дату, не выдавая за свежий гид.
5. Прежде чем менять живой `C:\ReservLampac\PluginManager\plugins.json`, сделать backup и локальную проверку двух UID. Установка и откат — через однократный CMD-запускатель на Windows Server 2022, с понятным отчётом.
6. Проверить на Samsung наличие отдельных пунктов меню, запуск основных RU/UA, поведение кнопок пульта и EPG. Не требовать полного просмотра 257 каналов.
7. Победивший плагин оставить; остальные удалить из конфигурации политики с сохранением rollback.
8. Только после выбора одного плагина — перейти на пользовательские вручную проверенные M3U и EPG. Если необходимо обновлять статический EPG с источника, делать только прозрачное скачивание без изменения семантики.

## Не делать

- Не вводить UID вручную на Samsung.
- Не запускать заново огромные проверки потоков/поиск альтернатив, не менять маршрутизацию, HLS Relay или 3proxy без новой просьбы.
- Не считать успешную загрузку EPG доказательством правильной даты: отдельно проверять эфирное время, часовой пояс Europe/Kyiv и границы сегодняшнего/завтрашнего дня.
- Не заявлять, что плагины совместимы одновременно, пока не пройден тест на Samsung.

## Samsung Tizen compatibility, 11.11.2026

- Реальный Samsung показал `SyntaxError: Unexpected token .` из `lampa-iptv-third-party-comparison-v1.js`; следствие — третий пункт IPTV 3 не появлялся.
- Причина: `?.` в 2 местах XMLTV parser. В `iptv-compare/lampa-iptv-third-party-comparison-v2-tizen.js` оба вхождения заменены совместимыми выражениями, код прошёл JS syntax compile check.
- `iptv-samsung-compare-loader-v12.js` на ветке main **обновлён на новый pinned IPTV 3 v2**, поэтому при использовании GitHub Pages установки на сервере не требуется. При закреплённом старом commit-CDN v12 потребуется миграция на `iptv-samsung-compare-loader-v13.js` через Plugin Manager.
- Фолбэк: пакет `IPTV-Samsung-IPTV3-Tizen-FIX-v13.zip` (один CMD, backup, проверка обеих UID). Его задача — отключить управляемую политику v12 и разрешить v13, не трогая IPTV+, MaxTV, M3U, XMLTV. Старый v12 должен остаться в `managed` для удаления клиентом при синхронизации.
- После первой перезагрузки возможно кратковременное появление старой ошибки, пока Plugin Manager удалит старый JS. Повторный перезапуск должен загружать только v13, если политика успешно применена. Работа на реальном Samsung ещё требует проверки.

## Samsung IPTV 3: remote scroll fix (11.11.2026)

- Реальный Samsung: после исправления `content`-контроллера v3 перемещение пультом работает, но фокус уходит ниже первого экрана (~10 каналов), а список не прокручивается.
- Установлена причина: `Navigator.move` менял фокус, но DOM-контейнеру `.liptv-channels` не задавался `scrollTop`; у flex-элементов требовалось `min-height:0`.
- Исправленная версия: `iptv-compare/lampa-iptv-third-party-comparison-v4-tizen-scroll.js`. Её обработчик `hover:focus` прокручивает нужный контейнер через `scrollTop` / `getBoundingClientRect`, с запасом 12px и ограничением в высоту списка. Поддерживает также группы и режим сетки, без влияния на документ/другие плагины.
- Обновлены существующие загрузчики `iptv-samsung-compare-loader-v12.js` и `-v13.js`: URL IPTV 3 теперь pinned к v4. Политика сервера, автонастройки IPTV+, MaxTV, M3U и XMLTV не изменялись.
- В автономной проверке JS-синтаксиса и сценариях прокрутки (вверх/вниз, низ списка, отсутствие метода closest на старом Tizen) ошибок нет. **Фактический результат Samsung требует подтверждения**.

## Samsung IPTV 3 v5 — ReferenceError after auto-scroll (12.11.2026)

- При запуске IPTV 3 пользователь на Samsung получил полноэкранную ошибку `ReferenceError: scrollLiptvFocusedItem is not defined`, стек из `lampa-iptv-third-party-comparison-v4-tizen-scroll.js` в обработчике `hover:focus`.
- Причина: обработчик `hover:focus` в `createMainScreen()` ссылался на функцию, объявленную внутри вложенного `init()`. Функция отсутствовала в лексической области обработчика.
- Исправление: `iptv-compare/lampa-iptv-third-party-comparison-v5-tizen-scroll-scope.js`. Общая функция `scrollLiptvFocusedItem` перенесена на уровень внешнего замыкания, до `createMainScreen`, без ссылки на приватную переменную `_body`. Введён обход родителей без `Element.closest`, чтобы не зависеть от старого Tizen.
- Проверено: синтаксис всего JS-файла; обработчик фокуса реального `createMainScreen` в мок-среде, прокрутка вверх и вниз, видимый элемент без прокрутки, fallback без `closest`. Все проверки PASS. **На Samsung ещё не подтверждено.**
- Текущие файлы `iptv-samsung-compare-loader-v12.js` и `-v13.js` обновлены только в строке pinned JS `LIPTV`: на v5. M3U, XMLTV, IPTV+, MaxTV и политики на сервере не изменялись.

## Community three-source comparison — 13.11.2026

User supplied three raw M3U files to compare on Samsung, **without filtering, re-sorting or probing streams**.

| Archive original | M3U entries | Native categories | EPG header |
|---|---:|---:|---|
| community_content (19).m3u | 3276 | 16 through `#EXTGRP:` | none |
| community_content (20).m3u | 3246 | 56 `group-title` categories | `http://epg.one/epg.xml.gz` |
| community_content (21).m3u | 3246 | 56 `group-title` categories | `http://epg.one/epg.xml.gz` |

File 20 and 21 have matching channel names/order, but 3244 stream paths use differing access-key-like segments. **Do not treat them as independent channel catalogs.** Private keys and raw M3U files are never committed to public GitHub.

Samsung design: add **one** left-menu entry `IPTV — три плейлиста`; it opens a 3-option picker then a single source in IPTV 3. Do not concatenate 9768 entries into a gigantic TV DOM. Existing IPTV+/MaxTV and original 257-channel IPTV 3 remain untouched. Plugin `iptv-compare/lampa-iptv-third-party-comparison-v6-source-selector.js` accepts transient `compare_m3u`, `compare_epg` component constructor options (no persistent Storage mutation), supports `#EXTGRP` and unique UI keys for streams sharing tvg-id. Regular IPTV 3 v5 remote navigation/scroll remains supported. Generic selection component `iptv-compare/iptv-community-picker-v1.js` contains no stream tokens.

Windows Server 2022 installer ZIP (distributed through the chat, not on GitHub) writes the original M3Us to *new unguessable filenames* under `C:\IPTV-Manager\public\playlists\` and writes one locally generated JS picker with exact URLs. Adds the scoped policy `iptv_community_three_sources_v1` to `C:\ReservLampac\PluginManager\plugins.json` after a backup; Policy Server must deliver to both Samsung UIDs. Other clients are skipped by the picker. Rollback removes only this new policy and files.

Security limitation: unguessable static URLs are **not authentication**. Anyone who knows them can retrieve a playlist; source paths may contain revocable access tokens. No secrets in GitHub. Content includes adult-labelled groups (20/21); no filtering per current user request. Most stream URLs and both EPG headers are HTTP: TV HTTPS mixed-content or compressed XMLTV compatibility is not guaranteed. No server/TV integration has yet been confirmed for the new package.

## 13.11.2026 — Source #19 retained across three independent clients

User-tested playback favors M3U #19, which has **3276** `#EXTINF` entries (3274 ordinary streams + 2 informational entries). #20/#21 have 3246 entries each and identical ordered channels and tvg-ids; 3244 media URLs differ in their access-key-like path segments. #19 and #20 share exactly **2615 normalized case-insensitive names**; 661 titles occur only in #19, 631 only in #20. These counts compare M3U metadata, **not** programme identity, rights, uptime or real availability.

Upstream distribution concentration: #19 sends 3274 stream URLs to `7b4ecc7c.edmonst.net`. #20/21 send 3244 to `sewv654wfcsdwfi87fwvgbngh.siauliairsavlt.pw`. The two common information links use `v.mover.uz`. Actual underlying broadcasters may be different; no assumptions about provider ownership.

EPG: #19 does not declare XMLTV and all its 3274 ordinary entries lack tvg-id. #20/21 declare `http://epg.one/epg.xml.gz`; 3242 numeric tvg-id, 2 ordinary entries missing ids, 2 informational entries `no_epg`. Actual XMLTV coverage not verified.

New upgrade ZIP `IPTV-Community19-ThreePlayers-KEEP-19-v1.zip` reuses the original unmodified, previously published #19 M3U on the user's Windows Server 2022. Installer requires existing `C:\ReservLampac\IPTVPlus\CommunityCompare\latest-install.json`. Stages isolated IPTV+ #19 / MaxTV #19 client variants locally from pinned GitHub revisions, plus one UID-scoped menu loader. Old 257-channel IPTV+/MaxTV/IPTV3 and EPG settings must remain unmodified. IPTV3 uses transient `compare_m3u` Activity override.

After HTTPS SHA and two-UID policy verification, it removes the previous three-source selector policy and moves *public* #20/#21 M3Us and picker JS into a private backup under `CommunityCompare\Selected19-*\Retired-Sources-20-21` (never permanently deletes). Full rollback is supplied. No original M3U, media access token or secret URL is stored in GitHub; published playlist URLs are unguessable but are **not authenticated**. Source #19 EPG will vary by plugin; no external EPG is silently assigned.

Full comparative HTML file generated in the chat from uploaded M3U sources; includes all channel names, groups, source hosts and EPG metadata without full stream URLs or credentials.

All code/installer validation is static or simulated until user's next server run and Samsung test confirms. No server mutation was performed directly from this chat.

## 13.11.2026 — fourth Samsung IPTV client: IPTV PRO Universal #19

Fourth candidate: [Artrax90/lampa IPT V PRO Universal](https://github.com/Artrax90/lampa/blob/001a67d5e0fb73e22ecb1b317562d544617f97f9/iptv.js), exact upstream Git blob SHA1 `956aa4db4f6a9c3d07fa6512bd567012ce640456`.

User approved testing it as independent **fourth** client on the same #19 M3U (3276 entries) for **two Samsung Lampa UIDs only**, alongside unchanged IPTV+, MaxTV and IPTV 3. The once-off Windows Server 2022 installer is delivered in chat as `IPTV-Samsung-4th-Player-IPTVPRO-19-v1.zip`; not committed to GitHub to avoid exposing selected opaque M3U URLs. The server downloads the immutable upstream source, validates its Git blob, and patches an *isolated* `iptv_universal_19` component/controller, unique storage `iptv_universal_v416_19` and left-menu entry `IPTV PRO - #19`. Built-in MEGA, RU IPTV Org and PRISMA preset sources are removed from this isolated copy and replaced with exactly the existing #19 URL. **Crucial:** original IPTV PRO parser does not parse `#EXTGRP`; source #19 uses it for 3274 channels. Installer patches `parsePlaylist` to recognize this tag and maintain original groups. Also patches plugin boot-time `window.appready` support for latest Lampa, preserving Tizen-compatible JS syntax. No copy of third-party source is committed here.

Preflight checks preserve original #19 M3U SHA256 and count; published client JS/loader checked by HTTPS SHA; adds only `iptv_pro_universal_19_v1` to `C:\\ReservLampac\\PluginManager\\plugins.json` with a policy backup and runtime verification against the two Samsung UIDs. Loader FNV hash checks prevent execution for other devices. An independent rollback is included. Do not change Lampac, Caddy, production playlists, HLS Relay, EPG or schedules. EPG availability for #19 is not guaranteed because original M3U has no XMLTV/tvg-id.

**Validation status:** source patch syntax and #EXTGRP parsing passed code checks; UID-scoped loader tested in Node for two allowed and three denied UID strings. Windows PowerShell runtime and actual Samsung navigation/playback **not yet confirmed**; require installer report `READY_FOR_SAMSUNG_FOUR_IPTV_CLIENTS`, then Samsung acceptance test.

## 13.11.2026 — user selects IPTV PRO #19 as sole Samsung IPTV client

User-tested IPTV PRO Universal (#19: 3276 original M3U entries, 16 categories) and elected to keep it as the **sole IPTV interface on both Samsung Lampa UIDs**. Do not add new playlists or change XMLTV/EPG yet. Keep source #19 unchanged for later manual curation. Previous IPTV+, IPTV 3, MaxTV (both 257-channel and #19 variants) are to be **de-registered on Samsung**, but all raw original M3U/XMLTV and backup files are retained. Preserve other non-IPTV plugins (Likhtar, Source Grid, etc.) and other devices' IPTV access.

Observed startup error: `Community-Picker-9db6aba44a524e43a5d67efbcff13c69.js` fails to load: the earlier three-source upgrade moved the JS from public Caddy, but an older Lampa client retained its URL in the local plugin registry. This is not an IPTV PRO playback/EPG error.

Prepared Windows Server 2022 cleanup: `IPTV-KeepOnly-IPTVPRO19-Samsung-Cleanup-v1.zip` with `START-KeepOnly-IPTVPRO19.cmd` and rollback. It verifies the successful IPTV PRO #19 installation manifests and original source SHA256, republishes a harmless no-op JS at the exact old Community-Picker URL (without any stream tokens), reintroduces an *inactive policy tombstone* for the retired URL, adds two Samsung UIDs to `exclude_uids` of older IPTV plugin policy records while leaving other UID behavior untouched, then confirms runtime policy for both Samsung UIDs has only `iptv_pro_universal_19_v1` allowed and all retired URLs represented in `managed` for client-side removal. If the managed/unmanaged behavior is not as expected, **fails safely and rolls back the old policy**. It never deletes the old JS before client sync, and never changes Lampac, Caddy configuration, services, schedules, M3U or XMLTV.

**Status:** ZIP produced with archive-integrity validation. PowerShell runtime and Samsung Lampa acceptance not yet performed. Require `READY_KEEP_ONLY_IPTV_PRO19_ON_SAMSUNG` in server report; then fully restart both Samsung Lampa variants. There may be a one-time stale menu until a second restart due to client cache.

## 13.11.2026 — IPTV PRO #19 v2 Samsung menu/empty-list repair

Samsung TV screenshots after the earlier cleanup show **three** separate `IPTV PRO - #19` entries in the side menu, while the player returns empty. IPTV+ still works and the user explicitly wishes to keep it as a comparator; do **not** remove/disable IPTV+.

Root causes found in the exact IPTV PRO v1 server installer and upstream `Artrax90/lampa/iptv.js`:

1. v1 replaced three upstream defaults with only **one** `Плейлист №19` but did not remove calls `ensureBuiltinPlaylist(raw.playlists, def.playlists[1])` and `[2]`. `ensureBuiltinPlaylist` accesses `builtin.url`, so `loadConfig()` raises a `TypeError` on `undefined` before channel rendering.
2. Upstream `$('.menu .menu__list').append(item)` appends/clones the menu item into **every** matching Lampa menu list; Samsung has more than one list. Fix: target the first menu list and prune duplicate entries.
3. `defaults().lastGroup = 'STAR_FAVORITES'` while favorites are empty. After load, activate the first nonempty actual #19 group instead of an empty Favorites pane.
4. IPTV PRO Universal intentionally does **not** register a separate Lampa `SettingsApi` component; configuration is inside the IPTV PRO interface.

One-click remediation produced as `IPTV-PRO19-Samsung-FIX-v2-OneClick.zip` with CMD installer, dated backup, exact previous JSON rollback, two-UID verification and new cache-busting JS filenames. It reads old server-deployed IPTV PRO variant and source #19 manifest, validates the original M3U SHA256 and 3276 entries, checks the safety patch anchors exactly once, writes a separate fixed IPTV PRO v2 JS and loader under new unique Caddy URLs, verifies both through HTTPS with SHA256. It **adds** `iptv_pro_universal_19_v2`, excludes the two Samsung UIDs from old `iptv_pro_universal_19_v1` (old URL stays `managed` for unregistration), and preserves all other policy records and installed IPTV+ behavior. Original streaming data, M3U/EPG and non-IPTV plugins remain unchanged. On success: `READY_IPTVPRO19_V2_MENU_AND_EMPTY_FIX`. Allow **two full Lampa restarts** for old registry cleanup. Keep v1 deployment backup for rollback.

Validation: reconstructed full JS syntax and removed invalid builtin references checked in V8; ZIP archive integrity checked. **Windows Server runtime and Samsung behavior not yet validated.**

## 13.11.2026 — IPTV PRO #19 v2 FAILED_SAFE and v2.1 rebuilt patch

v2 failed on the server in the **pre-publication** check with `ERROR: Installed IPTV PRO source is not our original v1 isolated client`; the screenshot confirms `RESULT: FAILED_SAFE` and v1 policy delivery for both Samsung UIDs. The v2 script required three brittle exact string matches in the old deployed JS: isolated storage key, localized title, and source URL. The individual failed condition was not logged, so **do not assume which of them changed**.

Prepared `IPTV-PRO19-Samsung-FIX-v21-Rebuild.zip`. Unlike v2, the repair **does not patch old JS or depend on matching its exact contents**. It checks v1 deployment manifest, current policy for two Samsung UIDs, exact #19 M3U SHA256/3276 entries, and the old loader path; then downloads the same immutable upstream `Artrax90/lampa@001a67d5...` JS, validates pinned Git blob SHA1 `956aa4db4f6a9c3d07fa6512bd567012ce640456`, rebuilds an isolated v2 plugin with only #19, fixes invalid `def.playlists[1/2]`, includes `#EXTGRP` parsing, initial nonempty group, and single-menu insertion, and verifies the new public JS/loader by SHA256. On success it allows v2 and de-registers v1 only for the two Samsung UIDs. It also removes the Samsung UIDs from exclusions of the existing `iptv_plus` policy record **if** that record is enabled, preserving IPTV+ per user's most recent explicit decision; no settings or URL of IPTV+ are changed. It never changes M3U, EPG, Caddy, Lampac, or non-IPTV policy entries. It has a policy backup and rollback. Expected success: `READY_IPTVPRO19_V21_REBUILT_FROM_PINNED_SOURCE`.

The planned rebuilt JavaScript patch was independently compile-checked and its source/anchor checks passed. The ZIP archive was checked. **Windows Server and Samsung actual runtime verification remain pending.**

## 13.11.2026 — standalone IPTV+ #19 for final comparison

User changed final comparison requirement: **retain IPTV PRO Universal #19 v2.1 exactly as installed**, **retain existing IPTV+ and its old 257-channel playlist/EPG exactly as installed**, and **add a new independent side-menu item IPTV+ - №19 with the original 3276 entries**. Do not enable MaxTV, IPTV 3, or other old comparison menus. Do not add other playlists now.

New one-click Windows Server 2022 archive: `IPTVPlus19-Standalone-Samsung-OneClick-v1.zip`. It reads `C:\\ReservLampac\\IPTVPlus\\CommunityCompare\\latest-selected19.json` and reuses the already published, separate `Community19-IPTVPlus-<nonce>.js` clone (its component is `iptv_plus_19`, and its M3U/EPG Storage namespace differs from original `iptv_plus`). Source #19 is re-verified SHA256 `6F9495E47524E7889C5A169C94E2E44D22ACB3467C3548DEC796AE88B53C6FD4` with **3276 EXTINF entries**, unchanged.

Only one new UID-guarded JS loader is published under the user's Caddy playlist route; it adds exactly one menu item `IPTV+ - №19` and lazily loads the previously installed isolated IPTV+ clone. It removes remnants of the retired `js-iptv19-plus/max/third` selector DOM items on startup but **does not** touch original IPTV+ or IPTV PRO menu elements. No player source is rewritten. Old community-three-client policy must remain excluded for both Samsung UIDs. The new enabled policy record is `iptv_plus_19_standalone_v1`, and is guarded client-side using the two Samsung UID fingerprints: off-target devices display no menu. Note that the Plugin Manager may still advertise the loader to other clients, as its schema does not support an explicit allowlist; the loader intentionally returns immediately for other UID values.

Preflight checks the previously repaired IPTV PRO v2 policy (`latest-iptvpro19-fix-v2.json`) and original IPTV+ policy are both delivered to each Samsung UID. All other `plugins.json` records are compared for semantic identity before update and left unchanged. HTTPS SHA256 verifies existing M3U, existing IPTV+ #19 JS and new loader. Full backup, conditional rollback and desktop report included. Expected server status: `READY_IPTVPLUS19_STANDALONE_SAMSUNG`.

Validation: Archive integrity verified; menu loader parsed by Node/V8, mocked both accepted Samsung UIDs and a third rejected UID, verified one menu, lazy load, two opens, and preservation of original IPTV+ storage. **PowerShell Server runtime and Samsung UI acceptance are not yet confirmed.**
