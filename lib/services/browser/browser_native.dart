import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../utils/app_logger.dart';

/// One event from a native browser tab (windows/runner/browser).
class BrowserEvent {
  BrowserEvent(this.type, this.tab, this.data);

  final String type;
  final int tab;
  final Map<Object?, Object?> data;

  String? str(String key) => data[key] as String?;
  bool flag(String key) => data[key] == true;
  int integer(String key) => (data[key] as num?)?.toInt() ?? 0;
}

/// The in-app browser's WebView2 tabs, hosted natively as child windows of
/// the Flutter view. Each tab has its own WebView; only the active one is
/// shown. The browser uses its own profile, separate from YouTube's.
class BrowserNative {
  BrowserNative._() {
    _events.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        final type = event['type'];
        final tab = event['tab'];
        if (type is! String || tab is! int) return;
        _stream.add(BrowserEvent(type, tab, event));
      },
      onError: (Object e) => appLogger.d('Browser event: $e'),
    );
  }

  static final BrowserNative instance = BrowserNative._();

  static bool get isSupported => Platform.isWindows;

  static const MethodChannel _channel = MethodChannel('com.plezy.retrowave/browser');
  static const EventChannel _events = EventChannel('com.plezy.retrowave/browser/events');

  final StreamController<BrowserEvent> _stream = StreamController<BrowserEvent>.broadcast();
  Stream<BrowserEvent> get events => _stream.stream;

  Future<void>? _ready;
  Map<String, int>? _rect;
  bool _visible = false;

  Future<void> ensureReady({required bool httpsUpgrade}) {
    final ready = _ready ??= _init(httpsUpgrade);
    return ready.catchError((Object e) {
      _ready = null;
      throw e;
    });
  }

  Future<void> _init(bool httpsUpgrade) async {
    final support = await getApplicationSupportDirectory();
    final profile = Directory('${support.path}${Platform.pathSeparator}browser_webview');
    await profile.create(recursive: true);
    await _channel.invokeMethod<bool>('initialize', {'userDataFolder': profile.path, 'httpsUpgrade': httpsUpgrade});
    final rect = _rect;
    if (rect != null) await _channel.invokeMethod<void>('setRect', rect);
    await _channel.invokeMethod<void>('setVisible', {'visible': _visible});
  }

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    if (_ready == null) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      appLogger.d('Browser $method: $e');
    }
  }

  /// Creates the WebView for tab [id] and loads [url]. Throws when WebView2
  /// could not start.
  Future<void> createTab(int id, String url) => _channel.invokeMethod<bool>('createTab', {'id': id, 'url': url});

  Future<void> closeTab(int id) => _call('closeTab', {'id': id});
  Future<void> navigate(int id, String url, {bool allowHttp = false}) =>
      _call('navigate', {'id': id, 'url': url, 'allowHttp': allowHttp});
  Future<void> back(int id) => _call('back', {'id': id});
  Future<void> forward(int id) => _call('forward', {'id': id});
  Future<void> reload(int id) => _call('reload', {'id': id});
  Future<void> stop(int id) => _call('stop', {'id': id});
  Future<void> focus(int id) => _call('focus', {'id': id});
  Future<void> suspend(int id) => _call('suspend', {'id': id});
  Future<void> resume(int id) => _call('resume', {'id': id});
  Future<void> setActive(int id) => _call('setActive', {'id': id});
  Future<void> setHttpsUpgrade(bool value) => _call('setHttpsUpgrade', {'value': value});
  Future<void> answerPermission(int request, bool allow) =>
      _call('answerPermission', {'request': request, 'allow': allow});
  Future<void> answerDownload(int request, bool allow) => _call('answerDownload', {'request': request, 'allow': allow});

  /// Places the tabs, in physical pixels of the Flutter view.
  Future<void> setRect({required int left, required int top, required int right, required int bottom}) {
    final rect = {'left': left, 'top': top, 'right': right, 'bottom': bottom};
    _rect = rect;
    return _call('setRect', rect);
  }

  Future<void> setVisible(bool visible) {
    if (_visible == visible) return Future<void>.value();
    _visible = visible;
    return _call('setVisible', {'visible': visible});
  }

  /// Closes every tab and the browser processes.
  Future<void> dispose() async {
    await _call('dispose');
    _ready = null;
  }
}
