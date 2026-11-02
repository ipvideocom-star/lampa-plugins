/* IPTV+ Auto Setup - Chrome-only M3U, invalid EPG cleanup v3.
   Does not alter plugin registry, favorites, history, or existing valid URLs. */
(function () {
    'use strict';

    var ua = (window.navigator && window.navigator.userAgent) || '';
    if (!/Chrome\/[0-9]+/i.test(ua) || /Tizen|Android|SmartTV|SMART-TV|WebOS|Mobile|CrKey/i.test(ua)) return;

    var playlistUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA.m3u';
    var rejectedEpgUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-test.xml';
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

            // Retire the known unusable EPG; never erase a user-selected guide.
            var epg = Lampa.Storage.get('iptv_plus_epg', '');
            if (typeof epg === 'string' &&
                (epg.trim() === rejectedEpgUrl || /^(undefined|null)$/i.test(epg.trim()))) {
                Lampa.Storage.set('iptv_plus_epg', '');
                console.log('IPTV+ Auto Setup: invalid EPG cleared');
            }
            initialized = true;
        } catch (error) {
            console.warn('IPTV+ Auto Setup failed', error);
        }
    }

    // Lampa may still be starting when Plugin Manager loads this script.
    var attempts = 0;
    function startWhenReady() {
        setup();
        if (!initialized && attempts++ < 40) setTimeout(startWhenReady, 500);
    }
    startWhenReady();
})();
