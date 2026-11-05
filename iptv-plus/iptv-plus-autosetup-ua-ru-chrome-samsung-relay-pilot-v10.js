/* IPTV+ Auto Setup v10: pilot selection for desktop Chrome and two approved Samsung/MSX UIDs.
   Fixes cache-busting ?refresh=... on managed playlist URLs. Does not overwrite
   unrelated custom IPTV playlists, EPG, favourites or history. UID fingerprints
   are device scoping only, not security enforcement. No private tokens here. */
(function () {
    'use strict';

    var ua = (window.navigator && window.navigator.userAgent) || '';
    var isDesktopChrome = /Chrome\/[0-9]+/i.test(ua) &&
        !/Tizen|Android|SmartTV|SMART-TV|WebOS|Mobile|CrKey/i.test(ua);

    var approvedUidHashes = ['e546300d', '1b192dce'];
    function uidFingerprint(value) {
        var v = String(value || '').trim().toLowerCase();
        if (!v || !/^[a-z0-9]{8,32}$/.test(v)) return '';
        var hash = 2166136261;
        for (var i = 0; i < v.length; i++) {
            hash = Math.imul(hash ^ v.charCodeAt(i), 16777619);
        }
        return ('00000000' + (hash >>> 0).toString(16)).slice(-8);
    }

    var uaUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA.m3u';
    var combinedUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA-RU-Pilot-v1.m3u';
    var pilotUrl = 'https://lampa.v6.army/iptv/pilot/IPTV-UA-RU-Relay-v02-257.m3u';
    var oldEpg = [
        'https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-test.xml',
        'https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-OpenEPG-test.xml',
        'https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-Merged-test.xml'
    ];
    var epgUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA-RU-EPG-Pilot-v1.xml';
    var initialized = false;

    function empty(value) {
        if (value === null || typeof value === 'undefined') return true;
        if (typeof value !== 'string') return true;
        var s = value.trim();
        return !s || /^(undefined|null)$/i.test(s);
    }

    // IPTV+ appends ?refresh=<timestamp>. Compare only canonical known managed
    // addresses; arbitrary user-provided playlists are never changed.
    function canonical(value) {
        return typeof value === 'string' ? value.trim().split(/[?#]/)[0] : '';
    }

    function setup() {
        if (initialized) return;
        if (!window.Lampa || !Lampa.Storage ||
            typeof Lampa.Storage.get !== 'function' ||
            typeof Lampa.Storage.set !== 'function') return;
        try {
            if (!isDesktopChrome) {
                var uid = Lampa.Storage.get('lampac_unic_id', '');
                if (empty(uid)) return;
                if (approvedUidHashes.indexOf(uidFingerprint(uid)) < 0) {
                    initialized = true;
                    return;
                }
            }

            var current = Lampa.Storage.get('iptv_plus_playlist', '');
            var base = canonical(current);
            if (empty(current) || base === uaUrl || base === combinedUrl) {
                Lampa.Storage.set('iptv_plus_playlist', pilotUrl);
                console.log('IPTV+ Auto Setup v10: 257-channel relay pilot selected');
            }

            var active = canonical(Lampa.Storage.get('iptv_plus_playlist', ''));
            var epg = Lampa.Storage.get('iptv_plus_epg', '');
            if ((active === pilotUrl || active === combinedUrl || active === uaUrl) &&
                (empty(epg) || oldEpg.indexOf(canonical(epg)) >= 0)) {
                Lampa.Storage.set('iptv_plus_epg', epgUrl);
            }

            initialized = true;
            console.log('IPTV+ Auto Setup v10: checked ' +
                (isDesktopChrome ? 'desktop Chrome' : 'approved Samsung/MSX UID'));
        } catch (e) {
            console.warn('IPTV+ Auto Setup v10 failed', e);
        }
    }

    var attempts = 0;
    function startWhenReady() {
        setup();
        if (!initialized && attempts++ < 40) setTimeout(startWhenReady, 500);
    }
    startWhenReady();
})();
