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

  /// The browser engine runs (tabs or the ad blocker can be used).
  bool get isReady => _ready != null;
  Map<String, int>? _rect;
  bool _visible = false;

  /// The cache limit the running browser was started with, in MB.
  int? activeCacheLimitMb;

  static const _cacheFolders = {'Cache', 'Code Cache', 'GPUCache', 'Service Worker', 'DawnCache', 'ShaderCache'};

  Future<void> ensureReady({required bool httpsUpgrade, required int cacheLimitMb, required int tracking}) {
    final ready = _ready ??= _init(httpsUpgrade, cacheLimitMb, tracking);
    return ready.catchError((Object e) {
      _ready = null;
      throw e;
    });
  }

  static Future<Directory> _profileDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}browser_webview');
  }

  Future<void> _init(bool httpsUpgrade, int cacheLimitMb, int tracking) async {
    final profile = await _profileDir();
    await profile.create(recursive: true);
    await _channel.invokeMethod<bool>('initialize', {
      'userDataFolder': profile.path,
      'httpsUpgrade': httpsUpgrade,
      'tracking': tracking,
      'arguments': '--disk-cache-size=${cacheLimitMb * 1024 * 1024}',
    });
    activeCacheLimitMb = cacheLimitMb;
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
  Future<void> createTab(int id, String url, {bool private = false}) =>
      _channel.invokeMethod<bool>('createTab', {'id': id, 'url': url, 'private': private});
  Future<void> setMuted(int id, bool value) => _call('setMuted', {'id': id, 'value': value});
  Future<void> setCutouts(List<int> rects) => _call('setCutouts', {'rects': rects});
  Future<void> adblockLoad(String config) => _call('adblockLoad', {'config': config});
  Future<void> adblockSetEnabled(bool value) => _call('adblockSetEnabled', {'value': value});
  Future<void> adblockSetOffSites(List<String> sites) => _call('adblockSetOffSites', {'sites': sites});
  Future<void> proceedBlocked(int id, String url) => _call('proceedBlocked', {'id': id, 'url': url});
  Future<void> setDarkScript(String script) => _call('setDarkScript', {'script': script});
  Future<void> setTrackingPrevention(int level) => _call('setTrackingPrevention', {'level': level});
  Future<void> cancelDownload(int download) => _call('cancelDownload', {'download': download});
  Future<void> pauseDownload(int download) => _call('pauseDownload', {'download': download});
  Future<void> resumeDownload(int download) => _call('resumeDownload', {'download': download});

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
  Future<void> setPopupSites(List<String> sites) => _call('setPopupSites', {'sites': sites});
  Future<void> setHttpsUpgrade(bool value) => _call('setHttpsUpgrade', {'value': value});
  Future<void> answerPermission(int request, bool allow) =>
      _call('answerPermission', {'request': request, 'allow': allow});
  Future<void> answerDownload(int request, bool allow, {String? path}) =>
      _call('answerDownload', {'request': request, 'allow': allow, 'path': ?path});

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
    activeCacheLimitMb = null;
  }

  static Iterable<File> _cacheFiles(List<FileSystemEntity> entities) => entities.whereType<File>().where(
    (f) => f.path.split(Platform.pathSeparator).any(_cacheFolders.contains),
  );

  /// Bytes used by the browser's caches (not its cookies or site sign-ins).
  static Future<int> cacheSize() async {
    final profile = await _profileDir();
    if (!await profile.exists()) return 0;
    var total = 0;
    try {
      final entities = await profile.list(recursive: true, followLinks: false).toList();
      for (final f in _cacheFiles(entities)) {
        try {
          total += await f.length();
        } catch (_) {}
      }
    } catch (e) {
      appLogger.d('Browser cache size: $e');
    }
    return total;
  }

  /// Cookies and what sites store on the PC (logins, site settings).
  static const _siteDataFolders = {
    'Network', 'Cookies', 'Local Storage', 'Session Storage', 'IndexedDB', 'Service Worker', 'File System',
    'WebStorage', 'databases', 'Shared Dictionary', 'blob_storage',
  };

  /// Deletes the cache folders. Only while no browser process uses them.
  static Future<void> deleteCache() => _deleteFolders(_cacheFolders);

  /// Deletes cookies and site data. Only while no browser process uses them.
  static Future<void> deleteSiteData() => _deleteFolders(_siteDataFolders);

  static Future<void> _deleteFolders(Set<String> names) async {
    final profile = await _profileDir();
    if (!await profile.exists()) return;
    final dirs = <Directory>[];
    final files = <File>[];
    await for (final entity in profile.list(recursive: true, followLinks: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!names.contains(name)) continue;
      // Not inside an already listed folder.
      if (dirs.any((d) => entity.path.startsWith('${d.path}${Platform.pathSeparator}'))) continue;
      if (entity is Directory) dirs.add(entity);
      if (entity is File) files.add(entity);
    }
    for (final file in files) {
      try {
        await file.delete();
      } catch (e) {
        appLogger.d('Browser data delete ${file.path}: $e');
      }
    }
    for (final dir in dirs) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (e) {
        appLogger.d('Browser cache delete ${dir.path}: $e');
      }
    }
  }
}
