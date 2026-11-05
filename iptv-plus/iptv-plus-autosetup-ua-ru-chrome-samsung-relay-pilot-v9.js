/* IPTV+ Auto Setup v9: staged HLS relay pilot for desktop Chrome and two approved Samsung Lampa/MSX UIDs.
   Preserves all 257 channels, the existing EPG, favorites, history and custom IPTV URLs.
   Does not expose or embed the HLS relay access token. Only redirects the managed
   playlist URL to a LAN-restricted pilot. PluginManager's UID key is lampac_unic_id.
   UID fingerprints below are inherited unchanged from v8; they are not access control. */
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

    var previousPlaylistUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA.m3u';
    var combinedPlaylistUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA-RU-Pilot-v1.m3u';
    var pilotPlaylistUrl = 'https://lampa.v6.army/iptv/pilot/IPTV-UA-RU-Relay-v02-257.m3u';

    var rejectedEpgUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-test.xml';
    var previousEpgUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-OpenEPG-test.xml';
    var previousMergedEpgUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-Merged-test.xml';
    var mergedEpgUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA-RU-EPG-Pilot-v1.xml';
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
            if (!isDesktopChrome) {
                // Reuse the stable identity already used by PluginManagerClient-v2.
                var clientUid = Lampa.Storage.get('lampac_unic_id', '');
                if (isUnset(clientUid)) return;
                if (approvedUidHashes.indexOf(uidFingerprint(clientUid)) < 0) {
                    initialized = true; // No settings change for other devices.
                    return;
                }
            }

            // Update ONLY previously managed playlists. Never overwrite custom URLs.
            var current = Lampa.Storage.get('iptv_plus_playlist', '');
            var currentText = typeof current === 'string' ? current.trim() : '';
            if (isUnset(current) ||
                currentText === previousPlaylistUrl ||
                currentText === combinedPlaylistUrl) {
                Lampa.Storage.set('iptv_plus_playlist', pilotPlaylistUrl);
                console.log('IPTV+ Auto Setup v9: relay pilot (257 channels) selected');
            }

            // EPG remains the existing managed guide; do not overwrite custom XMLTV.
            var effective = Lampa.Storage.get('iptv_plus_playlist', '');
            var epg = Lampa.Storage.get('iptv_plus_epg', '');
            var epgText = typeof epg === 'string' ? epg.trim() : '';
            if (typeof effective === 'string' &&
                (effective.trim() === pilotPlaylistUrl ||
                 effective.trim() === combinedPlaylistUrl ||
                 effective.trim() === previousPlaylistUrl) &&
                (isUnset(epg) || epgText === rejectedEpgUrl ||
                 epgText === previousEpgUrl || epgText === previousMergedEpgUrl)) {
                Lampa.Storage.set('iptv_plus_epg', mergedEpgUrl);
            }

            initialized = true;
            console.log('IPTV+ Auto Setup v9: managed settings checked (' +
                (isDesktopChrome ? 'desktop Chrome' : 'approved Samsung/MSX UID') + ')');
        } catch (error) {
            console.warn('IPTV+ Auto Setup v9 failed', error);
        }
    }

    var attempts = 0;
    function startWhenReady() {
        setup();
        if (!initialized && attempts++ < 40) setTimeout(startWhenReady, 500);
    }
    startWhenReady();
})();
