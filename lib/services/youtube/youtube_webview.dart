import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../utils/app_logger.dart';

/// Shared WebView2 setup for the YouTube player and the YouTube web sign-in.
///
/// Both use one browser profile (its own folder in the app's support
/// directory), so signing in to youtube.com once gives the embedded player
/// the account's YouTube Premium. The player page is served from a virtual
/// https host, because YouTube refuses embeds without a proper origin.
class YouTubeWebView {
  YouTubeWebView._();

  static const String host = 'plezy-yt.local';
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
    try {
      await WebviewController.initializeEnvironment(
        userDataPath: profile.path,
        additionalArguments: '--autoplay-policy=no-user-gesture-required',
      );
    } on PlatformException catch (e) {
      // Already initialized in this process.
      appLogger.d('WebView2 environment: ${e.message}');
    }
    return pageDir.path;
  }

  static Uri playerUrl(String videoId, {double start = 0}) => Uri.https(host, '/player.html', {
    'v': videoId,
    if (start > 0) 't': start.floor().toString(),
  });

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
      start: Math.floor(+(q.get('t') || 0)), origin: location.origin, enablejsapi: 1 },
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
    case 'cc': if (m.on) player.loadModule('captions'); else player.unloadModule('captions'); break;
  }
});
document.addEventListener('keydown', function(e){
  post({t: 'key', k: e.key, shift: e.shiftKey});
  e.preventDefault();
});
</script></body></html>''';
}
