/* IPTV+ Samsung/MSX v11 rollback: use ONLY after v11 preview if needed.
   Reverts only v22 test playlist and v22 managed guide. */
(function () {
    'use strict';
    var approved = ['e546300d', '1b192dce'];
    var fromM3u = 'https://lampa.v6.army/iptv/playlists/IPTV-Samsung-TEST-v22.m3u';
    var toM3u = 'https://lampa.v6.army/iptv/pilot/IPTV-UA-RU-Relay-v02-257.m3u';
    var fromXml = 'https://lampa.v6.army/iptv/playlists/IPTV-Samsung-Guide-v22.xml';
    var toXml = 'https://lampa.v6.army/iptv/playlists/IPTV-UA-RU-EPG-Pilot-v1.xml';
    function canonical(value) {return typeof value === 'string' ? value.trim().split(/[?#]/)[0] : '';}
    function fingerprint(value) {
        var v = String(value || '').trim().toLowerCase();
        if (!/^[a-z0-9]{8,32}$/.test(v)) return '';
        var h = 2166136261;
        for (var i = 0; i < v.length; i++) h = Math.imul(h ^ v.charCodeAt(i), 16777619);
        return ('00000000' + (h >>> 0).toString(16)).slice(-8);
    }
    var done=false, tries=0;
    function apply() {
        if(done) return;
        if(!window.Lampa || !Lampa.Storage || typeof Lampa.Storage.get!=='function' ||
           typeof Lampa.Storage.set!=='function') return;
        var uid=Lampa.Storage.get('lampac_unic_id','');
        if (!uid) return;
        if (approved.indexOf(fingerprint(uid)) < 0) {done=true;return;}
        try {
            if(canonical(Lampa.Storage.get('iptv_plus_playlist',''))===fromM3u) {
                Lampa.Storage.set('iptv_plus_playlist',toM3u);
            }
            if(canonical(Lampa.Storage.get('iptv_plus_epg',''))===fromXml) {
                Lampa.Storage.set('iptv_plus_epg',toXml);
            }
            done=true;
            console.log('IPTV+ Samsung/MSX v11: preview settings rolled back to relay pilot');
        } catch(e) {console.warn('IPTV+ v11 rollback retry',e);}
    }
    function poll(){apply(); if(!done && tries++<60) setTimeout(poll,500);}
    poll();
})();
