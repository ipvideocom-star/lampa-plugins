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
