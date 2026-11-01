/* IPTV+ Auto Setup - Chrome-only pilot v1.
   Does not alter plugin registry, favorites, history, or existing valid URLs. */
(function () {
    'use strict';

    var ua = (window.navigator && window.navigator.userAgent) || '';
    if (!/Chrome\/[0-9]+/i.test(ua) || /Tizen|Android|SmartTV|SMART-TV|WebOS|Mobile|CrKey/i.test(ua)) return;

    var playlistUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA.m3u';
    var initialized = false;

    function isUnset(value) {
        if (value === null || typeof value === 'undefined') return true;
        if (typeof value !== 'string') return true;
        var v = value.trim();
        return !v || /^(undefined|null)$/i.test(v);
    }

    function setup() {
        if (initialized) return;
        if (!window.Lampa || !Lampa.Storage ||
            typeof Lampa.Storage.get !== 'function' ||
            typeof Lampa.Storage.set !== 'function') return;

        try {
            var playlist = Lampa.Storage.get('iptv_plus_playlist', '');
            if (isUnset(playlist)) {
                Lampa.Storage.set('iptv_plus_playlist', playlistUrl);
                console.log('IPTV+ Auto Setup: default playlist configured');
            }

            var epg = Lampa.Storage.get('iptv_plus_epg', '');
            if (typeof epg === 'string' && /^(undefined|null)$/i.test(epg.trim())) {
                Lampa.Storage.set('iptv_plus_epg', '');
            }
            initialized = true;
        } catch (error) {
            console.warn('IPTV+ Auto Setup failed', error);
        }
    }

    setup();
    if (!initialized && window.Lampa && Lampa.Listener &&
        typeof Lampa.Listener.follow === 'function') {
        Lampa.Listener.follow('app', function (event) {
            if (event && event.type === 'ready') setup();
        });
    }
})();
