import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_logger.dart';
import 'browser_history.dart';
import 'browser_native.dart';
import 'browser_settings.dart';

class BrowserTabState {
  BrowserTabState(this.id, {this.url, this.title = ''});

  final int id;

  /// Null while the tab shows the new tab page.
  String? url;
  String title;
  bool loading = false;
  bool canGoBack = false;
  bool canGoForward = false;
  bool audio = false;
  bool fullscreen = false;
  bool crashed = false;

  /// The native WebView exists. Restored tabs get theirs when first shown.
  bool live = false;
  bool suspended = false;
  DateTime lastShown = DateTime.now();

  /// The http address a failed https upgrade came from.
  String? upgradedFrom;

  bool get isSecure => url?.startsWith('https://') ?? true;
  String get host => Uri.tryParse(url ?? '')?.host ?? '';
}

/// Something the browser page asks the user.
sealed class BrowserPrompt {
  const BrowserPrompt(this.tab);
  final int tab;
}

class PermissionPrompt extends BrowserPrompt {
  const PermissionPrompt(super.tab, this.request, this.kind, this.url);
  final int request;
  final int kind;
  final String url;
}

class DownloadPrompt extends BrowserPrompt {
  const DownloadPrompt(super.tab, this.request, this.url, this.path, this.size);
  final int request;
  final String url;
  final String path;
  final int size;
}

class PopupBlockedNotice extends BrowserPrompt {
  const PopupBlockedNotice(super.tab, this.url, this.site, {this.redirect = false});
  final String url;

  /// The site that tried to open it.
  final String site;

  /// The page tried to leave for [url] right after opening a pop-up.
  final bool redirect;
}

class HttpFallbackNotice extends BrowserPrompt {
  const HttpFallbackNotice(super.tab, this.httpUrl);
  final String httpUrl;
}

class BlockedSchemeNotice extends BrowserPrompt {
  const BlockedSchemeNotice(super.tab, this.url);
  final String url;
}

class CrashedNotice extends BrowserPrompt {
  const CrashedNotice(super.tab);
}

/// Tabs of the in-app browser. Only the shown tab runs; the others are
/// suspended after [BrowserSettings.suspendMinutes], unless they play audio.
class BrowserController extends ChangeNotifier with WidgetsBindingObserver {
  BrowserController._() {
    _native.events.listen(_onEvent);
    WidgetsBinding.instance.addObserver(this);
  }

  static final BrowserController instance = BrowserController._();

  static const _tabsKey = 'browser.tabs';

  /// After the browser was closed this long, its WebViews are released
  /// completely. The tabs stay and load again when shown.
  static const releaseAfter = Duration(minutes: 30);

  final _native = BrowserNative.instance;
  final _settings = BrowserSettings.instance;
  final List<BrowserTabState> tabs = [];
  final StreamController<BrowserPrompt> _prompts = StreamController<BrowserPrompt>.broadcast();
  final StreamController<String> _shortcuts = StreamController<String>.broadcast();

  Stream<BrowserPrompt> get prompts => _prompts.stream;

  /// Ctrl+T, Ctrl+W, Ctrl+L, Ctrl+Tab, Alt+arrows pressed inside a page.
  Stream<String> get shortcuts => _shortcuts.stream;

  int _nextId = 1;
  int? _activeId;
  bool _shown = false;
  bool _loaded = false;
  Timer? _sweep;
  Timer? _release;
  Timer? _saveTimer;
  DateTime? _hiddenSince;

  BrowserTabState? get active => _byId(_activeId);

  BrowserTabState? _byId(int? id) {
    if (id == null) return null;
    for (final t in tabs) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await _settings.load();
    await BrowserHistory.instance.load();
    if (_settings.restoreTabs) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = jsonDecode(prefs.getString(_tabsKey) ?? '{}');
        if (saved is Map && saved['tabs'] is List) {
          for (final entry in saved['tabs'] as List) {
            if (entry is! Map) continue;
            final url = entry['url'];
            tabs.add(
              BrowserTabState(
                _nextId++,
                url: url is String && url.isNotEmpty ? url : null,
                title: entry['title'] is String ? entry['title'] as String : '',
              ),
            );
          }
          final index = saved['active'];
          if (index is int && index >= 0 && index < tabs.length) _activeId = tabs[index].id;
        }
      } catch (e) {
        appLogger.d('Browser tabs restore: $e');
      }
    }
    if (tabs.isEmpty) tabs.add(BrowserTabState(_nextId++, url: _homeUrl()));
    _activeId ??= tabs.first.id;
    notifyListeners();
  }

  String? _homeUrl() {
    if (_settings.newTabPage != BrowserNewTabPage.custom) return null;
    return resolveInput(_settings.customNewTab);
  }

  /// Whether the browser page is on screen. Hidden, every tab counts as not
  /// shown and suspends on schedule.
  Future<void> setShown(bool shown) async {
    if (_shown == shown) return;
    _shown = shown;
    if (shown) {
      _hiddenSince = null;
      _release?.cancel();
      _sweep ??= Timer.periodic(const Duration(seconds: 30), (_) => _suspendIdle());
      final tab = active;
      if (tab != null) await _show(tab);
    } else {
      _hiddenSince = DateTime.now();
      active?.lastShown = DateTime.now();
      _release?.cancel();
      _release = Timer(releaseAfter, _releaseAll);
    }
    await _native.setVisible(shown && (active?.live ?? false));
    notifyListeners();
  }

  /// Creates or wakes the WebView of [tab] and makes it the shown one.
  Future<void> _show(BrowserTabState tab) async {
    tab.lastShown = DateTime.now();
    final url = tab.url;
    if (url == null) {
      await _native.setVisible(false);
      return;
    }
    try {
      await _native.ensureReady(httpsUpgrade: _settings.httpsUpgrade, cacheLimitMb: _settings.cacheLimitMb);
      await _native.setPopupSites(_settings.popupSites);
      if (!tab.live) {
        tab.live = true;
        tab.loading = true;
        notifyListeners();
        await _native.createTab(tab.id, url);
      } else if (tab.suspended) {
        await _native.resume(tab.id);
      }
      tab.suspended = false;
      if (_activeId != tab.id) return;
      await _native.setActive(tab.id);
      await _native.setVisible(_shown);
    } catch (e) {
      appLogger.w('Browser tab ${tab.id} could not start', error: e);
      tab.live = false;
      tab.loading = false;
      tab.crashed = true;
      notifyListeners();
    }
  }

  Future<void> select(int id) async {
    final tab = _byId(id);
    if (tab == null) return;
    active?.lastShown = DateTime.now();
    _activeId = id;
    notifyListeners();
    _scheduleSave();
    if (_shown) await _show(tab);
  }

  Future<void> selectRelative(int delta) async {
    if (tabs.length < 2) return;
    final index = tabs.indexWhere((t) => t.id == _activeId);
    await select(tabs[(index + delta) % tabs.length].id);
  }

  /// Opens a new tab next to the shown one, with [url] or the new tab page.
  Future<void> newTab({String? url, bool background = false}) async {
    final tab = BrowserTabState(_nextId++, url: url ?? _homeUrl());
    final index = tabs.indexWhere((t) => t.id == _activeId);
    tabs.insert(index < 0 ? tabs.length : index + 1, tab);
    if (background) {
      tab.lastShown = DateTime.now();
      notifyListeners();
      _scheduleSave();
      return;
    }
    await select(tab.id);
  }

  Future<void> close(int id) async {
    final index = tabs.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final tab = tabs.removeAt(index);
    if (tab.live) await _native.closeTab(id);
    if (tabs.isEmpty) tabs.add(BrowserTabState(_nextId++, url: _homeUrl()));
    if (_activeId == id) {
      _activeId = null;
      await select(tabs[index.clamp(0, tabs.length - 1)].id);
    } else {
      notifyListeners();
      _scheduleSave();
    }
  }

  /// Opens what was typed in the address bar: an address or a search.
  Future<void> go(String input, {BrowserTabState? tab, bool allowHttp = false}) async {
    final target = tab ?? active;
    final url = allowHttp ? input : resolveInput(input);
    if (target == null || url == null) return;
    target.crashed = false;
    if (!target.live) {
      target.url = url;
      target.title = '';
      notifyListeners();
      if (target.id == _activeId && _shown) await _show(target);
      return;
    }
    target.loading = true;
    notifyListeners();
    await _native.navigate(target.id, url, allowHttp: allowHttp);
  }

  Future<void> back() async {
    final tab = active;
    if (tab != null && tab.live) await _native.back(tab.id);
  }

  Future<void> forward() async {
    final tab = active;
    if (tab != null && tab.live) await _native.forward(tab.id);
  }

  Future<void> reload() async {
    final tab = active;
    if (tab == null || tab.url == null) return;
    if (tab.crashed || !tab.live) {
      if (tab.live) await _native.closeTab(tab.id);
      tab
        ..live = false
        ..crashed = false;
      await _show(tab);
      return;
    }
    await _native.reload(tab.id);
  }

  Future<void> stop() async {
    final tab = active;
    if (tab != null && tab.live) await _native.stop(tab.id);
  }

  Future<void> focusPage() async {
    final tab = active;
    if (tab != null && tab.live) await _native.focus(tab.id);
  }

  Future<void> setHttpsUpgrade(bool value) => _native.setHttpsUpgrade(value);

  /// Allows or blocks pop-ups from [site] from now on.
  Future<void> setPopupAllowed(String site, bool allowed) async {
    await _settings.setPopupAllowed(site, allowed);
    await _native.setPopupSites(_settings.popupSites);
  }

  /// Where the page goes, in physical pixels of the Flutter view.
  Future<void> setPageRect({required int left, required int top, required int right, required int bottom}) =>
      _native.setRect(left: left, top: top, right: right, bottom: bottom);

  Future<void> answerPermission(int request, bool allow) => _native.answerPermission(request, allow);
  Future<void> answerDownload(int request, bool allow) => _native.answerDownload(request, allow);

  void _onEvent(BrowserEvent e) {
    final tab = _byId(e.tab);
    if (tab == null) return;
    switch (e.type) {
      case 'state':
        final url = e.str('url');
        if (url != null && url.isNotEmpty) tab.url = url;
        tab
          ..title = e.str('title') ?? tab.title
          ..canGoBack = e.flag('canGoBack')
          ..canGoForward = e.flag('canGoForward');
        // Also catches pages that change their address without loading.
        if (!tab.loading && tab.url != null) BrowserHistory.instance.visit(tab.url!, tab.title);
        _scheduleSave();
      case 'loading':
        tab.loading = true;
        final url = e.str('url');
        if (url != null && url.isNotEmpty) tab.url = url;
      case 'loaded':
        tab.loading = false;
        // 14 = cancelled, e.g. the http load the https upgrade replaced.
        if (e.integer('error') == 14 && !e.flag('ok')) break;
        final from = tab.upgradedFrom;
        tab.upgradedFrom = null;
        if (!e.flag('ok') && from != null) _prompts.add(HttpFallbackNotice(tab.id, from));
        if (e.flag('ok') && tab.url != null) BrowserHistory.instance.visit(tab.url!, tab.title);
      case 'upgraded':
        tab.upgradedFrom = e.str('url');
      case 'blockedScheme':
        _prompts.add(BlockedSchemeNotice(tab.id, e.str('url') ?? ''));
      case 'openTab':
        final url = e.str('url');
        if (url != null && url.isNotEmpty) unawaited(newTab(url: url));
      case 'popupBlocked':
        final url = e.str('url');
        if (url != null && url.isNotEmpty) {
          _prompts.add(PopupBlockedNotice(tab.id, url, e.str('site') ?? '', redirect: e.flag('redirect')));
        }
      // Nobody to ask while the browser is closed: denied.
      case 'permission':
        if (_prompts.hasListener) {
          _prompts.add(PermissionPrompt(tab.id, e.integer('request'), e.integer('kind'), e.str('url') ?? ''));
        } else {
          unawaited(answerPermission(e.integer('request'), false));
        }
      case 'download':
        if (_prompts.hasListener) {
          _prompts.add(
            DownloadPrompt(tab.id, e.integer('request'), e.str('url') ?? '', e.str('path') ?? '', e.integer('size')),
          );
        } else {
          unawaited(answerDownload(e.integer('request'), false));
        }
      case 'fullscreen':
        tab.fullscreen = e.flag('value');
      case 'audio':
        tab.audio = e.flag('value');
      case 'crashed':
        tab
          ..crashed = true
          ..loading = false;
        _prompts.add(CrashedNotice(tab.id));
      case 'shortcut':
        final key = e.str('key');
        if (key != null) _shortcuts.add(key);
    }
    notifyListeners();
  }

  /// Suspends tabs not shown for [BrowserSettings.suspendMinutes].
  void _suspendIdle({bool all = false}) {
    final minutes = _settings.suspendMinutes;
    if (minutes <= 0 && !all) return;
    final now = DateTime.now();
    for (final tab in tabs) {
      if (!tab.live || tab.suspended) continue;
      final isShown = _shown && tab.id == _activeId;
      if (isShown) continue;
      if (_settings.keepPlayingAwake && tab.audio) continue;
      if (!all && now.difference(tab.lastShown).inMinutes < minutes) continue;
      tab.suspended = true;
      unawaited(_native.suspend(tab.id));
      appLogger.d('Browser: suspended tab ${tab.id}');
    }
  }

  @override
  void didHaveMemoryPressure() {
    if (tabs.any((t) => t.live)) _suspendIdle(all: true);
  }

  Future<void> _releaseAll() async {
    final since = _hiddenSince;
    if (_shown || since == null) return;
    if (tabs.any((t) => t.live && t.audio && _settings.keepPlayingAwake)) {
      _release = Timer(releaseAfter, _releaseAll);
      return;
    }
    await _closeEngine();
    appLogger.d('Browser: released after ${releaseAfter.inMinutes} minutes closed');
  }

  /// Ends every WebView and the browser processes; tabs load again when shown.
  Future<void> _closeEngine() async {
    _sweep?.cancel();
    _sweep = null;
    for (final tab in tabs) {
      tab
        ..live = false
        ..suspended = false
        ..loading = false;
    }
    await _native.dispose();
  }

  /// Clears the disk cache and keeps cookies and site sign-ins. Open tabs
  /// load again; a new cache limit applies from now on.
  Future<void> clearCache() async {
    await _closeEngine();
    // Let the browser processes exit and release their files.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await BrowserNative.deleteCache();
    if (_shown) {
      _sweep ??= Timer.periodic(const Duration(seconds: 30), (_) => _suspendIdle());
      final tab = active;
      if (tab != null) await _show(tab);
    }
    notifyListeners();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () => unawaited(_save()));
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = tabs.indexWhere((t) => t.id == _activeId);
      await prefs.setString(
        _tabsKey,
        jsonEncode({
          'active': index,
          'tabs': [
            for (final t in tabs) {'url': t.url ?? '', 'title': t.title},
          ],
        }),
      );
    } catch (e) {
      appLogger.d('Browser tabs save: $e');
    }
  }

  /// Turns address bar input into an address, searching when it isn't one.
  String? resolveInput(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('about:')) return text;
    if (!text.contains(' ')) {
      final uri = Uri.tryParse('http://$text');
      final host = uri?.host ?? '';
      if (host.isNotEmpty) {
        if (_isLocal(host) && (host.contains('.') || host == 'localhost' || uri!.hasPort)) return 'http://$text';
        if (host.contains('.') && RegExp(r'\.[a-z]{2,}$|\.xn--[a-z0-9-]+$').hasMatch(host.toLowerCase())) {
          return 'https://$text';
        }
      }
    }
    return _settings.searchUrl(text);
  }

  static bool _isLocal(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || !h.contains('.')) return true;
    if (h.endsWith('.local') || h.endsWith('.lan') || h.endsWith('.home.arpa')) return true;
    final parts = h.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null)) return false;
    final a = parts[0]!;
    final b = parts[1]!;
    return a == 10 || a == 127 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31) || (a == 169 && b == 254);
  }
}
