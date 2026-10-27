/**
 * Lampac Source Grid v0.1 (test build)
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

    var PLUGIN_ID = 'lampac-source-grid-v01';
    var MAX_ATTEMPTS = 100;
    var attempts = 0;
    var initialized = false;
    var gridOpen = false;
    var focusIndex = 0;
    var lastRoot = null;
    var originalSelectShow = null;
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
        '/* Lampac Source Grid v0.1: scoped to one native source picker */',
        '.lsg-panel .selectbox__content{width:90vw!important;max-width:1250px!important;}',
        '.lsg-panel .selectbox__head{box-sizing:border-box;}',
        '.lsg-panel .lsg-help{font-size:.65em;opacity:.72;margin-top:.35em;line-height:1.4;}',
        '.lsg-panel .scroll__body{display:-webkit-flex!important;display:flex!important;-webkit-flex-wrap:wrap;flex-wrap:wrap;align-content:flex-start;}',
        '.lsg-panel .selectbox-item.lsg-card{box-sizing:border-box!important;position:relative!important;',
        'display:-webkit-flex!important;display:flex!important;-webkit-align-items:center;align-items:center;',
        'width:calc(33.333% - .7em)!important;min-width:0!important;min-height:3.45em!important;',
        'margin:.32em!important;padding:.65em 2em .65em .8em!important;border-radius:.48em!important;',
        'border:2px solid rgba(255,255,255,.09)!important;background:rgba(255,255,255,.09)!important;',
        'box-shadow:none!important;overflow:hidden!important;}',
        '.lsg-panel .lsg-card .selectbox-item__title{display:block;overflow:hidden;',
        'white-space:nowrap;text-overflow:ellipsis;font-size:1em!important;line-height:1.25!important;flex:1;}',
        '.lsg-panel .lsg-card .selectbox-item__subtitle{display:none!important;}',
        '.lsg-panel .lsg-card .lsg-quality{display:inline-block;flex-shrink:0;',
        'margin-right:.6em;padding:.26em .42em;background:rgba(255,255,255,.18);',
        'border-radius:.28em;font-size:.65em;font-weight:700;line-height:1.2;}',
        '.lsg-panel .lsg-card .lsg-dot{position:absolute;right:.75em;top:50%;',
        'height:.5em;width:.5em;margin-top:-.25em;border-radius:50%;',
        'background:#33d488;box-shadow:0 0 0 2px rgba(51,212,136,.12);}',
        '.lsg-panel .lsg-card.lsg-ghost{opacity:.37!important;}',
        '.lsg-panel .lsg-card.lsg-ghost .lsg-dot{background:#888;box-shadow:none;}',
        '.lsg-panel .lsg-card.focus,.lsg-panel .lsg-card:focus,',
        '.lsg-panel .lsg-card.selected.focus{opacity:1!important;',
        'border-color:rgba(255,255,255,.85)!important;background:rgba(255,255,255,.21)!important;}',
        '.lsg-panel .lsg-card.selected:not(.focus){border-color:rgba(132,188,255,.56)!important;}',
        '@media(max-width:800px){.lsg-panel .selectbox-item.lsg-card{width:calc(50% - .7em)!important;}}',
        '@media(max-width:520px){.lsg-panel .selectbox__content{width:95vw!important;}',
        '.lsg-panel .selectbox-item.lsg-card{width:calc(100% - .7em)!important;}}'
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
        var matched = raw.match(/(?:^|[\s\[\]()])(?:4k|uhd|2160p|fhd|full\s*hd|1080p|720p|hd)(?=$|[\s\[\]()])/i);
        if (matched) {
            var val = matched[0].toUpperCase();
            if (/4K|UHD|2160/.test(val)) return '4K';
            if (/FHD|FULL|1080/.test(val)) return 'FHD';
            return 'HD';
        }
        var key = normalizeName(item.source);
        var hint = QUALITY_HINTS[key];
        if (!hint) hint = QUALITY_HINTS[normalizeName(raw)];
        return hint === '4K' || hint === 'FHD' || hint === 'HD' ? hint : '';
    }

    function isSourcePicker(o) {
        if (!o || !o.items || !o.items.length || o.items.length < 2) return false;
        var items = o.items, matched = 0, count = 0;
        for (var i = 0; i < items.length; i++) {
            if (items[i].hide || items[i].separator) continue;
            count++;
            if (typeof items[i].source === 'string' && typeof items[i].ghost === 'boolean') matched++;
        }
        if (count < 2 || matched !== count) return false;
        // Avoid touching other provider selectors, even if they share Lampa.Filter.
        try {
            var active = Lampa.Activity && Lampa.Activity.active ? Lampa.Activity.active() : null;
            var component = active && active.component ? String(active.component) : '';
            return /online|lampac/i.test(component);
        } catch (ignore) { return false; }
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

    function decorate(o) {
        var root = nodeRoot();
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
        for (var i = 0; i < visible.length; i++) {
            var item = visible[i], el = list[i];
            el.classList.add('lsg-card');
            if (item.ghost) el.classList.add('lsg-ghost');
            else el.classList.remove('lsg-ghost');

            var quality = qualityFor(item);
            var heading = el.querySelector('.selectbox-item__title');
            if (quality && heading) {
                var badge = document.createElement('span');
                badge.className = 'lsg-quality';
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
            legend.textContent = '● Есть результат  ·  Серый — пока нет  ·  HD/4K — справочные метки';
            head.appendChild(legend);
        }
        gridOpen = true;
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
        var style = document.createElement('style');
        style.id = PLUGIN_ID + '-style';
        style.appendChild(document.createTextNode(CSS));
        (document.head || document.documentElement).appendChild(style);
        installControllerPatch();

        originalSelectShow = Lampa.Select.show;
        Lampa.Select.show = function (options) {
            cleanup();
            if (!isSourcePicker(options)) return originalSelectShow.apply(this, arguments);
            var originalFullDraw = options.onFullDraw;
            // Work on a shallow copy: keep original source items and handlers unchanged.
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
        // Cleanup after exit; do not alter native close/back implementation.
        if (Lampa.Select.listener && typeof Lampa.Select.listener.follow === 'function') {
            Lampa.Select.listener.follow('hide', cleanup);
        }
        if (window.console && console.log) console.log('[Lampac Source Grid] Loaded v0.1');
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