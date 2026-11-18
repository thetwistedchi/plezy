import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../utils/app_logger.dart';
import 'youtube_settings.dart';

/// Shared WebView2 setup for the YouTube player and the YouTube web sign-in.
///
/// Both use one browser profile (its own folder in the app's support
/// directory), so signing in to youtube.com once gives the embedded player
/// the account's YouTube Premium. The player page is served from a virtual
/// https host, because YouTube refuses embeds without a proper origin.
class YouTubeWebView {
  YouTubeWebView._();

  static const String host = 'plezy-yt.local';

  /// The cache limit the running browser was started with, in MB. Changing
  /// the setting takes effect at the next app start.
  static int? activeCacheLimitMb;

  /// The player's browser profile folder and Chromium arguments, set by
  /// [ensureReady]. Every WebView on this profile must use the same ones.
  static String? profilePath;
  static String? browserArguments;

  static const _cacheFolders = {'Cache', 'Code Cache', 'GPUCache', 'Service Worker', 'DawnCache', 'ShaderCache'};
  static Future<String>? _ready;

  static bool get isSupported => Platform.isWindows;

  /// Initializes the WebView2 environment once and writes the player page.
  /// Returns the folder the virtual host serves.
  static Future<String> ensureReady() => _ready ??= _init();

  static Future<String> _init() async {
    final support = await getApplicationSupportDirectory();
    final sep = Platform.pathSeparator;
    final profile = Directory('${support.path}${sep}youtube_webview');
    final pageDir = Directory('${support.path}${sep}youtube_player');
    await profile.create(recursive: true);
    await pageDir.create(recursive: true);
    await File('${pageDir.path}${sep}player.html').writeAsString(playerHtml, flush: true);
    await YouTubeSettings.instance.load();
    final limitMb = YouTubeSettings.instance.playerCacheLimitMb;
    activeCacheLimitMb = limitMb;
    profilePath = profile.path;
    // Chromium pauses or throttles pages it thinks are hidden or covered;
    // its occlusion check gets confused with several monitors.
    browserArguments = [
      '--autoplay-policy=no-user-gesture-required',
      '--disk-cache-size=${limitMb * 1024 * 1024}',
      '--disable-background-timer-throttling',
      '--disable-renderer-backgrounding',
      '--disable-backgrounding-occluded-windows',
      '--disable-features=CalculateNativeWinOcclusion',
    ].join(' ');
    try {
      // The sign-in window still uses webview_windows; with the same folder
      // and the same arguments it shares the player's browser profile.
      await WebviewController.initializeEnvironment(userDataPath: profile.path, additionalArguments: browserArguments);
    } on PlatformException catch (e) {
      // Already initialized in this process.
      appLogger.d('WebView2 environment: ${e.message}');
    }
    return pageDir.path;
  }

  static Future<Directory> _profileDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}youtube_webview');
  }

  /// Bytes used by the player's browser caches (not its cookies/sign-in).
  static Future<int> cacheSize() async {
    final profile = await _profileDir();
    if (!await profile.exists()) return 0;
    var total = 0;
    try {
      await for (final entity in profile.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final parts = entity.path.split(Platform.pathSeparator);
        if (!parts.any(_cacheFolders.contains)) continue;
        try {
          total += await entity.length();
        } catch (_) {}
      }
    } catch (e) {
      appLogger.d('WebView2 cache size: $e');
    }
    return total;
  }

  /// Clears the player's browser cache and keeps the YouTube sign-in.
  static Future<void> clearCache() async {
    await ensureReady();
    final controller = WebviewController();
    try {
      await controller.initialize();
      await controller.clearCache();
    } finally {
      unawaited(controller.dispose());
    }
  }

  static Uri playerUrl(String videoId, {double start = 0, String language = 'en'}) =>
      Uri.https(host, '/player.html', {
        'v': videoId,
        'hl': language,
        if (start > 0) 't': start.floor().toString(),
      });

  /// Injected into every document of the player's WebView, including the
  /// YouTube embed frame, where it reaches the real <video> element and the
  /// player's internal API: any playback speed (1.1×, 1.2×) and quality
  /// selection, which the IFrame API no longer offers. Talks to the host page
  /// with window.postMessage.
  static const String frameScript = r'''(function(){
  if (location.hostname.indexOf('youtube.com') < 0 || location.pathname.indexOf('/embed/') !== 0) return;
  var desiredRate = null;
  // Hide YouTube's own overlays: the "More videos" shelf, end screen cards
  // and the title bar. The player shows its own channel videos instead. The
  // YouTube logo stays.
  var css = '.ytp-pause-overlay,.ytp-pause-overlay-container,.ytp-endscreen-content,.ytp-ce-element,' +
    '.ytp-chrome-top,.ytp-gradient-top,.ytp-show-cards-title,.ytp-cards-teaser,.ytp-cards-button,' +
    '.ytp-suggested-action,.ytp-paid-content-overlay{display:none!important}';
  function addStyle(){
    if (document.getElementById('plezy-style')) return;
    var s = document.createElement('style');
    s.id = 'plezy-style';
    s.textContent = css;
    (document.head || document.documentElement).appendChild(s);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', addStyle); else addStyle();
  function player(){ return document.getElementById('movie_player'); }
  function video(){ return document.querySelector('video'); }
  function applyRate(){ var v = video(); if (v && desiredRate !== null && Math.abs(v.playbackRate - desiredRate) > 0.001) v.playbackRate = desiredRate; }
  document.addEventListener('ratechange', applyRate, true);
  document.addEventListener('loadeddata', applyRate, true);
  window.addEventListener('message', function(e){
    var m = e.data;
    if (!m || !m.plezy) return;
    var p = player();
    if (m.plezy === 'rate') { desiredRate = m.r; applyRate(); }
    if (m.plezy === 'cc' && p) {
      try { p.loadModule('captions'); } catch (err) {}
      if (m.off) {
        try { p.setOption('captions', 'track', {}); } catch (err) {}
      } else {
        try {
          var list = [];
          try { list = p.getOption('captions', 'tracklist', {includeAsr: true}) || []; } catch (err) {}
          var found = null;
          for (var i = 0; i < list.length; i++) {
            var t = list[i];
            if (t.languageCode === m.code && ((t.kind || '') === (m.kind || ''))) { found = t; break; }
          }
          var track = found ? Object.assign({}, found) : {languageCode: m.code};
          if (!found && m.kind) track.kind = m.kind;
          if (m.tr) track.translationLanguage = {languageCode: m.tr};
          p.setOption('captions', 'track', track);
        } catch (err) {}
      }
    }
    if (m.plezy === 'audio' && p) {
      try {
        var tracks = p.getAvailableAudioTracks() || [];
        if (tracks[m.index]) p.setAudioTrack(tracks[m.index]);
      } catch (err) {}
    }
    if (m.plezy === 'quality' && p) {
      try { if (p.setPlaybackQualityRange) p.setPlaybackQualityRange(m.q, m.q); } catch (err) {}
      try { if (p.setPlaybackQuality) p.setPlaybackQuality(m.q); } catch (err) {}
    }
  });
  var ccLoaded = false;
  var lastReport = '';
  function captionInfo(p){
    var list = [], cur = null, trans = [];
    try { list = p.getOption('captions', 'tracklist', {includeAsr: true}) || []; } catch (err) {}
    if (!list.length) { try { list = p.getOption('captions', 'tracklist') || []; } catch (err) {} }
    try { cur = p.getOption('captions', 'track') || null; } catch (err) {}
    try { trans = p.getOption('captions', 'translationLanguages') || []; } catch (err) {}
    return {
      tracks: list.map(function(t){ return {code: t.languageCode || '', name: t.displayName || t.languageName || t.languageCode || '', kind: t.kind || ''}; }),
      current: cur && cur.languageCode ? {code: cur.languageCode, kind: cur.kind || '',
        tr: cur.translationLanguage ? cur.translationLanguage.languageCode : null} : null,
      translations: trans.map(function(l){ return {code: l.languageCode, name: l.languageName}; })
    };
  }
  function audioInfo(p){
    var out = [], current = -1;
    try {
      var tracks = p.getAvailableAudioTracks ? (p.getAvailableAudioTracks() || []) : [];
      var active = p.getAudioTrack ? p.getAudioTrack() : null;
      var activeId = null;
      try { activeId = active && active.getLanguageInfo ? active.getLanguageInfo().getId() : null; } catch (err) {}
      tracks.forEach(function(t, i){
        var info = null, name = '', id = '';
        try { info = t.getLanguageInfo ? t.getLanguageInfo() : null; } catch (err) {}
        try { name = info && info.getName ? info.getName() : (t.name || ''); } catch (err) {}
        try { id = info && info.getId ? info.getId() : (t.id || ''); } catch (err) {}
        out.push({name: String(name || id || ('Track ' + (i + 1))), id: String(id || '')});
        if (active === t || (activeId !== null && activeId === id)) current = i;
      });
    } catch (err) {}
    return {tracks: out, current: current};
  }
  function storyboard(p){
    try { if (p.getStoryboardFormat) { var f = p.getStoryboardFormat(); if (f) return String(f); } } catch (err) {}
    try {
      var r = p.getPlayerResponse ? p.getPlayerResponse() : null;
      var s = r && r.storyboards && r.storyboards.playerStoryboardSpecRenderer;
      if (s && s.spec) return s.spec;
    } catch (err) {}
    return '';
  }
  setInterval(function(){
    var p = player();
    if (!p || !p.getAvailableQualityLevels) return;
    if (!ccLoaded) {
      // The track list only exists once the captions module is loaded;
      // load it, then switch captions off until Flutter picks a track.
      ccLoaded = true;
      try { p.loadModule('captions'); } catch (err) {}
      setTimeout(function(){ try { p.setOption('captions', 'track', {}); } catch (err) {} }, 300);
    }
    try {
      var data = [];
      if (p.getAvailableQualityData) {
        data = p.getAvailableQualityData().map(function(d){ return {q: d.quality, label: d.qualityLabel || ''}; });
      }
      var payload = {plezyFrame: 'quality', levels: p.getAvailableQualityLevels(), current: p.getPlaybackQuality(),
        currentLabel: p.getPlaybackQualityLabel ? p.getPlaybackQualityLabel() : '', data: data,
        cc: captionInfo(p), audio: audioInfo(p), sb: storyboard(p)};
      // Only report changes; most seconds nothing changes.
      var text = JSON.stringify(payload);
      if (text === lastReport) return;
      lastReport = text;
      window.parent.postMessage(payload, '*');
    } catch (err) {}
  }, 1000);
})();''';

  /// The page hosting the YouTube IFrame player with YouTube's own controls
  /// hidden. It reports state to Flutter with chrome.webview.postMessage and
  /// takes commands from postWebMessage.
  static const String playerHtml = r'''<!doctype html>
<html><head><meta charset="utf-8"><meta name="referrer" content="strict-origin-when-cross-origin">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{position:absolute;left:0;top:0;width:100%;height:100%;border:0}</style>
</head><body><div id="p"></div>
<script>
var q = new URLSearchParams(location.search);
var player = null, ready = false;
function post(m){ try { window.chrome.webview.postMessage(m); } catch (e) {} }
var tag = document.createElement('script');
tag.src = 'https://www.youtube.com/iframe_api';
document.head.appendChild(tag);
function onYouTubeIframeAPIReady(){
  player = new YT.Player('p', {
    width: '100%', height: '100%', videoId: q.get('v'),
    playerVars: { controls: 0, autoplay: 1, rel: 0, playsinline: 1, iv_load_policy: 3, disablekb: 1, fs: 0,
      start: Math.floor(+(q.get('t') || 0)), origin: location.origin, enablejsapi: 1, hl: q.get('hl') || 'en' },
    events: {
      onReady: function(){ ready = true; post({t: 'ready'}); player.playVideo(); },
      onStateChange: function(e){ post({t: 'state', s: e.data}); },
      onError: function(e){ post({t: 'error', code: e.data}); },
      onPlaybackRateChange: function(e){ post({t: 'rate', r: e.data}); }
    }
  });
}
setInterval(function(){
  if (!ready) return;
  try {
    post({t: 'time', cur: player.getCurrentTime(), dur: player.getDuration(), buf: player.getVideoLoadedFraction(),
      vol: player.getVolume(), muted: player.isMuted()});
  } catch (e) {}
}, 250);
window.chrome.webview.addEventListener('message', function(e){
  var m = e.data;
  if (!player || !ready || !m) return;
  switch (m.cmd) {
    case 'play': player.playVideo(); break;
    case 'pause': player.pauseVideo(); break;
    case 'seek': player.seekTo(m.t, true); break;
    case 'volume': player.setVolume(m.v); break;
    case 'mute': if (m.on) player.mute(); else player.unMute(); break;
    case 'rate': player.setPlaybackRate(m.r); break;
    case 'load': player.loadVideoById({videoId: m.id, startSeconds: m.t || 0}); break;
    case 'frame':
      var f = document.getElementById('p');
      if (f && f.contentWindow) f.contentWindow.postMessage(m.msg, '*');
      break;
  }
});
window.addEventListener('message', function(e){
  if (e.data && e.data.plezyFrame === 'quality') post({t: 'quality', levels: e.data.levels, current: e.data.current,
    currentLabel: e.data.currentLabel, data: e.data.data, cc: e.data.cc, audio: e.data.audio});
});
document.addEventListener('keydown', function(e){
  post({t: 'key', k: e.key, shift: e.shiftKey});
  e.preventDefault();
});
</script></body></html>''';
}
