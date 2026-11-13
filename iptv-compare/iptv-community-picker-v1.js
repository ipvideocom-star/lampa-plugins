/* IPTV test source picker v1 — no playlist URLs or access keys in GitHub.
   Server-only source configuration comes from an opaque JS file served under
   the existing Caddy playlist route; only existing Samsung/MSX UID hashes
   may render this menu. This plugin never changes IPTV 3/Plus/MaxTV settings. */
(function () {
  'use strict';
  if (window.__iptvCommunityPickerLoadedV1) return;
  window.__iptvCommunityPickerLoadedV1 = true;
  var whitelisted = ['e546300d', '1b192dce'];
  var polls = 0;
  function fingerprint(value) {
    var v = String(value || '').trim().toLowerCase();
    if (!/^[a-z0-9]{8,32}$/.test(v)) return '';
    var h = 2166136261;
    for (var i = 0; i < v.length; i++) h = Math.imul(h ^ v.charCodeAt(i), 16777619);
    return ('00000000' + (h >>> 0).toString(16)).slice(-8);
  }
  function enter() {
    if (!window.Lampa || !window.$ || !Lampa.Storage ||
        !window.appready || !Lampa.Select || !Lampa.Activity) return false;
    var uid = Lampa.Storage.get('lampac_unic_id', '');
    if (!uid) return false;
    if (whitelisted.indexOf(fingerprint(uid)) < 0) return true;
    var config = window.__iptvCommunitySourceConfigV1;
    if (!config || !Array.isArray(config.sources) || config.sources.length !== 3)
      return false;
    var menu = $('.menu .menu__list').eq(0);
    if (!menu.length) return false;
    if ($('.js-iptv-community-v1').length) return true;

    var item = $('<li class="menu__item selector js-iptv-community-v1">' +
      '<div class="menu__ico"><svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8M12 17v4"/></svg></div>' +
      '<div class="menu__text">IPTV — три плейлиста</div></li>');
    item.on('hover:enter', function() {
      var options = config.sources.map(function(source,i) {
        return {title:source.label + ' (' + source.count + ' записей)', idx:i};
      });
      Lampa.Select.show({
        title:'Выбор тестового IPTV',
        items:options,
        onSelect:function(selected) {
          if (!window.__iptvCompareApiV6) {
            Lampa.Noty.show('IPTV 3 ещё не обновился до версии с поддержкой трёх списков', {style:'error',time:5000});
            return;
          }
          var src = config.sources[selected.idx];
          if (!src || !/^https:\/\//.test(src.url)) return;
          Lampa.Activity.push({
            component:'liptv_main',
            title:'IPTV — ' + src.label,
            url:'',
            compare_m3u:src.url,
            compare_epg:'playlist',
            page:1
          });
        },
        onBack:function(){ Lampa.Controller.toggle('menu'); }
      });
    });
    menu.append(item);
    return true;
  }
  function poll() {
    try {
      if (enter()) return;
    } catch (e) {
      console.warn('IPTV community picker: init retry', e);
    }
    if (polls++ < 100) setTimeout(poll, 500);
  }
  poll();
})();
