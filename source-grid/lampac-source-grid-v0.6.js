/**
 * Lampac Source Grid v0.6 (test build)
 * Compatible target: Lampa 2.x / 3.x, Samsung Tizen, Android TV, web.
 * Front-end only: DOES NOT modify Lampac, sources, proxies, accounts or UID.
 * It decorates the existing Lampac Filter->Source menu and keeps native item callbacks.
 *
 * Status dot = item.ghost as supplied by Lampac for THIS title. Green does not
 * mean that the video stream has been tested or can play on this device.
 * Quality badges = user-provided visual hints ONLY (NOT measured stream quality).
 * Remove entries from QUALITY_HINTS to suppress badges for those sources.
 */
(function () {
    'use strict';

    if (window.LampacSourceGridLoaded) return;

    var PLUGIN_ID = 'lampac-source-grid-v06';
    var MAX_ATTEMPTS = 100;
    var attempts = 0;
    var initialized = false;
    var gridOpen = false;
    var focusIndex = 0;
    var lastRoot = null;
    var originalSelectShow = null;
    var activationCount = 0;
    var hookMode = '';
    var originalControllerAdd = null;

    // Display examples from the user's screenshot; NOT video quality checks.
    var QUALITY_HINTS = {
        'filmix': 'HD', 'pizdatoehd': 'HD', 'kinobase': '4K',
        'mirage': '4K', 'phantom': '4K', 'zetflix': 'FHD',
        'aladin': '4K', 'flixcdn': 'FHD', 'kinogo': 'FHD',
        'videohub': 'FHD', 'pidtor': '4K', 'collaps': 'HD',
        'hdvb': 'FHD', 'rutube': 'HD', 'vkmovie': '4K',
        'vkvideo': '4K', 'vibix': 'FHD', 'kinotochka': 'HD'
    };

    var extraConfig = window.LampacSourceGridConfig || {};
    if (extraConfig.qualityHints && typeof extraConfig.qualityHints === 'object') {
        for (var name in extraConfig.qualityHints) {
            if (Object.prototype.hasOwnProperty.call(extraConfig.qualityHints, name)) {
                QUALITY_HINTS[name.toLowerCase()] = extraConfig.qualityHints[name];
            }
        }
    }

    var CSS = [
        '/* Lampac Source Grid v0.6: scoped to one native source picker */',
        '.lsg-panel .selectbox__content{width:94vw!important;max-width:1450px!important;}',
        '.lsg-panel .selectbox__head{box-sizing:border-box;}',
        '.lsg-panel .lsg-help{font-size:.68em;opacity:.76;margin-top:.48em;line-height:1.35;}',
        '.lsg-panel .scroll__body{display:-webkit-flex!important;display:flex!important;-webkit-flex-wrap:wrap;flex-wrap:wrap;align-content:flex-start;}',
        '.lsg-panel .selectbox-item.lsg-card{box-sizing:border-box!important;position:relative!important;',
        'display:-webkit-flex!important;display:flex!important;-webkit-align-items:center;align-items:center;',
        'width:calc(33.333% - .9em)!important;min-width:0!important;min-height:4.05em!important;',
        'margin:.36em!important;padding:.82em 2em .82em .85em!important;border-radius:.65em!important;',
        'border:2px solid rgba(255,255,255,.09)!important;background:rgba(255,255,255,.09)!important;',
        'box-shadow:none!important;overflow:hidden!important;}',
        '.lsg-panel .lsg-card .selectbox-item__title{display:block;overflow:hidden;',
        'white-space:nowrap;text-overflow:ellipsis;font-size:1em!important;line-height:1.32!important;flex:1;}',
        '.lsg-panel .lsg-card .selectbox-item__subtitle{display:none!important;}',
        '.lsg-panel .lsg-card .lsg-quality{display:inline-block;flex-shrink:0;',
        'margin-right:.62em;padding:.30em .50em;background:rgba(255,255,255,.18);',
        'border-radius:.30em;font-size:.72em;font-weight:700;line-height:1.15;',
        'border:1px solid rgba(255,255,255,.22)!important;box-sizing:border-box;white-space:nowrap;}',
        '/* Traffic-light colors ONLY on the quality badges; original tiles stay dark. */',
        '.lsg-panel .lsg-card .lsg-quality--2160{background:#ff1744!important;',
        'border-color:#ff6682!important;color:#fff!important;}',
        '.lsg-panel .lsg-card .lsg-quality--1080{background:#ffeb00!important;',
        'border-color:#fff56f!important;color:#171600!important;}',
        '.lsg-panel .lsg-card .lsg-quality--720{background:#08e65a!important;',
        'border-color:#7cff9b!important;color:#071e0e!important;}',
        '.lsg-panel .lsg-card .lsg-quality--480{background:#9098a5!important;',
        'border-color:#c7ccd6!important;color:#101820!important;}',
        '.lsg-panel .lsg-card .lsg-dot{position:absolute;right:.75em;top:50%;',
        'height:.5em;width:.5em;margin-top:-.25em;border-radius:50%;',
        'background:#33d488;box-shadow:0 0 0 2px rgba(51,212,136,.12);}',
        '.lsg-panel .lsg-card.lsg-ghost{opacity:.37!important;}',
        '.lsg-panel .lsg-card.lsg-ghost .lsg-dot{background:#888;box-shadow:none;}',
        '.lsg-panel .lsg-card.focus,.lsg-panel .lsg-card:focus,',
        '.lsg-panel .lsg-card.selected.focus{opacity:1!important;',
        'border-color:rgba(255,255,255,.95)!important;background:rgba(255,255,255,.24)!important;}',
        '.lsg-panel .lsg-card.selected:not(.focus){border-color:rgba(132,188,255,.56)!important;}',
        '@media(max-width:800px){.lsg-panel .selectbox-item.lsg-card{width:calc(50% - .9em)!important;}}',
        '@media(max-width:520px){.lsg-panel .selectbox__content{width:95vw!important;}',
        '.lsg-panel .selectbox-item.lsg-card{width:calc(100% - .9em)!important;}}'
    ].join('\n');

    function nodeRoot() {
        if (window.Lampa && Lampa.Select && typeof Lampa.Select.render === 'function') {
            var element = Lampa.Select.render(true);
            if (element && element.jquery) return element[0];
            if (element && element.nodeType === 1) return element;
        }
        return document.querySelector('body > .selectbox');
    }

    function normalizeName(value) {
        return (value || '').toString().toLowerCase().replace(/[^a-z0-9]/g, '');
    }

    function qualityFor(item) {
        var raw = (item.title || '').toString();
        // Explicit resolution shown in the source title takes precedence.
        // It is a display label, not independent stream-quality verification.
        var exact = raw.match(/(?:^|[^0-9])(2160|1080|720|480)\s*p?(?=$|[^0-9])/i);
        if (exact) return exact[1] + 'p';

        var named = raw.match(/(?:^|[^a-z0-9])(?:4k|uhd|fhd|full\s*hd|hd|sd)(?=$|[^a-z0-9])/i);
        if (named) {
            var val = named[0].toUpperCase().replace(/\s+/g, '');
            if (/4K|UHD/.test(val)) return '4K';
            if (/FHD|FULLHD/.test(val)) return 'FHD';
            if (val === 'HD') return 'HD';
            if (val === 'SD') return 'SD';
        }

        var key = normalizeName(item.source);
        var hint = QUALITY_HINTS[key];
        if (!hint) hint = QUALITY_HINTS[normalizeName(raw)];
        hint = (hint || '').toString().toUpperCase();
        if (/^(4K|UHD|2160P)$/.test(hint)) return hint === 'UHD' ? '4K' : hint === '2160P' ? '2160p' : hint;
        if (/^(FHD|FULLHD|1080P)$/.test(hint)) return hint === '1080P' ? '1080p' : 'FHD';
        if (/^(HD|720P)$/.test(hint)) return hint === '720P' ? '720p' : 'HD';
        if (/^(SD|480P)$/.test(hint)) return hint === '480P' ? '480p' : 'SD';
        return '';
    }

    function qualityTier(label) {
        if (/^(2160p|4K)$/.test(label)) return '2160';
        if (/^(1080p|FHD)$/.test(label)) return '1080';
        if (/^(720p|HD)$/.test(label)) return '720';
        if (/^(480p|SD)$/.test(label)) return '480';
        return '';
    }

    function isSourcePicker(o) {
        // Lampac NG supplies source IDs (source), text (title) and show state
        // (ghost). Older clients can omit ghost; don't reject the entire menu.
        if (!o || !o.items || o.items.length < 2) return false;
        var items = o.items, total = 0, sources = 0, status = 0;
        for (var i = 0; i < items.length; i++) {
            var item = items[i];
            if (!item || item.hide || item.separator) continue;
            total++;
            if (typeof item.source === 'string' && item.source.length &&
                typeof item.title === 'string') sources++;
            if (typeof item.ghost === 'boolean') status++;
        }
        if (total < 2 || sources !== total) return false;
        // Presence of the Lampac ghost field is strong evidence and does not
        // depend on the current Lampa activity/component name.
        if (status > 0) return true;
        // Fallback only for clients with legacy sort entries without ghost.
        var component = '';
        try {
            var active = Lampa.Activity && Lampa.Activity.active && Lampa.Activity.active();
            component = active && active.component ? String(active.component) : '';
        } catch (ignore) {}
        return /online|lampac/i.test(component);
    }

    function cleanup() {
        gridOpen = false;
        focusIndex = 0;
        if (!lastRoot) return;
        lastRoot.classList.remove('lsg-panel');
        var legend = lastRoot.querySelector('.lsg-help');
        if (legend && legend.parentNode) legend.parentNode.removeChild(legend);
        var cards = lastRoot.querySelectorAll('.lsg-card');
        for (var i = 0; i < cards.length; i++) {
            cards[i].classList.remove('lsg-card', 'lsg-ghost');
        }
    }

    function decorate(o, suppliedRoot) {
        var root = suppliedRoot && suppliedRoot.jquery ? suppliedRoot[0] : (suppliedRoot || nodeRoot());
        if (!root) return;
        lastRoot = root;
        root.classList.add('lsg-panel');
        var list = root.querySelectorAll('.scroll__body > .selectbox-item');
        var visible = [];
        for (var j = 0; j < o.items.length; j++) {
            if (!o.items[j].hide && !o.items[j].separator) visible.push(o.items[j]);
        }
        if (list.length !== visible.length) {
            // Do not alter the selection if its DOM doesn't match the source data.
            cleanup();
            return;
        }
        // Rename only the confirmed Lampac source picker; native menu logic stays intact.
        var titleNode = root.querySelector('.selectbox__title');
        if (titleNode) titleNode.textContent = 'Выбор источника';
        for (var i = 0; i < visible.length; i++) {
            var item = visible[i], el = list[i];
            el.classList.add('lsg-card');
            if (item.ghost) el.classList.add('lsg-ghost');
            else el.classList.remove('lsg-ghost');

            var quality = qualityFor(item);
            var heading = el.querySelector('.selectbox-item__title');
            if (quality && heading) {
                var badge = document.createElement('span');
                badge.className = 'lsg-quality' + (qualityTier(quality) ? ' lsg-quality--' + qualityTier(quality) : '');
                badge.textContent = quality;
                el.insertBefore(badge, heading);
            }
            var dot = document.createElement('span');
            dot.className = 'lsg-dot';
            dot.setAttribute('aria-hidden', 'true');
            el.appendChild(dot);
            el.setAttribute('title', (item.title || '') + (item.ghost ? ' — нет результата' : ' — есть результат'));
            (function (index, element) {
                // Read original focus events: keep remote/keyboard/scroll handling native.
                if (window.jQuery) jQuery(element).on('hover:focus', function () { focusIndex = index; });
            })(i, el);
            if (item.selected) focusIndex = i;
        }
        var head = root.querySelector('.selectbox__head');
        if (head && !head.querySelector('.lsg-help')) {
            var legend = document.createElement('div');
            legend.className = 'lsg-help';
            var resultCount = 0;
            for (var k = 0; k < visible.length; k++) if (!visible[k].ghost) resultCount++;
            legend.textContent = 'Результат: ' + resultCount + '/' + visible.length + '  ·  Разрешение — из названия или справочно';
            head.appendChild(legend);
        }
        gridOpen = true;
        activationCount++;
        window.LampacSourceGridDiagnostics.activations = activationCount;
        if (window.console && console.log) {
            console.log('[Lampac Source Grid v0.6] Decorated ' + visible.length + ' sources');
        }
    }

    function columns() {
        var width = window.innerWidth || document.documentElement.clientWidth || 1280;
        return width <= 520 ? 1 : width <= 800 ? 2 : 3;
    }

    function moveGrid(direction) {
        var root = nodeRoot();
        if (!gridOpen || !root || !root.classList.contains('lsg-panel')) return false;
        var items = root.querySelectorAll('.scroll__body > .selectbox-item.lsg-card');
        if (!items.length) return false;
        var index = focusIndex;
        for (var i = 0; i < items.length; i++) {
            if (items[i].classList.contains('focus')) { index = i; break; }
        }
        var count = columns(), next = index;
        if (direction === 'left' && index % count > 0) next = index - 1;
        else if (direction === 'right' && index % count < count - 1 && index + 1 < items.length) next = index + 1;
        else if (direction === 'up') next = Math.max(0, index - count);
        else if (direction === 'down' && index + count < items.length) next = index + count;
        else if (direction === 'down' && Math.floor(index / count) < Math.floor((items.length - 1) / count)) next = items.length - 1;
        if (next !== index) {
            focusIndex = next;
            Lampa.Controller.collectionFocus(items[next], root);
        }
        return true;
    }

    function installControllerPatch() {
        if (!Lampa.Controller || typeof Lampa.Controller.add !== 'function') return;
        originalControllerAdd = Lampa.Controller.add;
        Lampa.Controller.add = function (name, handlers) {
            if (name === 'select' && handlers && !handlers.__lsg_wrapped) {
                var directions = ['left', 'right', 'up', 'down'];
                for (var i = 0; i < directions.length; i++) {
                    (function (direction) {
                        var nativeMove = handlers[direction];
                        handlers[direction] = function () {
                            if (gridOpen && document.body.classList.contains('selectbox--open') && moveGrid(direction)) return;
                            if (typeof nativeMove === 'function') return nativeMove.apply(this, arguments);
                        };
                    })(directions[i]);
                }
                handlers.__lsg_wrapped = true;
            }
            return originalControllerAdd.apply(this, arguments);
        };
    }

    function install() {
        if (initialized || !window.Lampa || !Lampa.Select || !Lampa.Controller) return;
        if (typeof Lampa.Select.show !== 'function' || typeof Lampa.Controller.add !== 'function') return;
        initialized = true;
        window.LampacSourceGridLoaded = PLUGIN_ID;
        window.LampacSourceGridDiagnostics = {version:'0.6', hook:'initializing', activations:0};
        var style = document.createElement('style');
        style.id = PLUGIN_ID + '-style';
        style.appendChild(document.createTextNode(CSS));
        (document.head || document.documentElement).appendChild(style);
        installControllerPatch();

        // Prefer Lampa's native events. This also works if Lampa.Filter keeps
        // its own reference to Select.show or another extension wraps it later.
        // Modern Lampa sends fullshow AFTER the selectbox HTML is constructed.
        var listener = Lampa.Select.listener;
        if (listener && typeof listener.follow === 'function') {
            hookMode = 'native-fullshow';
            listener.follow('fullshow', function (event) {
                if (!event || !isSourcePicker(event.active)) return;
                cleanup();
                decorate(event.active, event.html);
            });
            listener.follow('hide', cleanup);
        } else {
            // Legacy fallback, only when the Select listener API is absent.
            hookMode = 'legacy-show';
            originalSelectShow = Lampa.Select.show;
            Lampa.Select.show = function (options) {
                cleanup();
                if (!isSourcePicker(options)) return originalSelectShow.apply(this, arguments);
                var originalFullDraw = options.onFullDraw;
                var copy = {};
                for (var key in options) {
                    if (Object.prototype.hasOwnProperty.call(options, key)) copy[key] = options[key];
                }
                copy.onFullDraw = function () {
                    if (typeof originalFullDraw === 'function') originalFullDraw.apply(this, arguments);
                    decorate(copy);
                };
                return originalSelectShow.call(this, copy);
            };
        }
        window.LampacSourceGridDiagnostics.hook = hookMode;
        if (window.console && console.log) console.log('[Lampac Source Grid] Loaded v0.6, mode=' + hookMode);
        try {
            if (Lampa.Noty && typeof Lampa.Noty.show === 'function')
                Lampa.Noty.show('Source Grid v0.6 загружен');
        } catch (ignore) {}

    }

    function boot() {
        if (initialized) return;
        if (window.Lampa && Lampa.Select && Lampa.Controller) {
            install();
            if (initialized) return;
        }
        attempts++;
        if (attempts < MAX_ATTEMPTS) setTimeout(boot, 200);
    }
    boot();
})();