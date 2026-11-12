/* Side-by-side Samsung IPTV plugins v1.2 + Tizen remote fix, 2026-11-11.
   Autoload MaxTV + MIT-adapted Lampa IPTV on the two existing Samsung/MSX UIDs.
   Does NOT touch IPTV+ settings, current EPG, other devices, Caddy, or Lampac.
   Never embeds raw device UID, stream URLs, or authentication tokens.
   Secondary plugins get the SAME published 257-channel M3U and XMLTV only
   where they natively support custom XMLTV (MaxTV may use rootu EPG). */
(function () {
  'use strict';
  if (window.__iptvCompareLoaderV12) return;
  window.__iptvCompareLoaderV1 = true;

  var ALLOWED = ['e546300d', '1b192dce'];
  var M3U = 'https://lampa.v6.army/iptv/playlists/IPTV-Samsung-TEST-v22.m3u';
  var XMLTV = 'https://lampa.v6.army/iptv/playlists/IPTV-Samsung-Guide-v22.xml';
  var MAX_TV = 'https://cdn.jsdelivr.net/gh/maks-mk/lampatv@15f9841b568fb1c6cca97aa1dcb3a615918d06c0/tv.js';
  var MAX_TV_FALLBACK = 'https://raw.githubusercontent.com/maks-mk/lampatv/15f9841b568fb1c6cca97aa1dcb3a615918d06c0/tv.js';
  var LIPTV = 'https://cdn.jsdelivr.net/gh/ipvideocom-star/lampa-plugins@3e2fc8e354eab729333f1857e30f339d4744d947/iptv-compare/lampa-iptv-third-party-comparison-v5-tizen-scroll-scope.js';
  var attempts = 0, started = false;

  function fp(value) {
    var v = String(value || '').trim().toLowerCase();
    if (!/^[a-z0-9]{8,32}$/.test(v)) return '';
    var hash = 2166136261;
    for (var i = 0; i < v.length; i++) hash = Math.imul(hash ^ v.charCodeAt(i), 16777619);
    return ('00000000' + (hash >>> 0).toString(16)).slice(-8);
  }
  function canonical(value) {
    return typeof value === 'string' ? value.trim().split(/[?#]/)[0] : '';
  }
  function safeSet(key, value, prior) {
    var current = Lampa.Storage.get(key, '');
    if (typeof current !== 'string') return false;
    var p = canonical(current);
    if (!p || p === canonical(value) || (prior && prior.indexOf(p) >= 0)) {
      if (current !== value) Lampa.Storage.set(key, value);
      return true;
    }
    return false; // no overwrite of a user's own settings
  }
  function inject(url, label, cb, fallback) {
    var attempt = 0;
    var urls = fallback ? [url, fallback] : [url];
    function next() {
      if (attempt >= urls.length) {
        console.warn('IPTV compare v1.2: all ' + label + ' sources failed');
        if (cb) cb(false);
        return;
      }
      var el = document.createElement('script');
      el.async = true;
      el.src = urls[attempt++];
      el.onload = function() {
        console.log('IPTV compare v1.2: ' + label + ' loaded from source ' + attempt);
        if (cb) cb(true);
      };
      el.onerror = function() {
        console.warn('IPTV compare v1.2: ' + label + ' source ' + attempt + ' unavailable');
        next();
      };
      (document.head || document.body).appendChild(el);
    }
    next();
  }
  function start() {
    if (started) return;
    if (!window.Lampa || !Lampa.Storage || typeof Lampa.Storage.get !== 'function' ||
        typeof Lampa.Storage.set !== 'function' || !window.appready) return;
    var uid = Lampa.Storage.get('lampac_unic_id', '');
    if (!uid) return;
    if (ALLOWED.indexOf(fp(uid)) === -1) {
      started = true; // harmless on other devices
      return;
    }
    started = true;
    var maxConfigured = safeSet('max_iptv_list_url_0', M3U, []);
    if (maxConfigured) safeSet('max_iptv_list_name_0', 'MaxTV', []);
    var thirdConfigured = safeSet('liptv_m3u_url', M3U, []);
    if (thirdConfigured) {
      var epgIsManaged = safeSet('liptv_epg_url', XMLTV, []);
      if (epgIsManaged) {
        // Third-party Lampa IPTV has dedicated custom EPG setting.
        safeSet('liptv_epg_source', 'custom', []); // initialise only when unset; never reset the viewer's choice
      }
    }
    console.log('IPTV compare v1: scoped Samsung, MaxTV M3U set=' +
                maxConfigured + ', IPTV 3 M3U set=' + thirdConfigured);
    // Only two external clients. IPTV+ stays under its pre-existing v11 manager.
    if (!window.plugin_max_iptv_ready) {
      inject(MAX_TV, 'MaxTV', function () { inject(LIPTV, 'IPTV 3'); }, MAX_TV_FALLBACK);
    } else {
      inject(LIPTV, 'IPTV 3');
    }
  }
  function poll() {
    start();
    if (!started && attempts++ < 80) setTimeout(poll, 500);
  }
  poll();
})();
