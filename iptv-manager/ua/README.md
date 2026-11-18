# UA Manager — категории, EPG и мониторинг

Текущий релиз (18.11.2026): global IPTV Украина, 158 каналов, девять групп. Около 20 каналов пользователь проверил на Samsung: все запустились. HLS-сбои Chrome рассматриваем отдельно. Старые IPTV №19/№14 и RU не трогаем.

## Категории
UA-Category-Overrides-v1.json — централизованная политика по 127 точным canonical tvg-id из известной 158-канальной коллекции. Остальные 31 сохраняют исходные группы, пока не проверены. Раздельные идентичности: ICTV vs ICTVSerialy, Maincast Sport vs Maincast Cybersport, 1Plus1Marafon vs 1Plus1Ukraina. Девять прежних групп сохраняются.

## EPG
Опубликовано 53/158 каналов с текущей программой; 105 пока без надёжного будущего расписания. Не принимать ошибочные региональные соответствия Suspilne Sport. Дополнительный публичный кандидат: https://iptv-org.github.io/epg/guides/ua/tvgid.ua.epg.xml, только безопасный read-only cross-match точных ID. Не делать автоматического объединения без контентной и идентификационной проверки.

## Готовый приватный аудит
Пакет UA-Manager-Review-v1-READONLY.zip создан в этой беседе. В нём Invoke-UA-Manager-Review-v1.ps1, UA-Category-Overrides-v1.json, README.md. Скрипт читает только C:\IPTV-Manager\public\playlists\IPTV-UA-NEW.m3u, IPTV-UA-EPG-NEW.xml и приватный снимок TVA. Результат — URL-free CSV по категориям и пробелам EPG и summary JSON в C:\IPTV-Manager\data\ua-autocatalog\v3\manager-review\review-*. Никаких изменений M3U, EPG, Caddy, Plugin Policy, задач или служб. PowerShell на пользовательском сервере ещё не запускался.

## План интеграции без дополнительных Scheduled Tasks
После верификации отчёта перенести одобренные категории в действующий Invoke-UA-AutoCatalog-v3.ps1 и в клиентский плагин, проверить сохранность всех URL, tvg-id и EPG. Затем улучшить 6-часовой EPG pipeline, интегрировать проверки TVA, источников и резервов в существующий Nightly IPTV Manager, а не заводить одноразовые процессы. AutoPublish OFF до отдельного разрешения на изменение потоков. Last-good, страховка и возврат изменений обязательны.

TVA Setanta: приоритет поиска, но сначала подтверждение правильного канала, текущей доступности и законности публичного доступа.
