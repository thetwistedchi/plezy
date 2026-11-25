import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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

  static const MethodChannel _channel = MethodChannel('com.plezy.retrowave/youtube_web');

  /// The installed WebView2 runtime's version, or null without one.
  static Future<String?> runtimeVersion() async {
    try {
      return await _channel.invokeMethod<String>('runtimeVersion');
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String?>> _profileArgs() async {
    await ensureReady();
    return {'userDataFolder': profilePath, 'arguments': browserArguments};
  }

  /// Clears the player's browser cache and keeps the YouTube sign-in.
  static Future<void> clearCache() => _authRun('clearCache');

  /// Removes the player's YouTube cookies (signs out).
  static Future<void> clearCookies() => _authRun('clearCookies');

  /// Runs [action] on the sign-in view, or on a hidden one opened for it and
  /// closed afterwards (the native side says which).
  static Future<void> _authRun(String action) async {
    final bool? temporary;
    try {
      temporary = await _channel.invokeMethod<bool>('authRun', {...await _profileArgs(), 'action': action});
    } catch (_) {
      if (!_signInOpen) await closeSignIn().catchError((_) {});
      rethrow;
    }
    if (temporary == true && !_signInOpen) {
      // Outside the WebView's callback, so closing it is safe.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await closeSignIn();
    }
  }

  /// Opens the interactive sign-in view on the player's profile at [url].
  static Future<void> openSignIn(Uri url) async {
    _signInOpen = true;
    await _channel.invokeMethod<void>('authOpen', {...await _profileArgs(), 'url': url.toString()});
  }

  static bool _signInOpen = false;

  static Future<void> _historyChain = Future<void>.value();
  static final Set<String> _historyDone = {};
  static bool _backfillStarted = false;

  /// Once per app run with the setting on: the videos watched in the app
  /// before (at least 30 seconds) go into the YouTube history too, one
  /// after another in the background.
  static Future<int> backfillHistory({bool now = false}) async {
    if (!isSupported || (_backfillStarted && !now)) return 0;
    final settings = YouTubeSettings.instance;
    await settings.load();
    if (!settings.syncHistory) return 0;
    _backfillStarted = true;
    final backlog = await settings.historyBacklog();
    if (backlog.isEmpty) return 0;
    // A visit that failed before may be tried again.
    if (now) _historyDone.removeAll([for (final (id, _) in backlog) id]);
    appLogger.i('YouTube history: adding ${backlog.length} earlier videos in the background');
    for (final (id, position) in backlog) {
      addToHistory(id, position);
    }
    return backlog.length;
  }

  /// Adds [videoId] to the signed-in account's YouTube history: YouTube does
  /// not count plays in the embedded player, so the watch page is opened
  /// once in a hidden, muted WebView on the player's profile, at
  /// [position] seconds, and closed again after a few seconds. One video at
  /// a time; skipped while the sign-in page is open.
  static void addToHistory(String videoId, double position) {
    if (!isSupported || videoId.isEmpty || !_historyDone.add(videoId)) return;
    _historyChain = _historyChain.then((_) async {
      // Likes go first: the history can wait, a click should not.
      while (_likesWaiting > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (_signInOpen || !YouTubeSettings.instance.syncHistory) return;
      await _withHiddenView(() async {
        var interrupted = false;
        try {
          final url = Uri.https('www.youtube.com', '/watch', {
            'v': videoId,
            if (position >= 1) 't': '${position.floor()}s',
          });
          await _channel.invokeMethod<void>('authVisit', {...await _profileArgs(), 'url': url.toString()});
          for (var i = 0; i < 30; i++) {
            if (_likesWaiting > 0) {
              interrupted = true;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          if (interrupted) {
            // Tried again on the next backfill.
            _historyDone.remove(videoId);
            appLogger.d('YouTube history: visit cut short for a comment like');
          } else {
            await YouTubeSettings.instance.markHistorySynced(videoId);
            appLogger.d('YouTube history: watch page visited');
          }
        } catch (e) {
          appLogger.d('YouTube history visit failed', error: e);
        } finally {
          if (!_signInOpen) await closeSignIn().catchError((_) {});
        }
      });
    });
  }

  /// One user of the hidden view at a time (history visits, comment likes).
  static Future<void> _hiddenViewQueue = Future<void>.value();
  static int _likesWaiting = 0;

  static Future<T> _withHiddenView<T>(Future<T> Function() body) {
    final done = Completer<T>();
    _hiddenViewQueue = _hiddenViewQueue.then((_) async {
      try {
        done.complete(await body());
      } catch (e, stackTrace) {
        done.completeError(e, stackTrace);
      }
    });
    return done.future;
  }

  /// Fork: comments liked from the app this run, so the thumbs stay filled.
  static final ValueNotifier<Set<String>> likedComments = ValueNotifier(const {});

  /// Script polled in the hidden view. It likes the comment through the
  /// same internal requests youtube.com itself sends, with the page's own
  /// sign-in, so it needs neither a rendered page nor the comment on screen:
  /// the watch page's comments continuation (opened with `&lc=`, so the
  /// comment comes first), the comment's like action token, then
  /// `comment/perform_comment_action`. The first call starts that work; later
  /// calls answer "wait" until it ends with "liked", "unliked" or a reason.
  static String _likeScript(String commentId, bool like) => r'''
(() => {
  const S = window.__plezyLike || (window.__plezyLike = { state: 'idle' });
  if (S.state === 'running') return 'wait';
  if (S.state === 'done') return S.result;
  const video = document.querySelector('video');
  if (video) { video.muted = true; if (!video.paused) video.pause(); }
  if (!window.ytcfg || !window.ytInitialData || !window.ytcfg.get('INNERTUBE_API_KEY')) return 'wait';
  S.state = 'running';
  const commentId = '__CID__';
  const wantLike = __LIKE__;
  const walk = (o, fn, path) => {
    if (!o || typeof o !== 'object') return;
    fn(o, path);
    for (const k in o) walk(o[k], fn, path.concat(k));
  };
  const run = async () => {
    const cfg = window.ytcfg;
    const key = cfg.get('INNERTUBE_API_KEY');
    const cookie = (n) => {
      const c = document.cookie.split('; ').find((x) => x.startsWith(n + '='));
      return c ? c.substring(n.length + 1) : '';
    };
    const sapisid = cookie('SAPISID') || cookie('__Secure-3PAPISID');
    if (!sapisid) return 'signedout';
    const ts = Math.floor(Date.now() / 1000);
    const digest = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(ts + ' ' + sapisid + ' ' + location.origin));
    const hex = Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('');
    const headers = {
      'Content-Type': 'application/json',
      'Authorization': 'SAPISIDHASH ' + ts + '_' + hex,
      'X-Origin': location.origin,
      'X-Goog-AuthUser': String(cfg.get('SESSION_INDEX') || 0),
      'X-Youtube-Client-Name': String(cfg.get('INNERTUBE_CONTEXT_CLIENT_NAME') || 1),
      'X-Youtube-Client-Version': String(cfg.get('INNERTUBE_CLIENT_VERSION') || ''),
    };
    const post = async (path, body) => {
      const r = await fetch('/youtubei/v1/' + path + '?key=' + key + '&prettyPrint=false', {
        method: 'POST',
        credentials: 'include',
        headers,
        body: JSON.stringify(Object.assign({ context: cfg.get('INNERTUBE_CONTEXT') }, body)),
      });
      if (!r.ok) throw new Error(path + ' HTTP ' + r.status);
      return r.json();
    };
    let token = null;
    walk(window.ytInitialData, (o) => {
      if (token || !o.itemSectionRenderer || o.itemSectionRenderer.targetId !== 'comments-section') return;
      walk(o, (x) => {
        if (!token && x.continuationCommand && x.continuationCommand.token) token = x.continuationCommand.token;
      }, []);
    }, []);
    if (!token) return 'nocomments';
    const data = await post('next', { continuation: token });
    const decode = (t) => {
      try {
        return atob(decodeURIComponent(t).replace(/-/g, '+').replace(/_/g, '/'));
      } catch (e) {
        return '';
      }
    };
    let action = null;
    // Current responses: the comment's view model names its toolbar entity,
    // whose payload carries likeCommand / unlikeCommand.
    let surfaceKey = null;
    walk(data, (o) => {
      if (!surfaceKey && o.commentId === commentId && o.toolbarSurfaceKey) surfaceKey = o.toolbarSurfaceKey;
    }, []);
    if (surfaceKey) {
      walk(data, (o) => {
        if (action || o.entityKey !== surfaceKey || !o.payload) return;
        walk(o.payload, (x, path) => {
          const ep = x.performCommentActionEndpoint;
          if (action || !ep || !ep.action) return;
          const p = path.join('/').toLowerCase();
          if (p.includes('dislike')) return;
          if (p.includes('unlikecommand') === wantLike) return;
          action = ep.action;
        }, []);
      }, []);
    }
    // Older responses (and a fallback): the action token that names the comment.
    walk(data, (o, path) => {
      const ep = o.performCommentActionEndpoint;
      if (action || !ep || !ep.action) return;
      const p = path.join('/').toLowerCase();
      if (p.includes('dislike')) return;
      const isUnlike = p.includes('unlikecommand') || p.includes('toggledserviceendpoint');
      if (isUnlike === wantLike) return;
      if (!decode(ep.action).includes(commentId)) return;
      action = ep.action;
    }, []);
    if (!action) return 'noaction';
    const res = await post('comment/perform_comment_action', { actions: [action] });
    if (res && res.error) return 'rejected';
    return wantLike ? 'liked' : 'unliked';
  };
  run().then((r) => { S.result = r; S.state = 'done'; }, (e) => { S.result = 'error ' + (e && e.message ? e.message : e); S.state = 'done'; });
  return 'wait';
})()
'''.replaceAll('__CID__', commentId.replaceAll(RegExp(r"[^A-Za-z0-9_.\-]"), '')).replaceAll('__LIKE__', '$like');

  /// Likes (or un-likes) a comment with the signed-in account: the comment's
  /// page opens in the hidden, muted view, the like button is pressed there
  /// and the view closes again. YouTube's API cannot like comments. Shares
  /// the queue of the history visits; fails while the sign-in page is open.
  static Future<bool> setCommentLiked(String videoId, String commentId, {required bool like}) async {
    if (!isSupported || videoId.isEmpty || commentId.isEmpty) return false;
    _likesWaiting++;
    appLogger.d('YouTube comment ${like ? 'like' : 'unlike'}: queued');
    try {
      return await _withHiddenView(() async {
        if (_signInOpen) return false;
        var ok = false;
        final watch = Stopwatch()..start();
        try {
          final url = Uri.https('www.youtube.com', '/watch', {'v': videoId, 'lc': commentId});
          await _channel.invokeMethod<void>('authVisit', {...await _profileArgs(), 'url': url.toString()});
          String? last;
          while (watch.elapsed < const Duration(seconds: 25)) {
            await Future<void>.delayed(const Duration(milliseconds: 700));
            final raw = await _channel.invokeMethod<String>('authScript', {'script': _likeScript(commentId, like)});
            last = raw?.replaceAll('"', '');
            if (last == null || last == 'wait' || last == 'null') continue;
            ok = last == 'liked' || last == 'unliked';
            break;
          }
          appLogger.d(
            'YouTube comment ${like ? 'like' : 'unlike'}: ${ok ? 'done' : 'failed ($last)'} after ${watch.elapsedMilliseconds} ms',
          );
        } catch (e) {
          appLogger.d('YouTube comment like failed', error: e);
        } finally {
          if (!_signInOpen) await closeSignIn().catchError((_) {});
        }
        if (ok) {
          final next = {...likedComments.value};
          if (like) {
            next.add(commentId);
          } else {
            next.remove(commentId);
          }
          likedComments.value = next;
        }
        return ok;
      });
    } finally {
      _likesWaiting--;
    }
  }

  /// Places the sign-in view, in physical pixels of the Flutter view.
  static Future<void> setSignInRect({required int left, required int top, required int right, required int bottom}) =>
      _channel.invokeMethod<void>('authRect', {'left': left, 'top': top, 'right': right, 'bottom': bottom});

  static Future<void> closeSignIn() {
    _signInOpen = false;
    return _channel.invokeMethod<void>('authClose');
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
