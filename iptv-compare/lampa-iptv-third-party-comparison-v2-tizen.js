/* Compare-mode adaptation of smackftw/lampa_iptv dist/lampa-iptv.js (MIT)
   Changes: preserve left-menu component, label IPTV 3; prevent auto-opening the
   IPTV screen during Lampa startup. No stream source or EPG override embedded.
   Upstream: https://github.com/smackftw/lampa_iptv
   The following license is reproduced as required by MIT:
MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/
/* Lampa IPTV Plugin v0.1.0 */
(function () {
  'use strict';

  function djb2(str) {
    let hash = 5381;
    for (let i = 0; i < str.length; i++) {
      hash = ((hash << 5) + hash) + str.charCodeAt(i);
      hash = hash & hash; // keep 32-bit
    }
    return Math.abs(hash).toString(36);
  }

  function parseM3U(text) {
    const lines = text.split('\n').map(l => l.trim()).filter(Boolean);
    const channels = [];
    const groupSet = new Set();
    let playlistEpgUrl = null;

    if (lines[0] && lines[0].startsWith('#EXTM3U')) {
      const m = lines[0].match(/tvg-url="([^"]+)"/);
      if (m) playlistEpgUrl = m[1];
    }

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (!line.startsWith('#EXTINF:')) continue;

      const urlLine = lines[i + 1];
      if (!urlLine || urlLine.startsWith('#')) continue;

      const tvgId = (line.match(/tvg-id="([^"]*)"/)    || ['', ''])[1];
      const name  = (line.match(/,(.+)$/)               || ['', 'Unknown'])[1].trim();
      const logo  = (line.match(/tvg-logo="([^"]*)"/)   || ['', ''])[1];
      const group = (line.match(/group-title="([^"]*)"/)|| ['', 'Other'])[1];

      groupSet.add(group);
      const id = tvgId || djb2(name + urlLine);
      channels.push({ id, name, url: urlLine, logo, group, tvgId });
    }

    return { channels, groups: [...groupSet], playlistEpgUrl };
  }

  async function fetchM3U(url) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`M3U fetch failed: HTTP ${response.status}`);
    const text = await response.text();
    return parseM3U(text);
  }

  const EPG_PRESETS = {
    auto:       { label: 'Авто' },
    playlist:   { label: 'Из плейлиста' },
    epgpw_ru:   { label: 'epg.pw — Россия',           url: 'https://epg.pw/xmltv/epg_RU.xml.gz' },
    epgpw_ua:   { label: 'epg.pw — Украина',           url: 'https://epg.pw/xmltv/epg_UA.xml.gz' },
    epgpw_cy:   { label: 'epg.pw — Кипр',              url: 'https://epg.pw/xmltv/epg_CY.xml.gz' },
    epgpw_de:   { label: 'epg.pw — Германия',          url: 'https://epg.pw/xmltv/epg_DE.xml.gz' },
    epgpw_us:   { label: 'epg.pw — США',               url: 'https://epg.pw/xmltv/epg_US.xml.gz' },
    epgpw_gb:   { label: 'epg.pw — Великобритания',    url: 'https://epg.pw/xmltv/epg_GB.xml.gz' },
    epgpw_tr:   { label: 'epg.pw — Турция',            url: 'https://epg.pw/xmltv/epg_TR.xml.gz' },
    epgpw_fr:   { label: 'epg.pw — Франция',           url: 'https://epg.pw/xmltv/epg_FR.xml.gz' },
    custom:     { label: 'Свой URL' }
  };

  function normalizeName(name) {
    if (!name) return '';
    var s = name.toLowerCase();
    s = s.replace(/\([^)]*\)/g, '').replace(/\[[^\]]*\]/g, '');
    s = s.replace(/\b(hd|sd|fhd|uhd|4k)\s*$/g, '');
    s = s.replace(/\s+/g, ' ').trim();
    return s;
  }

  function detectCountries(channels, maxCount) {
    var counts = {};
    channels.forEach(function(ch) {
      if (!ch.tvgId) return;
      var base = ch.tvgId.replace(/@.*$/, '');
      var match = base.match(/\.([a-z]{2})$/i);
      if (!match) return;
      var cc = match[1].toUpperCase();
      counts[cc] = (counts[cc] || 0) + 1;
    });
    return Object.entries(counts)
      .sort(function(a, b) { return b[1] - a[1]; })
      .slice(0, maxCount)
      .map(function(e) { return e[0]; });
  }

  function buildChannelMapping(epgChannels, playlistChannels) {
    var mapping = new Map();
    var tvgIdToId = {};
    playlistChannels.forEach(function(ch) {
      if (ch.tvgId) tvgIdToId[ch.tvgId] = ch.id;
    });
    var nameToId = {};
    playlistChannels.forEach(function(ch) {
      var norm = normalizeName(ch.name);
      if (norm && !nameToId[norm]) nameToId[norm] = ch.id;
    });
    epgChannels.forEach(function(epgCh) {
      if (tvgIdToId[epgCh.id] !== undefined) {
        mapping.set(epgCh.id, tvgIdToId[epgCh.id]);
        return;
      }
      var norm = normalizeName(epgCh.displayName);
      if (norm && nameToId[norm] !== undefined) {
        mapping.set(epgCh.id, nameToId[norm]);
      }
    });
    return mapping;
  }

  function resolveEpgUrls(sourceKey, channels, playlistEpgUrl, customUrl) {
    if (sourceKey === 'auto') {
      if (playlistEpgUrl && playlistEpgUrl.trim()) {
        return { urls: [playlistEpgUrl.trim()], needsMapping: false };
      }
      var countries = detectCountries(channels, 3);
      var withCountry = channels.filter(function(ch) {
        if (!ch.tvgId) return false;
        var base = ch.tvgId.replace(/@.*$/, '');
        return /\.[a-z]{2}$/i.test(base);
      }).length;
      if (channels.length > 0 && withCountry / channels.length < 0.3) {
        return { urls: [], needsMapping: true };
      }
      var urls = countries.map(function(cc) {
        return 'https://epg.pw/xmltv/epg_' + cc + '.xml.gz';
      });
      return { urls: urls, needsMapping: true };
    }
    if (sourceKey === 'playlist') {
      if (playlistEpgUrl && playlistEpgUrl.trim()) {
        return { urls: [playlistEpgUrl.trim()], needsMapping: false };
      }
      return { urls: [], needsMapping: false };
    }
    if (sourceKey === 'custom') {
      if (customUrl && customUrl.trim()) {
        return { urls: [customUrl.trim()], needsMapping: false };
      }
      return { urls: [], needsMapping: false };
    }
    var preset = EPG_PRESETS[sourceKey];
    if (preset && preset.url) {
      return { urls: [preset.url], needsMapping: true };
    }
    return { urls: [], needsMapping: false };
  }

  function parseXmltvDate(str) {
    if (!str) return null;
    // Format: YYYYMMDDHHmmss +HHMM
    const m = str.match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\s*([+-]\d{2})(\d{2})/);
    if (!m) return null;
    const [, yr, mo, dy, hr, mn, sc, tzH, tzM] = m;
    return new Date(`${yr}-${mo}-${dy}T${hr}:${mn}:${sc}${tzH}:${tzM}`);
  }

  function parseXMLTV(xmlText) {
    const doc = new DOMParser().parseFromString(xmlText, 'text/xml');
    const programs = {};
    const channels = [];

    doc.querySelectorAll('channel').forEach(node => {
      const id = node.getAttribute('id');
      const dn = node.querySelector('display-name');
      if (id) channels.push({ id: id, displayName: dn ? dn.textContent : '' });
    });

    doc.querySelectorAll('programme').forEach(node => {
      const channelId = node.getAttribute('channel');
      const start = parseXmltvDate(node.getAttribute('start'));
      const stop  = parseXmltvDate(node.getAttribute('stop'));
      const title = (node.querySelector('title') || {}).textContent || '';
      const desc  = (node.querySelector('desc') || {}).textContent  || '';
      if (!channelId || !start) return;
      if (!programs[channelId]) programs[channelId] = [];
      programs[channelId].push({ channelId, title, start, stop, desc });
    });
    Object.keys(programs).forEach(id => programs[id].sort((a, b) => a.start - b.start));
    return { programs, channels };
  }

  async function fetchXmlText(url) {
    const res = await fetch(url);
    if (!res.ok) return null;
    const buf = await res.arrayBuffer();
    const bytes = new Uint8Array(buf);
    if (bytes.length >= 2 && bytes[0] === 0x1f && bytes[1] === 0x8b) {
      if (typeof DecompressionStream !== 'undefined') {
        const ds = new DecompressionStream('gzip');
        const stream = new Response(new Blob([buf]).stream().pipeThrough(ds));
        return await stream.text();
      }
      var fallbackUrl = url.replace(/\.gz$/, '');
      if (fallbackUrl !== url) {
        var res2 = await fetch(fallbackUrl);
        if (res2.ok) return await res2.text();
      }
      return null;
    }
    return new TextDecoder().decode(buf);
  }

  let _programs        = {};
  let _urls            = [];
  let _playlistChannels = [];
  let _needsMapping    = false;

  const epg = {
    reset() {
      _programs        = {};
      _urls            = [];
      _playlistChannels = [];
      _needsMapping    = false;
    },

    init(urls, playlistChannels, needsMapping) {
      _urls             = urls || [];
      _playlistChannels = playlistChannels || [];
      _needsMapping     = !!needsMapping;
    },

    async fetchInBackground() {
      if (_urls.length === 0) return;
      for (var i = 0; i < _urls.length; i++) {
        try {
          var text = await fetchXmlText(_urls[i]);
          if (!text) continue;
          var parsed = parseXMLTV(text);

          if (_needsMapping && _playlistChannels.length > 0) {
            var mapping = buildChannelMapping(parsed.channels, _playlistChannels);
            mapping.forEach(function(playlistId, epgId) {
              if (parsed.programs[epgId] && !_programs[playlistId]) {
                _programs[playlistId] = parsed.programs[epgId];
              }
            });
            Object.keys(parsed.programs).forEach(function(epgId) {
              if (!_programs[epgId]) _programs[epgId] = parsed.programs[epgId];
            });
          } else {
            Object.keys(parsed.programs).forEach(function(id) {
              if (!_programs[id]) _programs[id] = parsed.programs[id];
            });
          }
        } catch (e) {
          console.warn('[lampa-iptv] EPG fetch failed:', e.message);
        }
      }
      if (Object.keys(_programs).length > 0) {
        Lampa.Listener.send('liptv:epg_loaded', {});
      }
    },

    getCurrent(channelId) {
      const list = _programs[channelId];
      if (!list) return null;
      const now = new Date();
      return list.find(p => p.start <= now && (!p.stop || p.stop > now)) || null;
    },

    getNext(channelId) {
      const list = _programs[channelId];
      if (!list) return null;
      const now = new Date();
      return list.find(p => p.start > now) || null;
    },

    getAll(channelId) {
      return _programs[channelId] || [];
    }
  };

  const DEFAULTS = {
    liptv_m3u_url:    '',
    liptv_epg_url:    '',
    liptv_epg_source: 'auto',
    liptv_view_mode:  'list',
    liptv_favorites:  [],
    liptv_history:    [],
    liptv_blacklist:  []
  };

  function get(key) { return Lampa.Storage.get(key, DEFAULTS[key]); }
  function set(key, val) { Lampa.Storage.set(key, val); }

  const storage = {
    getM3uUrl:  () => get('liptv_m3u_url'),
    setM3uUrl:  (v) => set('liptv_m3u_url', v),
    getEpgUrl:    () => get('liptv_epg_url'),
    setEpgUrl:    (v) => set('liptv_epg_url', v),
    getEpgSource: () => get('liptv_epg_source'),
    setEpgSource: (v) => set('liptv_epg_source', v),
    getViewMode:  () => get('liptv_view_mode'),
    setViewMode:(v) => set('liptv_view_mode', v),

    getFavorites:   () => get('liptv_favorites'),
    addFavorite:    (id) => { const f = get('liptv_favorites'); if (!f.includes(id)) set('liptv_favorites', [...f, id]); },
    removeFavorite: (id) => set('liptv_favorites', get('liptv_favorites').filter(x => x !== id)),
    isFavorite:     (id) => get('liptv_favorites').includes(id),

    getHistory: () => get('liptv_history'),
    addHistory: (id) => {
      let h = get('liptv_history').filter(x => x.id !== id);
      h.unshift({ id, ts: Date.now() });
      if (h.length > 100) h = h.slice(0, 100);
      set('liptv_history', h);
    },
    clearHistory: () => set('liptv_history', []),

    getBlacklist:    () => get('liptv_blacklist'),
    addBlacklist:    (id) => { const bl = get('liptv_blacklist'); if (!bl.includes(id)) set('liptv_blacklist', [...bl, id]); },
    removeBlacklist: (id) => set('liptv_blacklist', get('liptv_blacklist').filter(x => x !== id)),
    isBlacklisted:   (id) => get('liptv_blacklist').includes(id),
  };

  /**
   * Injects IPTV plugin CSS into the page <head>.
   * Called once on plugin init.
   */
  function injectStyles() {
    if (document.getElementById('liptv-styles')) return;

    var style = document.createElement('style');
    style.id = 'liptv-styles';
    style.textContent = CSS;
    document.head.appendChild(style);
  }

  var CSS = '\
/* ── Layout ───────────────────────────────────── */\
.liptv-container {\
  width: 100%;\
  height: 100%;\
  overflow: hidden;\
}\
.liptv-wrap {\
  display: flex;\
  flex-direction: column;\
  height: 100%;\
}\
\
/* ── Toolbar ──────────────────────────────────── */\
.liptv-toolbar {\
  display: flex;\
  gap: 1em;\
  padding: 1em 1.5em 0.5em;\
  flex-shrink: 0;\
}\
.liptv-btn {\
  padding: 0.5em 1.2em;\
  border-radius: 0.5em;\
  background: rgba(255,255,255,0.08);\
  color: #fff;\
  font-size: 1em;\
  cursor: pointer;\
  white-space: nowrap;\
}\
.liptv-btn.focus {\
  background: rgba(255,255,255,0.28);\
  color: #fff;\
}\
\
/* ── Body: sidebar + channels ─────────────────── */\
.liptv-body {\
  display: flex;\
  flex: 1;\
  overflow: hidden;\
}\
\
/* ── Sidebar (groups) ─────────────────────────── */\
.liptv-sidebar {\
  width: 15em;\
  flex-shrink: 0;\
  overflow-y: auto;\
  padding: 0.5em 0 0.5em 1.5em;\
}\
.liptv-group {\
  padding: 0.5em 1em;\
  margin-bottom: 0.2em;\
  border-radius: 0.4em;\
  color: rgba(255,255,255,0.6);\
  font-size: 0.95em;\
  cursor: pointer;\
  white-space: nowrap;\
  overflow: hidden;\
  text-overflow: ellipsis;\
}\
.liptv-group.active {\
  color: #fff;\
  background: rgba(255,255,255,0.1);\
}\
.liptv-group.focus {\
  color: #fff;\
  background: rgba(255,255,255,0.22);\
}\
\
/* ── Channel list (list mode) ─────────────────── */\
.liptv-channels {\
  flex: 1;\
  overflow-y: auto;\
  padding: 0.5em 1.5em 2em 1em;\
}\
.liptv-row {\
  display: flex;\
  align-items: center;\
  gap: 1em;\
  padding: 0.6em 1em;\
  margin-bottom: 0.2em;\
  border-radius: 0.5em;\
  cursor: pointer;\
}\
.liptv-row.focus {\
  background: rgba(255,255,255,0.15);\
}\
.liptv-logo {\
  width: 3.5em;\
  height: 3.5em;\
  object-fit: contain;\
  flex-shrink: 0;\
  border-radius: 0.3em;\
}\
.liptv-no-logo {\
  background: rgba(255,255,255,0.05);\
}\
.liptv-row-info {\
  flex: 1;\
  min-width: 0;\
}\
.liptv-row-name {\
  color: #fff;\
  font-size: 1.05em;\
  white-space: nowrap;\
  overflow: hidden;\
  text-overflow: ellipsis;\
}\
.liptv-row-prog {\
  color: rgba(255,255,255,0.45);\
  font-size: 0.85em;\
  margin-top: 0.15em;\
  white-space: nowrap;\
  overflow: hidden;\
  text-overflow: ellipsis;\
}\
\
/* ── Channel grid (grid mode) ─────────────────── */\
.liptv-channels.grid {\
  display: flex;\
  flex-wrap: wrap;\
  gap: 1em;\
  align-content: flex-start;\
}\
.liptv-tile {\
  width: 8em;\
  display: flex;\
  flex-direction: column;\
  align-items: center;\
  padding: 0.8em;\
  border-radius: 0.5em;\
  cursor: pointer;\
}\
.liptv-tile.focus {\
  background: rgba(255,255,255,0.15);\
}\
.liptv-tile .liptv-logo {\
  width: 5em;\
  height: 5em;\
  margin-bottom: 0.4em;\
}\
.liptv-tile-name {\
  color: #fff;\
  font-size: 0.85em;\
  text-align: center;\
  max-width: 100%;\
  overflow: hidden;\
  text-overflow: ellipsis;\
  white-space: nowrap;\
}\
\
/* ── Empty state ──────────────────────────────── */\
.liptv-empty {\
  color: rgba(255,255,255,0.4);\
  font-size: 1.1em;\
  padding: 3em 1em;\
  text-align: center;\
}\
\
/* ── OSD mini-list (player overlay) ──────────── */\
.liptv-osd {\
  position: fixed;\
  bottom: 2em;\
  left: 2em;\
  z-index: 9999;\
  background: rgba(0,0,0,0.82);\
  -webkit-backdrop-filter: blur(10px);\
  backdrop-filter: blur(10px);\
  border-radius: 10px;\
  padding: 0.6em 0.8em;\
  min-width: 18em;\
  transform: translateX(-110%);\
  opacity: 0;\
  transition: transform 300ms ease-out, opacity 300ms ease-out;\
  pointer-events: none;\
}\
.liptv-osd.visible {\
  transform: translateX(0);\
  opacity: 1;\
  pointer-events: auto;\
}\
.liptv-osd.fade-out {\
  transform: translateX(0);\
  opacity: 0;\
  transition: opacity 300ms ease-in;\
}\
.liptv-osd-item {\
  display: flex;\
  align-items: center;\
  gap: 0.5em;\
  padding: 0.25em 0;\
  opacity: 0.4;\
}\
.liptv-osd-item.current {\
  opacity: 1;\
  background: rgba(255,255,255,0.1);\
  border-radius: 5px;\
  padding: 0.35em 0.5em;\
  margin: 0.15em -0.5em;\
}\
.liptv-osd-num {\
  color: #999;\
  font-size: 0.8em;\
  width: 2em;\
  text-align: right;\
  flex-shrink: 0;\
}\
.liptv-osd-item.current .liptv-osd-num {\
  background: #e63946;\
  color: #fff;\
  font-weight: bold;\
  font-size: 0.75em;\
  padding: 0.15em 0.35em;\
  border-radius: 3px;\
  width: auto;\
  text-align: center;\
}\
.liptv-osd-name {\
  color: #ccc;\
  font-size: 0.9em;\
  white-space: nowrap;\
  overflow: hidden;\
  text-overflow: ellipsis;\
}\
.liptv-osd-item.current .liptv-osd-name {\
  color: #fff;\
  font-weight: 600;\
}\
.liptv-osd-prog {\
  color: rgba(255,255,255,0.5);\
  font-size: 0.72em;\
  white-space: nowrap;\
  overflow: hidden;\
  text-overflow: ellipsis;\
}\
\
/* ── EPG sidebar ─────────────────────────────── */\
.liptv-epg {\
  position: fixed;\
  top: 0;\
  right: 0;\
  bottom: 0;\
  width: 40%;\
  z-index: 10000;\
  background: rgba(0,0,0,0.88);\
  -webkit-backdrop-filter: blur(12px);\
  backdrop-filter: blur(12px);\
  padding: 1.2em 1em;\
  overflow-y: auto;\
  transform: translateX(100%);\
  transition: transform 300ms ease-out;\
}\
.liptv-epg.visible {\
  transform: translateX(0);\
}\
.liptv-epg.hiding {\
  transform: translateX(100%);\
  transition: transform 250ms ease-in;\
}\
.liptv-epg-title {\
  color: #fff;\
  font-size: 1.05em;\
  font-weight: 600;\
  padding-bottom: 0.5em;\
  margin-bottom: 0.6em;\
  border-bottom: 1px solid rgba(255,255,255,0.1);\
}\
.liptv-epg-item {\
  padding: 0.4em 0.5em;\
  margin-bottom: 0.15em;\
  border-radius: 0 4px 4px 0;\
}\
.liptv-epg-item.past {\
  opacity: 0.35;\
}\
.liptv-epg-item.now {\
  background: rgba(230,57,70,0.2);\
  border-left: 3px solid #e63946;\
}\
.liptv-epg-item.focus {\
  background: rgba(255,255,255,0.1);\
}\
.liptv-epg-item.now.focus {\
  background: rgba(230,57,70,0.35);\
}\
.liptv-epg-time {\
  font-size: 0.75em;\
  color: rgba(255,255,255,0.4);\
}\
.liptv-epg-item.now .liptv-epg-time {\
  color: #e63946;\
  font-weight: 500;\
}\
.liptv-epg-prog-title {\
  font-size: 0.88em;\
  color: rgba(255,255,255,0.7);\
  margin-top: 0.1em;\
}\
.liptv-epg-item.now .liptv-epg-prog-title {\
  color: #fff;\
  font-weight: 500;\
}\
.liptv-epg-progress {\
  height: 2px;\
  background: rgba(255,255,255,0.15);\
  border-radius: 1px;\
  margin-top: 0.3em;\
  overflow: hidden;\
}\
.liptv-epg-progress-fill {\
  height: 100%;\
  background: #e63946;\
}\
.liptv-epg-empty {\
  color: rgba(255,255,255,0.4);\
  text-align: center;\
  padding: 3em 1em;\
  font-size: 0.95em;\
}\
';

  function fmt(date) {
    if (!date) return '';
    return date.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
  }

  function showEpgScreen(channel) {
    const programs = epg.getAll(channel.id);
    if (programs.length === 0) {
      Lampa.Noty.show('Программа передач недоступна');
      return;
    }

    const now = new Date();
    Lampa.Select.show({
      title:    channel.name + ' — Программа',
      items:    programs.map(function(p) {
        return {
          title:    fmt(p.start) + '–' + fmt(p.stop) + '  ' + p.title,
          subtitle: p.desc || '',
          selected: p.start <= now && (!p.stop || p.stop > now)
        };
      }),
      onSelect: function() {} // read-only; close on select is default Lampa.Select behavior
    });
  }

  function showCard(channel, onClose) {
    const cur    = epg.getCurrent(channel.id);
    const next   = epg.getNext(channel.id);
    const isFav  = storage.isFavorite(channel.id);

    // Store action fn directly on each item; Lampa.Select.show onSelect passes only (item)
    const actionItems = [
      { title: '▶ Смотреть',
        fn: function() { playChannel(channel); } },
      { title: isFav ? '★ Убрать из избранного' : '☆ В избранное',
        fn: function() { toggleFav(channel); if (onClose) onClose(); } },
      { title: '📋 Программа',
        fn: function() { showEpgScreen(channel); } },
      { title: '🚫 Скрыть',
        fn: function() { storage.addBlacklist(channel.id); Lampa.Noty.show('"' + channel.name + '" скрыт'); if (onClose) onClose(); } }
    ];

    Lampa.Select.show({
      title: channel.name,
      items: [
        { title: cur  ? 'Сейчас: ' + cur.title  : 'Сейчас: —',  noclick: true },
        { title: next ? 'Далее: '  + next.title : 'Далее: —',   noclick: true },
        { separator: true }
      ].concat(actionItems),
      onSelect: function(item) {
        if (typeof item.fn === 'function') item.fn();
      }
    });
  }

  var _onPlay = null;
  function setOnPlay(fn) { _onPlay = fn; }

  function playChannel(channel) {
    if (typeof _onPlay === 'function') _onPlay(channel);
    Lampa.Player.play({ url: channel.url, title: channel.name, iptv: true });
  }

  function toggleFav(channel) {
    if (storage.isFavorite(channel.id)) {
      storage.removeFavorite(channel.id);
      Lampa.Noty.show('Удалено из избранного');
    } else {
      storage.addFavorite(channel.id);
      Lampa.Noty.show('Добавлено в избранное');
    }
  }

  const VIRTUAL_GROUPS = ['Все', 'Избранное', 'История'];

  function esc(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function createMainScreen(allChannels, onChannelSelect) {
    let currentGroup = 'Все';
    let viewMode     = storage.getViewMode();

    const groups = VIRTUAL_GROUPS.concat(
      [...new Set(allChannels.map(function(ch) { return ch.group; }))].filter(Boolean)
    );

    function getVisible() {
      const blacklist = storage.getBlacklist();
      let list = allChannels.filter(function(ch) { return !blacklist.includes(ch.id); });

      if (currentGroup === 'Избранное') {
        const favs = storage.getFavorites();
        list = list.filter(function(ch) { return favs.includes(ch.id); });
      } else if (currentGroup === 'История') {
        const history = storage.getHistory();
        const rank = {};
        history.forEach(function(h, i) { rank[h.id] = i; });
        list = list
          .filter(function(ch) { return ch.id in rank; })
          .sort(function(a, b) { return rank[a.id] - rank[b.id]; });
      } else if (currentGroup !== 'Все') {
        list = list.filter(function(ch) { return ch.group === currentGroup; });
      }
      return list;
    }

    function channelHtml(ch) {
      const cur  = epg.getCurrent(ch.id);
      const prog = cur ? esc(cur.title) : '';
      const logo = ch.logo
        ? '<img class="liptv-logo" src="' + esc(ch.logo) + '" onerror="this.style.display=\'none\'">'
        : '<div class="liptv-logo liptv-no-logo"></div>';

      if (viewMode === 'grid') {
        return '<div class="liptv-tile selector" data-id="' + esc(ch.id) + '">'
          + logo
          + '<div class="liptv-tile-name">' + esc(ch.name) + '</div>'
          + '</div>';
      }
      return '<div class="liptv-row selector" data-id="' + esc(ch.id) + '">'
        + logo
        + '<div class="liptv-row-info">'
        + '<div class="liptv-row-name">' + esc(ch.name) + '</div>'
        + '<div class="liptv-row-prog">' + prog + '</div>'
        + '</div>'
        + '</div>';
    }

    function render(body) {
      const visible    = getVisible();
      const groupsHtml = groups.map(function(g) {
        return '<div class="liptv-group selector' + (g === currentGroup ? ' active' : '') + '" data-group="' + esc(g) + '">' + esc(g) + '</div>';
      }).join('');
      const channelsHtml = visible.length
        ? visible.map(channelHtml).join('')
        : '<div class="liptv-empty">Нет каналов</div>';

      body.empty().append(
        '<div class="liptv-wrap">'
          + '<div class="liptv-toolbar">'
          + '<div class="liptv-btn selector" data-action="search">Поиск</div>'
          + '<div class="liptv-btn selector" data-action="toggle">'
          + (viewMode === 'list' ? '⊞ Сетка' : '☰ Список')
          + '</div>'
          + '</div>'
          + '<div class="liptv-body">'
          + '<div class="liptv-sidebar">' + groupsHtml + '</div>'
          + '<div class="liptv-channels ' + viewMode + '">' + channelsHtml + '</div>'
          + '</div>'
          + '</div>'
      );

      body.find('[data-group]').on('hover:enter', function() {
        currentGroup = $(this).data('group');
        render(body);
      });

      body.find('[data-action="toggle"]').on('hover:enter', function() {
        viewMode = viewMode === 'list' ? 'grid' : 'list';
        storage.setViewMode(viewMode);
        render(body);
      });

      body.find('[data-action="search"]').on('hover:enter', function() {
        onChannelSelect(null, 'search');
      });

      // Short press → play, long press → card with actions
      body.find('[data-id]').on('hover:enter', function() {
        const id = $(this).data('id');
        const ch = allChannels.find(function(c) { return c.id === id; });
        if (ch) playChannel(ch);
      }).on('hover:long', function() {
        const id = $(this).data('id');
        const ch = allChannels.find(function(c) { return c.id === id; });
        if (ch) onChannelSelect(ch, 'card');
      });

      // Activate Lampa navigation on .selector elements
      Lampa.Controller.toggle('content');
    }

    // Refresh EPG labels when data loads — keep named reference for cleanup
    function onEpgLoaded() {
      document.querySelectorAll('.liptv-row[data-id]').forEach(function(el) {
        const cur    = epg.getCurrent(el.dataset.id);
        const progEl = el.querySelector('.liptv-row-prog');
        if (progEl && cur) progEl.textContent = cur.title;
      });
    }
    Lampa.Listener.follow('liptv:epg_loaded', onEpgLoaded);

    return {
      render:  render,
      destroy: function() { Lampa.Listener.remove('liptv:epg_loaded'); }
    };
  }

  function showSearch(allChannels) {
    // Lampa.Keypad is the documented API for text input.
    // Falls back to a simple prompt for environments where Keypad is unavailable.
    if (Lampa.Keypad && typeof Lampa.Keypad.show === 'function') {
      Lampa.Keypad.show({
        title:   'Поиск',
        value:   '',
        confirm: function(query) { doSearch(query, allChannels); }
      });
    } else {
      // Minimal fallback: browser prompt (web preview / desktop testing)
      const query = window.prompt('Поиск (название канала или передачи):');
      if (query) doSearch(query, allChannels);
    }
  }

  function doSearch(query, allChannels) {
    const q = (query || '').toLowerCase().trim();
    if (!q) return;

    const byName    = allChannels.filter(function(ch) { return ch.name.toLowerCase().includes(q); });
    const nameIds   = new Set(byName.map(function(ch) { return ch.id; }));
    const byProg    = allChannels.filter(function(ch) {
      return !nameIds.has(ch.id) &&
        epg.getAll(ch.id).some(function(p) { return p.title.toLowerCase().includes(q); });
    });
    const results = byName.concat(byProg);

    if (results.length === 0) {
      Lampa.Noty.show('Ничего не найдено');
      return;
    }

    Lampa.Select.show({
      title:    'Результаты (' + results.length + ')',
      items:    results.map(function(ch) {
        const cur = epg.getCurrent(ch.id);
        return { title: ch.name, subtitle: cur ? cur.title : '', channel: ch };
      }),
      onSelect: function(item) { showCard(item.channel, function() {}); }
    });
  }

  function promptUrl(title, current, callback) {
    if (window.Lampa && Lampa.Keypad && typeof Lampa.Keypad.show === 'function') {
      Lampa.Keypad.show({
        title:   title,
        value:   current,
        confirm: callback
      });
    } else {
      const val = window.prompt(title + ':', current);
      if (val !== null) callback(val);
    }
  }

  function registerSettings(onM3uChange, onEpgChange) {
    Lampa.SettingsApi.addComponent({
      component: 'liptv',
      icon: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M21 3H3c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h5v2h8v-2h5c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 14H3V5h18v12z"/></svg>',
      name: 'IPTV'
    });

    Lampa.SettingsApi.addParam({
      component: 'liptv',
      param:  { name: 'liptv_m3u_url', type: 'trigger', default: false },
      field:  { name: 'M3U URL', description: storage.getM3uUrl() || 'Не задан' },
      onChange: function() {
        promptUrl('M3U URL', storage.getM3uUrl() || '', function(v) {
          v = v.trim();
          storage.setM3uUrl(v);
          if (typeof onM3uChange === 'function') onM3uChange(v);
        });
      }
    });

    // Build values object for select from EPG_PRESETS
    var epgValues = {};
    Object.keys(EPG_PRESETS).forEach(function(key) {
      epgValues[key] = EPG_PRESETS[key].label;
    });

    Lampa.SettingsApi.addParam({
      component: 'liptv',
      param: {
        name:    'liptv_epg_source',
        type:    'select',
        values:  epgValues,
        default: 'auto'
      },
      field:    { name: 'Источник EPG' },
      onChange: function() {
        if (typeof onEpgChange === 'function') onEpgChange();
      }
    });

    Lampa.SettingsApi.addParam({
      component: 'liptv',
      param:  { name: 'liptv_epg_url', type: 'trigger', default: false },
      field:  { name: 'EPG URL (свой)', description: storage.getEpgUrl() || 'Не задан' },
      onChange: function() {
        if (storage.getEpgSource() !== 'custom') {
          Lampa.Noty.show('Выберите "Свой URL" в источнике EPG');
          return;
        }
        promptUrl('EPG URL', storage.getEpgUrl() || '', function(v) {
          storage.setEpgUrl(v.trim());
          if (typeof onEpgChange === 'function') onEpgChange();
        });
      }
    });

    Lampa.SettingsApi.addParam({
      component: 'liptv',
      param: {
        name:    'liptv_view_mode',
        type:    'select',
        values:  { list: 'Список', grid: 'Сетка' },
        default: 'list'
      },
      field:    { name: 'Режим отображения' },
      onChange: function() { /* Lampa stores select value automatically */ }
    });

    Lampa.SettingsApi.addParam({
      component: 'liptv',
      param:    { name: 'liptv_hidden', type: 'trigger', default: false },
      field:    { name: 'Скрытые каналы', description: 'Каналы, убранные из списка' },
      onChange: function() { showHiddenChannels(); }
    });

    Lampa.SettingsApi.addParam({
      component: 'liptv',
      param:    { name: 'liptv_clear_history', type: 'trigger', default: false },
      field:    { name: 'Очистить историю просмотров' },
      onChange: function() {
        storage.clearHistory();
        Lampa.Noty.show('История очищена');
      }
    });
  }

  let _channelMap = {};
  function setChannelMap(map) { _channelMap = map; }

  function showHiddenChannels() {
    const blacklist = storage.getBlacklist();
    if (blacklist.length === 0) {
      Lampa.Noty.show('Нет скрытых каналов');
      return;
    }

    Lampa.Select.show({
      title: 'Скрытые каналы',
      items: blacklist.map(function(id) {
        return { title: _channelMap[id] || id, subtitle: 'Нажмите для восстановления', id: id };
      }),
      onSelect: function(item) {
        storage.removeBlacklist(item.id);
        Lampa.Noty.show('Канал "' + item.title + '" восстановлен');
      }
    });
  }

  var KEY = {
    CH_UP:   [166, 33],
    CH_DOWN: [167, 34],
    OK:      [13],
    BACK:    [8, 27],
    LEFT:    [37],
    UP:      [38],
    DOWN:    [40]
  };

  function isKey(keyCode, group) {
    return group.indexOf(keyCode) !== -1;
  }

  function formatTime(ts) {
    if (!ts) return '';
    var d = (ts instanceof Date) ? ts : new Date(ts);
    var h = d.getHours();
    var m = d.getMinutes();
    return (h < 10 ? '0' + h : h) + ':' + (m < 10 ? '0' + m : m);
  }

  function getNeighbors(channels, currentIndex) {
    var len = channels.length;
    if (len === 0) return [];

    var count = Math.min(5, len);
    var half  = Math.floor(count / 2);
    var result = [];

    for (var i = 0; i < count; i++) {
      var offset = i - half;
      var idx    = ((currentIndex + offset) % len + len) % len;
      result.push({
        channel:   channels[idx],
        index:     idx,
        isCurrent: idx === currentIndex
      });
    }

    return result;
  }

  function renderOsdHtml(neighbors) {
    var html = '';
    for (var i = 0; i < neighbors.length; i++) {
      var item = neighbors[i];
      var ch   = item.channel;
      var cls  = 'liptv-osd-item' + (item.isCurrent ? ' current' : '');
      var prog = '';

      if (item.isCurrent) {
        var cur = epg.getCurrent(ch.id);
        prog = cur ? cur.title : '';
      }

      html += '<div class="' + cls + '">' +
        '<span class="liptv-osd-num">' + (item.index + 1) + '</span>' +
        '<span class="liptv-osd-name">' + _esc(ch.name) + '</span>' +
        (prog ? '<span class="liptv-osd-prog">' + _esc(prog) + '</span>' : '') +
        '</div>';
    }
    return html;
  }

  function renderEpgHtml(channel) {
    var programs = epg.getAll(channel.id);
    if (programs.length === 0) {
      return '<div class="liptv-epg-title">' + _esc(channel.name) + '</div>' +
             '<div class="liptv-epg-empty">Нет данных о программе</div>';
    }

    var now  = Date.now();
    var html = '<div class="liptv-epg-title">' + _esc(channel.name) + '</div>';

    for (var i = 0; i < programs.length; i++) {
      var p         = programs[i];
      var startMs   = p.start ? p.start.getTime() : 0;
      var stopMs    = p.stop  ? p.stop.getTime()  : Infinity;
      var isCurrent = startMs <= now && now < stopMs;
      var isPast    = stopMs  <= now;

      var cls = 'liptv-epg-item';
      if (isPast)    cls += ' past';
      if (isCurrent) cls += ' now';

      var progress = '';
      if (isCurrent && p.stop && p.start) {
        var total = stopMs - startMs;
        var done  = now - startMs;
        var pct   = total > 0 ? Math.min(100, Math.round(done / total * 100)) : 0;
        progress  = '<div class="liptv-epg-progress">' +
                    '<div class="liptv-epg-progress-fill" style="width:' + pct + '%"></div>' +
                    '</div>';
      }

      var timeStr = formatTime(p.start) + (p.stop ? ' – ' + formatTime(p.stop) : '');
      if (isCurrent) timeStr += ' · Сейчас';

      html += '<div class="' + cls + '" data-epg-index="' + i + '">' +
        '<div class="liptv-epg-time">' + timeStr + '</div>' +
        '<div class="liptv-epg-prog-title">' + _esc(p.title) + '</div>' +
        progress +
        '</div>';
    }

    return html;
  }

  function _esc(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function createOsd(channels, onSwitch) {
    // Create DOM elements
    var osdEl = document.createElement('div');
    osdEl.className = 'liptv-osd';

    var epgEl = document.createElement('div');
    epgEl.className = 'liptv-epg';

    document.body.appendChild(osdEl);
    document.body.appendChild(epgEl);

    var _currentIndex = 0;
    var _hideTimer    = null;
    var _epgVisible   = false;
    var _osdVisible   = false;
    var _epgItems     = [];
    var _epgFocusIdx  = -1;

    // ── OSD ──────────────────────────────────────────────────────────────────

    function show(currentIndex) {
      _currentIndex = currentIndex;
      _resetTimer();
      _renderOsd();
      osdEl.classList.add('visible');
      osdEl.classList.remove('fade-out');
      _osdVisible = true;
    }

    function hide() {
      clearTimeout(_hideTimer);
      _hideTimer = null;
      osdEl.classList.remove('visible', 'fade-out');
      _osdVisible = false;
    }

    function _renderOsd() {
      var neighbors = getNeighbors(channels, _currentIndex);
      osdEl.innerHTML = renderOsdHtml(neighbors);
    }

    function _resetTimer() {
      clearTimeout(_hideTimer);
      _hideTimer = setTimeout(function() {
        osdEl.classList.add('fade-out');
        setTimeout(function() {
          osdEl.classList.remove('visible', 'fade-out');
          _osdVisible = false;
        }, 350);
      }, 3000);
    }

    // ── EPG sidebar ───────────────────────────────────────────────────────────

    function showEpgSidebar(channel) {
      hide(); // hide OSD while EPG is open
      epgEl.innerHTML = renderEpgHtml(channel);
      epgEl.classList.add('visible');
      epgEl.classList.remove('hiding');
      _epgVisible  = true;
      _epgFocusIdx = -1;

      // Collect focusable items
      _epgItems = epgEl.querySelectorAll('.liptv-epg-item');

      // Auto-scroll to current program
      var nowItem = epgEl.querySelector('.liptv-epg-item.now');
      if (nowItem) {
        // Set focus on current program
        var items = Array.prototype.slice.call(_epgItems);
        _epgFocusIdx = items.indexOf(nowItem);
        nowItem.classList.add('focus');
        nowItem.scrollIntoView({ block: 'center', behavior: 'smooth' });
      }
    }

    function hideEpgSidebar() {
      epgEl.classList.add('hiding');
      setTimeout(function() {
        epgEl.classList.remove('visible', 'hiding');
        _epgVisible  = false;
        _epgItems    = [];
        _epgFocusIdx = -1;
      }, 280);
    }

    // ── EPG navigation helpers ────────────────────────────────────────────────

    function _epgMoveFocus(direction) {
      var items = epgEl.querySelectorAll('.liptv-epg-item');
      if (items.length === 0) return;

      if (_epgFocusIdx >= 0 && _epgFocusIdx < items.length) {
        items[_epgFocusIdx].classList.remove('focus');
      }

      _epgFocusIdx += direction;
      if (_epgFocusIdx < 0)             _epgFocusIdx = 0;
      if (_epgFocusIdx >= items.length) _epgFocusIdx = items.length - 1;

      items[_epgFocusIdx].classList.add('focus');
      items[_epgFocusIdx].scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }

    // ── Channel switch helper ─────────────────────────────────────────────────

    function _switchChannel(direction) {
      var next = _currentIndex + direction;
      if (next >= channels.length) next = 0;
      if (next < 0)                next = channels.length - 1;
      _currentIndex = next;
      if (typeof onSwitch === 'function') onSwitch(channels[_currentIndex], _currentIndex);
    }

    // ── Keyboard handler ──────────────────────────────────────────────────────

    function _onKeyDown(e) {
      var kc = e.keyCode;

      // Layer 3: EPG sidebar open
      if (_epgVisible) {
        if (isKey(kc, KEY.UP)) {
          e.preventDefault(); e.stopPropagation();
          _epgMoveFocus(-1);
          return;
        }
        if (isKey(kc, KEY.DOWN)) {
          e.preventDefault(); e.stopPropagation();
          _epgMoveFocus(1);
          return;
        }
        if (isKey(kc, KEY.LEFT) || isKey(kc, KEY.BACK)) {
          e.preventDefault(); e.stopPropagation();
          hideEpgSidebar();
          return;
        }
        if (isKey(kc, KEY.CH_UP)) {
          e.preventDefault(); e.stopPropagation();
          _switchChannel(1);
          showEpgSidebar(channels[_currentIndex]);
          return;
        }
        if (isKey(kc, KEY.CH_DOWN)) {
          e.preventDefault(); e.stopPropagation();
          _switchChannel(-1);
          showEpgSidebar(channels[_currentIndex]);
          return;
        }
        // All other keys pass through
        return;
      }

      // Layer 2: OSD visible
      if (_osdVisible) {
        if (isKey(kc, KEY.CH_UP)) {
          e.preventDefault(); e.stopPropagation();
          _switchChannel(1);
          show(_currentIndex);
          return;
        }
        if (isKey(kc, KEY.CH_DOWN)) {
          e.preventDefault(); e.stopPropagation();
          _switchChannel(-1);
          show(_currentIndex);
          return;
        }
        if (isKey(kc, KEY.OK)) {
          e.preventDefault(); e.stopPropagation();
          showEpgSidebar(channels[_currentIndex]);
          return;
        }
        if (isKey(kc, KEY.BACK)) {
          e.preventDefault(); e.stopPropagation();
          hide();
          return;
        }
        // All other keys pass through
        return;
      }

      // Layer 1: nothing shown
      if (isKey(kc, KEY.CH_UP)) {
        e.preventDefault(); e.stopPropagation();
        _switchChannel(1);
        show(_currentIndex);
        return;
      }
      if (isKey(kc, KEY.CH_DOWN)) {
        e.preventDefault(); e.stopPropagation();
        _switchChannel(-1);
        show(_currentIndex);
        return;
      }
      // All other keys pass to native Lampa player
    }

    document.addEventListener('keydown', _onKeyDown, true);

    // ── Destroy ───────────────────────────────────────────────────────────────

    function destroy() {
      clearTimeout(_hideTimer);
      document.removeEventListener('keydown', _onKeyDown, true);
      if (osdEl.parentNode) osdEl.parentNode.removeChild(osdEl);
      if (epgEl.parentNode) epgEl.parentNode.removeChild(epgEl);
    }

    return {
      show:            show,
      hide:            hide,
      setIndex:        function(idx) { _currentIndex = idx; },
      showEpgSidebar:  showEpgSidebar,
      hideEpgSidebar:  hideEpgSidebar,
      destroy:         destroy
    };
  }

  (function() {

    let historyTimer    = null;
    let _mainScreen     = null;
    let _body           = null;
    let _channels       = [];   // current channel list — used by player history tracking
    let _osd = null;
    let _switching = false;     // guard: prevents Player 'destroy' from killing OSD during channel switch

    function startHistoryTracking(channelId) {
      clearTimeout(historyTimer);
      historyTimer = setTimeout(function() { storage.addHistory(channelId); }, 10000);
    }

    function stopHistoryTracking() {
      clearTimeout(historyTimer);
      historyTimer = null;
    }

    // Called on first launch and whenever M3U URL changes via settings.
    // Fetches playlist, (re)builds the main screen, starts EPG in background.
    async function loadAndRender() {
      const m3uUrl = storage.getM3uUrl();

      if (!m3uUrl) {
        Lampa.Noty.show('IPTV: укажите M3U URL в настройках');
        Lampa.Activity.push({ component: 'settings', url: '', title: 'Настройки' });
        return;
      }

      let parsed;
      try {
        parsed = await fetchM3U(m3uUrl);
      } catch (e) {
        // TODO (v0.2.0): replace with error screen + "Повторить" button (Known Gap)
        Lampa.Noty.show('Не удалось загрузить плейлист: ' + e.message, { style: 'error', time: 5000 });
        return;
      }

      const channels       = parsed.channels;
      const playlistEpgUrl = parsed.playlistEpgUrl;

      _channels = channels;

      const channelMap = {};
      channels.forEach(function(ch) { channelMap[ch.id] = ch.name; });
      setChannelMap(channelMap);

      // Clean up previous main screen listener before creating a new one
      if (_mainScreen) _mainScreen.destroy();

      _mainScreen = createMainScreen(channels, function(channel, action) {
        if (action === 'search') return showSearch(channels);
        if (action === 'card')   return showCard(channel, function() { if (_body && _mainScreen) _mainScreen.render(_body); });
      });

      if (_body) _mainScreen.render(_body);

      // Resolve EPG source and start fetch in background
      epg.reset();
      const epgSource = storage.getEpgSource();
      const resolved = resolveEpgUrls(epgSource, channels, playlistEpgUrl, storage.getEpgUrl());
      if (resolved.urls.length === 0 && epgSource === 'auto' && !playlistEpgUrl) {
        Lampa.Noty.show('Не удалось определить EPG автоматически, выберите источник в настройках');
      }
      if (resolved.urls.length === 0 && epgSource === 'playlist' && !playlistEpgUrl) {
        Lampa.Noty.show('Плейлист не содержит EPG URL');
      }
      if (resolved.urls.length === 0 && epgSource === 'custom') {
        Lampa.Noty.show('Укажите EPG URL в настройках');
      }
      epg.init(resolved.urls, channels, resolved.needsMapping);
      epg.fetchInBackground();
    }

    function init() {
      injectStyles();

      // Register component once — create() and destroy() called by Lampa lifecycle
      class LiptvMain {
        constructor(object) { this.activity = object; }
        render() {
          this.html = $('<div class="liptv-container"></div>');
          _body = this.html;
          loadAndRender();
          return this.html[0];
        }
        create()  { return this.render(); }
        start()   {}
        pause()   {}
        stop()    {}
        destroy() {
          stopHistoryTracking();
          if (_mainScreen) { _mainScreen.destroy(); _mainScreen = null; }
          _body = null;
        }
      }
      Lampa.Component.add('liptv_main', LiptvMain);

      // Track current playing channel immediately when playChannel() is called
      setOnPlay(function(channel) {
        _switching = true;
        channel.url;
        startHistoryTracking(channel.id);

        // Create OSD only once; reuse across channel switches
        if (!_osd) {
          var blacklist = storage.getBlacklist();
          var visible = _channels.filter(function(ch) { return !blacklist.includes(ch.id); });
          _osd = createOsd(visible, function(switchedChannel) {
            playChannel(switchedChannel);
          });
        }

        var blacklist = storage.getBlacklist();
        var visible = _channels.filter(function(ch) { return !blacklist.includes(ch.id); });
        var idx = visible.findIndex(function(ch) { return ch.url === channel.url; });
        if (idx >= 0) _osd.setIndex(idx);
        _switching = false;
      });

      // Register player listeners once
      Lampa.Player.listener.follow('destroy', function() {
        stopHistoryTracking();
        // Don't destroy OSD during channel switch — Player fires 'destroy' for the old stream
        if (!_switching && _osd) { _osd.destroy(); _osd = null; }
      });

      // Re-render when user updates M3U URL in settings
      registerSettings(
        function() { loadAndRender(); },   // onM3uChange
        function() { loadAndRender(); }    // onEpgChange — reload EPG
      );

      // Add IPTV item to the left sidebar menu
      var menuIcon = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M21 3H3c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h5v2h8v-2h5c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 14H3V5h18v12z"/></svg>';
      var menuItem = $('<li class="menu__item selector" data-action="liptv">' +
        '<div class="menu__ico">' + menuIcon + '</div>' +
        '<div class="menu__text">IPTV 3</div>' +
        '</li>');

      menuItem.on('hover:enter', function() {
        Lampa.Activity.push({ component: 'liptv_main', url: '', title: 'IPTV' });
      });

      // Insert before Settings item if found, otherwise append to end
      var settingsItem = $('.menu .menu__list .menu__item[data-action="settings"]');
      if (settingsItem.length) {
        settingsItem.before(menuItem);
      } else {
        $('.menu .menu__list').eq(0).append(menuItem);
      }

      /* compare-mode: do not auto-open IPTV screen on app startup; only open from menu */
    }

    // Verified init pattern from docs/lampa-api-notes.md
    if (window.appready) {
      init();
    } else {
      Lampa.Listener.follow('app', function(e) {
        if (e.type === 'ready') init();
      });
    }
  })();

})();
