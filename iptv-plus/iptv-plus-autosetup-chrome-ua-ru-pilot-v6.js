/* IPTV+ Auto Setup - Chrome-only UA+RU pilot 98 channels, UA merged EPG v6.
   Does not alter plugin registry, favorites, history, or existing valid URLs. */
(function () {
    'use strict';

    var ua = (window.navigator && window.navigator.userAgent) || '';
    if (!/Chrome\/[0-9]+/i.test(ua) || /Tizen|Android|SmartTV|SMART-TV|WebOS|Mobile|CrKey/i.test(ua)) return;

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
            // Migrate only the playlist previously configured by Auto Setup.
            // Do not touch any other playlist the user may have chosen.
            var playlist = Lampa.Storage.get('iptv_plus_playlist', '');
            var playlistText = typeof playlist === 'string' ? playlist.trim() : '';
            if (isUnset(playlist) || playlistText === previousPlaylistUrl) {
                Lampa.Storage.set('iptv_plus_playlist', combinedPlaylistUrl);
                console.log('IPTV+ Auto Setup v6: Chrome UA+RU pilot playlist configured');
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
                console.log('IPTV+ Auto Setup v6: existing UA merged EPG retained');
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
