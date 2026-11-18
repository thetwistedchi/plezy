import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../utils/app_logger.dart';
import 'youtube_webview.dart';

/// The YouTube player's WebView2, hosted natively (windows/runner/youtube).
///
/// It is a child window of the Flutter view, composited beneath the Flutter
/// UI like the mpv video, so the retrowave controls draw on top without any
/// frame capture. One instance is reused for every video; it is hidden and
/// suspended while no player is open.
class YouTubePlayerHost {
  YouTubePlayerHost._() {
    _events.receiveBroadcastStream().listen(_onEvent, onError: (Object e) => appLogger.d('YouTube web event: $e'));
  }

  static final YouTubePlayerHost instance = YouTubePlayerHost._();

  static const MethodChannel _channel = MethodChannel('com.plezy.retrowave/youtube_web');
  static const EventChannel _events = EventChannel('com.plezy.retrowave/youtube_web/events');

  final StreamController<dynamic> _messages = StreamController<dynamic>.broadcast();
  Future<void>? _ready;
  Future<void> _queue = Future<void>.value();
  bool _suspended = false;

  /// The last rect the player asked for; applied again to a new WebView.
  Map<String, int>? _rect;

  /// Messages from the page, already decoded from JSON. A crashed browser
  /// process arrives as `{'t': 'processFailed'}`.
  Stream<dynamic> get messages => _messages.stream;

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    switch (event['type']) {
      case 'message':
        try {
          _messages.add(jsonDecode(event['data'] as String? ?? 'null'));
        } catch (_) {}
      case 'processFailed':
        appLogger.w('YouTube WebView process failed (kind ${event['data']})');
        _messages.add({'t': 'processFailed'});
    }
  }

  /// Runs [op] after the previous host operation, so closing one player and
  /// opening the next can't interleave.
  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> ensureReady() {
    final ready = _ready ??= _init();
    return ready.catchError((Object e) {
      _ready = null;
      throw e;
    });
  }

  Future<void> _init() async {
    final folder = await YouTubeWebView.ensureReady();
    await _channel.invokeMethod<bool>('initialize', {
      'userDataFolder': YouTubeWebView.profilePath,
      'arguments': YouTubeWebView.browserArguments,
      'hostName': YouTubeWebView.host,
      'hostFolder': folder,
      'script': YouTubeWebView.frameScript,
    });
    final rect = _rect;
    if (rect != null) await _channel.invokeMethod<void>('setRect', rect);
  }

  /// Shows the WebView and loads [url].
  Future<void> open(Uri url) => _serial(() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    await ensureReady();
    if (_suspended) {
      await _channel.invokeMethod<void>('resume');
      _suspended = false;
    }
    await setVisible(true);
    await _channel.invokeMethod<void>('loadUrl', {'url': url.toString()});
  });

  Future<void> post(String json) async {
    if (_ready == null || _suspended) return;
    try {
      await _channel.invokeMethod<void>('postWebMessage', {'json': json});
    } catch (_) {}
  }

  /// Whether the page still runs scripts, within [timeout].
  Future<bool> ping({Duration timeout = const Duration(seconds: 3)}) async {
    if (_ready == null || _suspended) return false;
    try {
      await _channel.invokeMethod<String>('executeScript', {'script': '1'}).timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Places the WebView, in physical pixels of the Flutter view.
  Future<void> setRect({required int left, required int top, required int right, required int bottom}) async {
    final rect = {'left': left, 'top': top, 'right': right, 'bottom': bottom};
    _rect = rect;
    if (_ready == null) return;
    try {
      await _channel.invokeMethod<void>('setRect', rect);
    } catch (_) {}
  }

  Future<void> setVisible(bool visible) async {
    if (_ready == null) return;
    try {
      await _channel.invokeMethod<void>('setVisible', {'visible': visible});
    } catch (_) {}
  }

  /// Throws the WebView away and starts a fresh one (with a new browser
  /// process) on the next [open]. Used after sleep or a crashed process.
  Future<void> reset() => _serial(() async {
    if (_ready == null) return;
    try {
      await _channel.invokeMethod<void>('dispose');
    } catch (e) {
      appLogger.d('YouTube player reset: $e');
    }
    _ready = null;
    _suspended = false;
    // Let the old browser process exit, so the new WebView doesn't join it.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
  });

  /// Stops playback, hides the WebView and suspends it until the next [open].
  Future<void> release() => _serial(() async {
    if (_ready == null) return;
    try {
      await ensureReady();
      await _channel.invokeMethod<void>('setVisible', {'visible': false});
      await _channel.invokeMethod<void>('loadUrl', {'url': 'about:blank'});
      await _channel.invokeMethod<void>('suspend');
      _suspended = true;
    } catch (e) {
      appLogger.d('YouTube player release: $e');
    }
    // A suspended WebView still holds its browser processes (100-200 MB).
    // Unused for [idleDispose], it goes completely; the next [open] builds a
    // new one, which takes a second or two longer.
    _idleTimer?.cancel();
    _idleTimer = Timer(idleDispose, () {
      _idleTimer = null;
      unawaited(_disposeIdle());
    });
  });

  static const idleDispose = Duration(minutes: 10);
  Timer? _idleTimer;

  Future<void> _disposeIdle() => _serial(() async {
    if (_ready == null || !_suspended) return;
    try {
      await _channel.invokeMethod<void>('dispose');
    } catch (e) {
      appLogger.d('YouTube player idle dispose: $e');
    }
    _ready = null;
    _suspended = false;
    appLogger.d('YouTube player: released after ${idleDispose.inMinutes} idle minutes');
  });
}
