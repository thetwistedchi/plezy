import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../utils/app_logger.dart';
import 'youtube_webview.dart';

/// One WebView2 for every YouTube video, created once and reused.
///
/// Creating a WebView per player meant a new browser process and a new
/// Windows capture session (which runs through the Desktop Window Manager)
/// each time. Reusing one, capping it at 60 fps and suspending it while no
/// player is open keeps memory and GPU use flat.
class YouTubePlayerHost {
  YouTubePlayerHost._();

  static final YouTubePlayerHost instance = YouTubePlayerHost._();

  WebviewController controller = WebviewController();
  StreamSubscription<dynamic>? _subscription;
  final StreamController<dynamic> _messages = StreamController<dynamic>.broadcast();
  Future<void>? _ready;
  Future<void> _queue = Future<void>.value();
  bool _suspended = false;

  Stream<dynamic> get messages => _messages.stream;

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
    if (await WebviewController.getWebViewVersion() == null) {
      throw StateError('WebView2 runtime missing');
    }
    await controller.initialize();
    await controller.setBackgroundColor(Colors.black);
    await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
    await controller.addVirtualHostNameMapping(YouTubeWebView.host, folder, WebviewHostResourceAccessKind.allow);
    await controller.addScriptToExecuteOnDocumentCreated(YouTubeWebView.frameScript);
    await controller.setFpsLimit(60);
    _subscription = controller.webMessage.listen(
      _messages.add,
      onError: (Object e) => appLogger.d('YouTube web message: $e'),
    );
  }

  /// Wakes the WebView if needed and loads [url].
  Future<void> open(Uri url) => _serial(() async {
    await ensureReady();
    if (_suspended) {
      await controller.resume();
      _suspended = false;
    }
    await controller.loadUrl(url.toString());
  });

  Future<void> post(String json) async {
    if (_ready == null || _suspended) return;
    await controller.postWebMessage(json);
  }

  /// Throws the WebView away and starts a fresh one on the next [open].
  /// Used when it stopped responding, e.g. after the PC slept or hibernated.
  Future<void> reset() => _serial(() async {
    final old = controller;
    final hadOne = _ready != null;
    await _subscription?.cancel();
    _subscription = null;
    controller = WebviewController();
    _ready = null;
    _suspended = false;
    if (hadOne) {
      try {
        await old.dispose().timeout(const Duration(seconds: 3));
      } catch (e) {
        appLogger.d('YouTube player reset: $e');
      }
    }
  });

  /// Stops playback and suspends the WebView until the next [open].
  Future<void> release() => _serial(() async {
    if (_ready == null) return;
    try {
      await ensureReady();
      await controller.loadUrl('about:blank');
      await controller.suspend();
      _suspended = true;
    } catch (e) {
      appLogger.d('YouTube player release: $e');
    }
  });
}
