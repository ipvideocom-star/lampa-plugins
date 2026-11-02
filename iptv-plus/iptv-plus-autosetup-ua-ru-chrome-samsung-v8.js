/* IPTV+ Auto Setup v8: desktop Chrome + 2 approved Samsung Lampa/MSX UIDs.
   Uses PluginManager's identity key lampac_unic_id, not device_uid.
   Supports MSX even when its UA has no Tizen marker.
   Does not modify plugin registration, favourites, history, custom URLs. */
(function () {
    'use strict';

    var ua = (window.navigator && window.navigator.userAgent) || '';
    var isDesktopChrome = /Chrome\/[0-9]+/i.test(ua) &&
        !/Tizen|Android|SmartTV|SMART-TV|WebOS|Mobile|CrKey/i.test(ua);
    // For all non-desktop-Chrome clients allow ONLY the two approved UID
    // fingerprints. Do not require a Tizen UA marker: MSX may omit it.

    // Approved original-Lampa and MSX UIDs of one Samsung. No raw UIDs.
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
                // This is the exact storage key used by PluginManagerClient-v2
                // to request /plugin-manager/policy?uid=...
                var clientUid = Lampa.Storage.get('lampac_unic_id', '');
                if (isUnset(clientUid)) return; // retry while Lampa initializes
                if (approvedUidHashes.indexOf(uidFingerprint(clientUid)) < 0) {
                    initialized = true; // other devices never modified
                    return;
                }
            }
            // Migrate only the playlist previously configured by Auto Setup.
            // Do not touch any other playlist the user may have chosen.
            var playlist = Lampa.Storage.get('iptv_plus_playlist', '');
            var playlistText = typeof playlist === 'string' ? playlist.trim() : '';
            if (isUnset(playlist) || playlistText === previousPlaylistUrl) {
                Lampa.Storage.set('iptv_plus_playlist', combinedPlaylistUrl);
                console.log('IPTV+ Auto Setup v8: 98-channel UA+RU playlist configured');
            }

            // Upgrade ONLY an unset/old managed guide on the managed UA+RU
            // playlist. Preserve any user-specified XMLTV guide URL.
            var effectivePlaylist = Lampa.Storage.get('iptv_plus_playlist', '');
            var epg = Lampa.Storage.get('iptv_plus_epg', '');
            var epgText = typeof epg === 'string' ? epg.trim() : '';
            if (typeof effectivePlaylist === 'string' &&
                (effectivePlaylist.trim() === combinedPlaylistUrl ||
                 effectivePlaylist.trim() === previousPlaylistUrl) &&
                (isUnset(epg) || epgText === rejectedEpgUrl ||
                 epgText === previousEpgUrl || epgText === previousMergedEpgUrl)) {
                Lampa.Storage.set('iptv_plus_epg', mergedEpgUrl);
                console.log('IPTV+ Auto Setup v8: 28-channel UA+RU EPG configured');
            }
            initialized = true;
            console.log('IPTV+ Auto Setup v8: settings checked for ' +
                (isDesktopChrome ? 'desktop Chrome' : 'approved Samsung/MSX UID'));
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
