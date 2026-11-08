/* IPTV+ Samsung/MSX EPG overlay v11 (2026-11-08).
   Scoped to the SAME two Samsung UID fingerprints used by v10.
   Only migrates known managed IPTV+ playlist/EPG values; no UID values,
   stream credentials or user-customized URLs are embedded. */
(function () {
    'use strict';
    var approved = ['e546300d', '1b192dce'];
    var newPlaylist = 'https://lampa.v6.army/iptv/playlists/IPTV-Samsung-RelayEPG-v23.m3u';
    var newEpg = 'https://lampa.v6.army/iptv/playlists/IPTV-Samsung-Guide-v22.xml';
    var oldPlaylists = [
        'https://lampa.v6.army/iptv/playlists/IPTV-UA.m3u',
        'https://lampa.v6.army/iptv/playlists/IPTV-UA-RU-Pilot-v1.m3u',
        'https://lampa.v6.army/iptv/pilot/IPTV-UA-RU-Relay-v02-257.m3u',
        'https://lampa.v6.army/iptv/playlists/IPTV-Samsung-TEST.m3u',
        'https://lampa.v6.army/iptv/playlists/IPTV-Samsung-TEST-v22.m3u',
        newPlaylist
    ];
    var oldEpgs = [
        'https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-test.xml',
        'https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-OpenEPG-test.xml',
        'https://lampa.v6.army/iptv/playlists/IPTV-UA-EPG-Merged-test.xml',
        'https://lampa.v6.army/iptv/playlists/IPTV-UA-RU-EPG-Pilot-v1.xml',
        'https://lampa.v6.army/iptv/playlists/IPTV-Samsung-Guide-PREVIEW.xml',
        newEpg
    ];
    function canonical(value) {
        return typeof value === 'string' ? value.trim().split(/[?#]/)[0] : '';
    }
    function empty(value) {
        return typeof value !== 'string' || !value.trim() || /^(undefined|null)$/i.test(value.trim());
    }
    function fingerprint(value) {
        var v = String(value || '').trim().toLowerCase();
        if (!/^[a-z0-9]{8,32}$/.test(v)) return '';
        var h = 2166136261;
        for (var i = 0; i < v.length; i++) h = Math.imul(h ^ v.charCodeAt(i), 16777619);
        return ('00000000' + (h >>> 0).toString(16)).slice(-8);
    }
    var finished = false;
    var tries = 0;
    function setup() {
        if (finished) return;
        if (!window.Lampa || !Lampa.Storage ||
            typeof Lampa.Storage.get !== 'function' ||
            typeof Lampa.Storage.set !== 'function') return;
        try {
            var uid = Lampa.Storage.get('lampac_unic_id', '');
            if (empty(uid)) return;
            if (approved.indexOf(fingerprint(uid)) < 0) { finished = true; return; }
            var playlist = Lampa.Storage.get('iptv_plus_playlist', '');
            if (!empty(playlist) && oldPlaylists.indexOf(canonical(playlist)) < 0) {
                finished = true; // Custom user playlist: NEVER override.
                return;
            }
            var epg = Lampa.Storage.get('iptv_plus_epg', '');
            // Keep custom EPG even on the managed playlist.
            if (empty(epg) || oldEpgs.indexOf(canonical(epg)) >= 0) {
                if (canonical(epg) !== newEpg) Lampa.Storage.set('iptv_plus_epg', newEpg);
            }
            if (canonical(playlist) !== newPlaylist) {
                Lampa.Storage.set('iptv_plus_playlist', newPlaylist);
            }
            finished = true;
            console.log('IPTV+ Samsung/MSX v11: managed relay + EPG preview selected');
        } catch (error) {
            console.warn('IPTV+ Samsung/MSX v11: setup retry after error', error);
        }
    }
    function poll() {
        setup();
        if (!finished && tries++ < 60) setTimeout(poll, 500);
    }
    poll();
})();
