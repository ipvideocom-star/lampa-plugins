/* IPTV+ Auto Setup v7: desktop Chrome + two approved Samsung Lampa UIDs.
   For original Samsung Tizen app and Lampa via MSX on that Samsung.
   Contains hashed UID fingerprints (no raw UIDs) and does not modify plugins,
   registration, favourites, history, or unrelated custom playlist/EPG URLs. */
(function () {
    'use strict';

    var ua = (window.navigator && window.navigator.userAgent) || '';
    var isSamsungTizen = /Tizen/i.test(ua) || typeof window.tizen !== 'undefined';
    var isDesktopChrome = /Chrome\/[0-9]+/i.test(ua) &&
        !/Tizen|Android|SmartTV|SMART-TV|WebOS|Mobile|CrKey/i.test(ua);
    if (!isSamsungTizen && !isDesktopChrome) return;

    // Approved original-Lampa and MSX UIDs of one Samsung. Do not expose raw UIDs.
    // This is device scoping, not a security/authorization boundary.
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
    var rejectedEpgUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-test.xml';
    var previousEpgUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-OpenEPG-test.xml';
    var mergedEpgUrl = 'https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-Merged-test.xml';
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
            if (isSamsungTizen) {
                // Use the same device UID as Lampa's server-facing IPTV requests.
                // Never assume that Samsung app and MSX share a browser storage.
                var deviceUid = Lampa.Storage.get('device_uid', '');
                if (isUnset(deviceUid)) return; // wait until client initializes
                if (approvedUidHashes.indexOf(uidFingerprint(deviceUid)) < 0) {
                    initialized = true; // other devices are not modified
                    return;
                }
            }
            // Migrate only the playlist previously configured by Auto Setup.
            // Do not touch any other playlist the user may have chosen.
            var playlist = Lampa.Storage.get('iptv_plus_playlist', '');
            var playlistText = typeof playlist === 'string' ? playlist.trim() : '';
            if (isUnset(playlist) || playlistText === previousPlaylistUrl) {
                Lampa.Storage.set('iptv_plus_playlist', combinedPlaylistUrl);
                console.log('IPTV+ Auto Setup v7: UA+RU pilot playlist configured');
            }

            // The merged guide currently covers UA channels only.  Keep it for
            // UA+RU, but never overwrite a custom guide.
            var effectivePlaylist = Lampa.Storage.get('iptv_plus_playlist', '');
            var epg = Lampa.Storage.get('iptv_plus_epg', '');
            var epgText = typeof epg === 'string' ? epg.trim() : '';
            if (typeof effectivePlaylist === 'string' &&
                (effectivePlaylist.trim() === combinedPlaylistUrl ||
                 effectivePlaylist.trim() === previousPlaylistUrl) &&
                (isUnset(epg) || epgText === rejectedEpgUrl || epgText === previousEpgUrl)) {
                Lampa.Storage.set('iptv_plus_epg', mergedEpgUrl);
                console.log('IPTV+ Auto Setup v7: UA merged EPG configured');
            }
            initialized = true;
            console.log('IPTV+ Auto Setup v7: settings checked for ' +
                (isSamsungTizen ? 'approved Samsung' : 'Chrome'));
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
