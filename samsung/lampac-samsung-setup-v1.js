/*
 * Lampac NG / Lampa Samsung Apps - client-side setup, version 1.0
 * Load using LampaWeb.customPlugins AFTER built-in ts.js.
 * Hosting: a static HTTPS URL outside the Lampac server.
 * It does NOT launch a local torrent parser, modify Lampac files, or change
 * Android/web-Lampa settings. No credentials are embedded in this script.
 */
(function () {
    'use strict';

    var guard = '__lampac_samsung_setup_v1';

    // Only the installed Samsung/Tizen app, not browser/MSX using Lampac's domain.
    var userAgent = String((window.navigator && window.navigator.userAgent) || '');
    var isTizen = /Tizen/i.test(userAgent) || typeof window.tizen !== 'undefined';
    var host = String((window.location && window.location.hostname) || '').toLowerCase();
    if (!isTizen || host === 'lampa.v6.army' || /\.lampa\.v6\.army$/.test(host)) return;

    // As in etor, set UI feature flags immediately, BEFORE waiting for Storage.
    // Lampa creates the Parser/TorrServer settings folders during startup.
    window.lampa_settings = window.lampa_settings || {};
    window.lampa_settings.torrents_use = true;
    window.lampa_settings.demo = false;
    window.lampa_settings.read_only = false;

    var readyAttempts = 0;
    function whenLampaReady() {
        if (!window.Lampa || !Lampa.Storage ||
            typeof Lampa.Storage.get !== 'function' ||
            typeof Lampa.Storage.set !== 'function') {
            readyAttempts += 1;
            if (readyAttempts < 40) window.setTimeout(whenLampaReady, 250);
            return;
        }
        if (window[guard]) return;
        window[guard] = true;
        ensureNativePluginRegistered();
        initialize();
    }

    // on.js loads plugins asynchronously, sometimes after the settings menu was built.
    // Register this exact HTTPS URL in native Lampa's own plugin registry so that
    // on the NEXT launch it loads before Settings.init(), just like manually added etor.
    // Never re-enable an existing disabled entry or touch other client installations.
    function ensureNativePluginRegistered() {
        if (!Lampa.Plugins ||
            typeof Lampa.Plugins.get !== 'function' ||
            typeof Lampa.Plugins.add !== 'function') return;

        var url = 'https://ipvideocom-star.github.io/lampa-plugins/samsung/lampac-samsung-setup-v1.js';
        var existing = Lampa.Plugins.get();
        if (!Array.isArray(existing)) return;

        var found = existing.some(function (plugin) {
            var storedUrl = typeof plugin === 'string' ? plugin : plugin && plugin.url;
            return typeof storedUrl === 'string' &&
                   storedUrl.split('?')[0] === url;
        });
        if (found) return;

        try {
            Lampa.Plugins.add({
                url: url,
                status: 1,
                name: 'Lampac Samsung setup'
            });
        } catch (e) {
            if (window.console && console.warn) console.warn('[Lampac Samsung] native plugin registration failed', e);
        }
    }

    function initialize() {
    var storage = Lampa.Storage;
    var torrserverUrl = 'https://lampa.v6.army/ts';
    var parserHost = 'https://lampa.v6.army'; // required by Samsung Apps Lampa

    function read(key) {
        var value = storage.get(key, '');
        return value == null ? '' : String(value).replace(/^\s+|\s+$/g, '');
    }

    function setIfMissing(key, value) {
        // Never overwrite deliberately selected settings (including 'false').
        if (!read(key)) storage.set(key, value);
    }

    // Parser compatibility mode; Lampac JacRed proxies its configured webapi.
    // This is not a request to install or start Jackett/JacRed indexing locally.
    var currentParserHost = read('jackett_url');
    var parserWasEmpty = !currentParserHost;
    // Upgrade only our old bare/HTTP endpoint; leave custom parser addresses alone.
    if (parserWasEmpty || /^(?:http:\/\/)?lampa\.v6\.army\/?$/i.test(currentParserHost)) {
        storage.set('jackett_url', parserHost);
    }
    if (parserWasEmpty) {
        // A fresh Samsung installation often has parser_use='false' by default.
        storage.set('parser_use', 'true');
    } else {
        setIfMissing('parser_use', 'true');
    }
    setIfMissing('jackett_key', '1');
    setIfMissing('parser_torrent_type', 'jackett');

    function isOurTorrserver(value) {
        if (!value) return true;
        var v = String(value).replace(/^\s+|\s+$/g, '')
                             .replace(/\/+$/, '').toLowerCase();
        return v === 'lampa.v6.army/ts' ||
               v === 'http://lampa.v6.army/ts' ||
               v === 'https://lampa.v6.army/ts';
    }

    var attempts = 0;
    function finishTorrserverSetup() {
        var old = read('torrserver_url');
        if (!isOurTorrserver(old)) return; // preserve a user's custom server
        if (old === torrserverUrl) return;

        attempts += 1;

        // ts.js may initialize its user login asynchronously with /reqinfo.
        // Wait for its marker and auth before fixing the URL: changing it too
        // early would make the built-in ts.js skip writing credentials.
        var tsInitialized = !!read('lampac_torrserver_url');
        var authReady = !!read('torrserver_login');
        if (attempts < 45 && (!tsInitialized || !authReady)) {
            window.setTimeout(finishTorrserverSetup, 400);
            return;
        }

        storage.set('torrserver_url', torrserverUrl);

        // Intentionally DO NOT update lampac_torrserver_url: keeping the value
        // written by ts.js prevents that plugin from overwriting our HTTPS URL
        // on subsequent launches. Auth stays managed by the stock ts.js.
    }

    window.setTimeout(finishTorrserverSetup, 400);
    } // initialize

    whenLampaReady();
})();
