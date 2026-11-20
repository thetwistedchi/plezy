import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_logger.dart';
import '../fullscreen_state_manager.dart';
import 'adblock_lists.dart';
import 'browser_history.dart';
import 'browser_native.dart';
import 'browser_settings.dart';

class BrowserTabState {
  BrowserTabState(this.id, {this.url, this.title = '', this.isPrivate = false});

  final int id;

  /// InPrivate: no cookies, history or saved tab once it closes.
  final bool isPrivate;
  bool muted = false;

  /// Requests the ad blocker stopped on the current page.
  int blockedCount = 0;

  /// A page the ad blocker kept from opening (on a filter list).
  String? blockedPage;

  /// The site's icon as PNG, when it has one.
  Uint8List? favicon;

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

  /// One of the app's own pages (settings, filter lists), shown by Flutter.
  bool get isInternal => url?.startsWith('plezy://') ?? false;

  bool get isSecure => url?.startsWith('https://') ?? true;
  String get host => Uri.tryParse(url ?? '')?.host ?? '';
}

enum BrowserDownloadState { running, paused, completed, failed }

class BrowserDownload {
  BrowserDownload(this.id, {required this.url, required this.path});

  final int id;
  String url;
  String path;
  int received = 0;
  int total = 0;
  BrowserDownloadState state = BrowserDownloadState.running;

  String get fileName => path.split(RegExp(r'[\\/]')).last;
  double? get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
  bool get active => state == BrowserDownloadState.running || state == BrowserDownloadState.paused;
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

  String get site => Uri.tryParse(url)?.host ?? url;
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

class UnresponsiveNotice extends BrowserPrompt {
  const UnresponsiveNotice(super.tab);
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

  final StreamController<void> _pageFocus = StreamController<void>.broadcast();

  /// The user clicked into the page (it took the keyboard focus).
  Stream<void> get pageFocused => _pageFocus.stream;

  final Map<int, (Rect, double)> _cutouts = {};
  bool _cutoutsQueued = false;

  /// Marks where Flutter content (a popup) lies over the page, in physical
  /// pixels; null removes it. The page gets a hole there, so the popup takes
  /// the clicks while the page stays visible around it.
  void setCutout(int id, Rect? rect, {double radius = 0}) {
    if (rect == null) {
      if (_cutouts.remove(id) == null) return;
    } else {
      if (_cutouts[id] == (rect, radius)) return;
      _cutouts[id] = (rect, radius);
    }
    if (_cutoutsQueued) return;
    _cutoutsQueued = true;
    scheduleMicrotask(() {
      _cutoutsQueued = false;
      unawaited(
        _native.setCutouts([
          for (final (r, radius) in _cutouts.values)
            ...[r.left.floor(), r.top.floor(), r.right.ceil(), r.bottom.ceil(), radius.round()],
        ]),
      );
    });
  }

  /// Ctrl+T, Ctrl+W, Ctrl+L, Ctrl+Tab, Alt+arrows pressed inside a page.
  Stream<String> get shortcuts => _shortcuts.stream;

  /// Downloads of this session, newest first.
  final List<BrowserDownload> downloads = [];

  /// Recently closed tabs (addresses), newest last.
  final List<String> _closed = [];
  bool get canReopen => _closed.isNotEmpty;

  bool _ownsFullscreen = false;

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
    // "Delete cookies when the app closes": done at the next start, before
    // the browser engine runs.
    if (_settings.clearSiteDataOnExit) {
      await BrowserNative.deleteSiteData();
      appLogger.d('Browser: cookies and site data cleared at start');
    }
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
    appLogger.d('Browser: ${shown ? 'shown' : 'hidden'} (${tabs.length} tabs, ${tabs.where((t) => t.live).length} running)');
    if (shown) {
      _hiddenSince = null;
      _release?.cancel();
      _sweep ??= Timer.periodic(const Duration(seconds: 30), (_) => _suspendIdle());
      final tab = active;
      if (tab != null) await _show(tab);
    } else {
      _hiddenSince = DateTime.now();
      active?.lastShown = DateTime.now();
      if (_ownsFullscreen) unawaited(_syncFullscreen(false));
      _release?.cancel();
      _release = Timer(releaseAfter, _releaseAll);
    }
    await _applyVisibility();
    notifyListeners();
  }

  /// The native page shows only for a live tab without a blocked-page warning.
  Future<void> _applyVisibility() {
    final tab = active;
    return _native.setVisible(
      _shown && tab != null && tab.live && tab.url != null && !tab.isInternal && tab.blockedPage == null,
    );
  }

  static const settingsPage = 'plezy://settings';
  static const filtersPage = 'plezy://filters';
  static const historyPage = 'plezy://history';

  /// Shows one of the app's own pages in a tab, reusing an open one.
  Future<void> openInternal(String page) async {
    final open = tabs.where((t) => t.url == page).firstOrNull;
    if (open != null) return select(open.id);
    final current = active;
    // An empty new tab is used instead of opening another one.
    if (current != null && current.url == null && !current.isPrivate) {
      current.url = page;
      notifyListeners();
      await _applyVisibility();
      return;
    }
    await newTab(url: page);
  }

  /// Opens the page the ad blocker kept closed, once, in [tab].
  Future<void> proceedBlocked(BrowserTabState tab) async {
    final url = tab.blockedPage;
    if (url == null) return;
    tab.blockedPage = null;
    notifyListeners();
    if (tab.live) await _native.proceedBlocked(tab.id, url);
    await _applyVisibility();
  }

  /// Leaves the warning: back to the page before, or the new tab page.
  Future<void> leaveBlocked(BrowserTabState tab) async {
    tab.blockedPage = null;
    if (!tab.canGoBack) tab.url = null;
    notifyListeners();
    await _applyVisibility();
  }

  /// Creates or wakes the WebView of [tab] and makes it the shown one.
  Future<void> _show(BrowserTabState tab) async {
    tab.lastShown = DateTime.now();
    final url = tab.url;
    if (url == null || tab.isInternal) {
      await _native.setVisible(false);
      return;
    }
    try {
      final started = DateTime.now();
      final fresh = _native.activeCacheLimitMb == null;
      await _native.ensureReady(
        httpsUpgrade: _settings.httpsUpgrade,
        cacheLimitMb: _settings.cacheLimitMb,
        tracking: _settings.trackingLevel,
      );
      if (fresh) {
        appLogger.i(
          'Browser: engine started in ${DateTime.now().difference(started).inMilliseconds} ms '
          '(cache limit ${_settings.cacheLimitMb} MB)',
        );
      }
      await _native.setPopupSites(_settings.popupSites);
      if (fresh) {
        await _syncDark();
        unawaited(AdblockManager.instance.start());
      }
      if (!tab.live) {
        tab.live = true;
        tab.loading = true;
        notifyListeners();
        final created = DateTime.now();
        await _native.createTab(tab.id, url, private: tab.isPrivate);
        if (tab.muted) await _native.setMuted(tab.id, true);
        appLogger.d('Browser tab ${tab.id}: created in ${DateTime.now().difference(created).inMilliseconds} ms');
      } else if (tab.suspended) {
        appLogger.d('Browser tab ${tab.id}: resumed');
        await _native.resume(tab.id);
      }
      tab.suspended = false;
      if (_activeId != tab.id) return;
      await _native.setActive(tab.id);
      await _applyVisibility();
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
  Future<void> newTab({String? url, bool background = false, bool private = false}) async {
    final tab = BrowserTabState(_nextId++, url: url ?? _homeUrl(), isPrivate: private);
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
    final closedUrl = tab.url;
    if (!tab.isPrivate && closedUrl != null) {
      _closed.add(closedUrl);
      if (_closed.length > 20) _closed.removeAt(0);
    }
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

  Future<void> reopenClosed() async {
    if (_closed.isEmpty) return;
    await newTab(url: _closed.removeLast());
  }

  Future<void> duplicate(int id) async {
    final tab = _byId(id);
    if (tab == null) return;
    await newTab(url: tab.url, private: tab.isPrivate);
  }

  Future<void> closeOthers(int id) async {
    for (final tab in [...tabs]) {
      if (tab.id != id) await close(tab.id);
    }
  }

  Future<void> setMuted(int id, bool muted) async {
    final tab = _byId(id);
    if (tab == null) return;
    tab.muted = muted;
    notifyListeners();
    if (tab.live) await _native.setMuted(id, muted);
  }

  String? _darkLibrary;

  /// Dark mode for websites: Dark Reader runs in every page unless the site
  /// is excluded. Kept out of the page's view (no global DarkReader).
  Future<String> _darkScript() async {
    if (!_settings.darkMode) return '';
    final lib = _darkLibrary ??= await rootBundle.loadString('assets/browser/darkreader.min.js');
    final excluded = jsonEncode(_settings.darkExcluded);
    return '(()=>{try{if(window.__plezyDark){window.__plezyDark.disable();}}catch(e){}'
        'const h=location.hostname.replace(/^www\\./,"");'
        'if($excluded.some(s=>h===s||h.endsWith("."+s)))return;'
        'var exports={},module={exports:{}},define=undefined;\n'
        '$lib\n'
        ';const D=exports;try{D.setFetchMethod(window.fetch.bind(window));}catch(e){}'
        'D.enable({brightness:${_settings.darkBrightness},contrast:${_settings.darkContrast},sepia:0});'
        'try{Object.defineProperty(window,"__plezyDark",{value:D,configurable:true});}catch(e){}'
        '})();';
  }

  Future<void> _syncDark() async {
    try {
      await _native.setDarkScript(await _darkScript());
    } catch (e) {
      appLogger.w('Browser dark mode', error: e);
    }
  }

  /// Applies changed dark mode settings to open and new pages.
  Future<void> setDarkMode({bool? enabled, int? brightness, int? contrast}) async {
    await _settings.update(darkMode: enabled, darkBrightness: brightness, darkContrast: contrast);
    await _syncDark();
  }

  Future<void> setDarkExcluded(String site, bool excluded) async {
    await _settings.setDarkExcluded(site, excluded);
    await _syncDark();
  }

  Future<void> setTrackingLevel(int level) async {
    await _settings.update(trackingLevel: level);
    await _native.setTrackingPrevention(level);
  }

  /// Deletes cookies and site data; signs out of every website.
  Future<void> clearSiteData() async {
    await _closeEngine();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await BrowserNative.deleteSiteData();
    if (_shown) {
      _sweep ??= Timer.periodic(const Duration(seconds: 30), (_) => _suspendIdle());
      final tab = active;
      if (tab != null) await _show(tab);
    }
    notifyListeners();
  }

  bool get hasActiveDownloads => downloads.any((d) => d.active);

  Future<void> cancelDownload(int id) => _native.cancelDownload(id);
  Future<void> pauseDownload(int id) => _native.pauseDownload(id);
  Future<void> resumeDownload(int id) => _native.resumeDownload(id);

  void clearFinishedDownloads() {
    downloads.removeWhere((d) => !d.active);
    notifyListeners();
  }

  /// Opens what was typed in the address bar: an address or a search.
  Future<void> go(String input, {BrowserTabState? tab, bool allowHttp = false}) async {
    final target = tab ?? active;
    final url = allowHttp ? input : resolveInput(input);
    if (target == null || url == null) return;
    target
      ..crashed = false
      ..blockedPage = null;
    if (url.startsWith('plezy://')) {
      target.url = url;
      notifyListeners();
      await _applyVisibility();
      return;
    }
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
    await _applyVisibility();
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
  Future<void> answerDownload(int request, bool allow, {String? path}) =>
      _native.answerDownload(request, allow, path: path);

  /// Only the host goes into the log, not the full address.
  static String _host(String? url) => Uri.tryParse(url ?? '')?.host ?? '';

  void _log(BrowserEvent e) {
    final t = 'Browser tab ${e.tab}';
    switch (e.type) {
      case 'loading':
        appLogger.d('$t: loading ${_host(e.str('url'))}');
      case 'loaded':
        if (e.flag('ok')) {
          appLogger.d('$t: loaded');
        } else if (e.integer('error') != 14) {
          appLogger.i('$t: load failed (WebView2 error ${e.integer('error')})');
        }
      case 'upgraded':
        appLogger.d('$t: upgraded ${_host(e.str('url'))} to https');
      case 'blockedScheme':
        appLogger.i('$t: blocked a local file or script address');
      case 'openTab':
        appLogger.d('$t: opens ${_host(e.str('url'))} in a new tab');
      case 'popupBlocked':
        appLogger.i(
          '$t: ${e.flag('redirect') ? 'tab-under' : 'pop-up'} from ${e.str('site')} to ${_host(e.str('url'))} blocked',
        );
      case 'permission':
        appLogger.d('$t: permission ${e.integer('kind')} requested by ${_host(e.str('url'))}');
      case 'download':
        final name = (e.str('path') ?? '').split(RegExp(r'[\\/]')).last;
        final ext = name.contains('.') ? name.split('.').last : '?';
        appLogger.d('$t: download requested (.$ext, ${e.integer('size')} bytes)');
      case 'adblockStats':
        final ms = (e.data['ms'] as num?)?.toDouble() ?? 0;
        appLogger.d(
          '$t: ad blocker checked ${e.integer('checked')} requests, blocked ${e.integer('blocked')}, '
          'checking took ${ms.toStringAsFixed(1)} ms',
        );
      case 'crashed':
        appLogger.w(
          '$t: WebView2 process failed: ${_failKind(e.integer('kind'))}, reason ${e.integer('reason')}, '
          'exit code ${e.integer('exitCode')}',
        );
      case 'fullscreen':
        appLogger.d('$t: fullscreen ${e.flag('value')}');
    }
  }

  static String _failKind(int kind) => switch (kind) {
    0 => 'browser process exited',
    1 => 'page process exited',
    2 => 'page not responding',
    3 => 'frame process exited',
    4 => 'utility process exited',
    5 => 'sandbox helper exited',
    6 => 'GPU process exited',
    _ => 'kind $kind',
  };

  void _onEvent(BrowserEvent e) {
    if (e.type == 'pageFocus') {
      _pageFocus.add(null);
      return;
    }
    if (e.type == 'downloadState') {
      // Also for downloads of tabs that have closed since.
      _onDownload(e);
      notifyListeners();
      return;
    }
    if (e.type == 'adblockReady') {
      AdblockManager.instance.onReady(e.flag('ok'), e.integer('ms'));
      return;
    }
    final tab = _byId(e.tab);
    if (tab == null) return;
    _log(e);
    switch (e.type) {
      case 'state':
        final url = e.str('url');
        if (url != null && url.isNotEmpty) tab.url = url;
        tab
          ..title = e.str('title') ?? tab.title
          ..canGoBack = e.flag('canGoBack')
          ..canGoForward = e.flag('canGoForward');
        // Also catches pages that change their address without loading.
        if (!tab.isPrivate && !tab.loading && tab.url != null) BrowserHistory.instance.visit(tab.url!, tab.title);
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
        if (!tab.isPrivate && e.flag('ok') && tab.url != null) BrowserHistory.instance.visit(tab.url!, tab.title);
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
        final site = Uri.tryParse(e.str('url') ?? '')?.host ?? '';
        final remembered = tab.isPrivate ? null : _settings.permissionFor(site, e.integer('kind'));
        if (remembered != null) {
          unawaited(answerPermission(e.integer('request'), remembered));
        } else if (_prompts.hasListener) {
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
        unawaited(_syncFullscreen(tab.fullscreen));
      case 'favicon':
        final data = e.data['data'];
        tab.favicon = data is Uint8List && data.isNotEmpty ? data : null;
      case 'blocked':
        tab.blockedCount = e.integer('count');
      case 'pageBlocked':
        tab
          ..blockedPage = e.str('url')
          ..loading = false;
        appLogger.i('Browser tab ${tab.id}: page on a filter list kept closed (${_host(e.str('url'))})');
        unawaited(_applyVisibility());
      case 'audio':
        tab.audio = e.flag('value');
      case 'crashed':
        switch (e.integer('kind')) {
          // The page's own process ended: the tab shows the reload page.
          case 1:
            tab
              ..crashed = true
              ..loading = false;
            _prompts.add(CrashedNotice(tab.id));
          // The page hangs: it may still recover, so the user decides.
          case 2:
            _prompts.add(UnresponsiveNotice(tab.id));
          // The whole browser ended: every tab starts again when shown.
          case 0:
            for (final t in tabs) {
              t
                ..live = false
                ..suspended = false
                ..loading = false;
            }
            unawaited(_native.dispose().then((_) async {
              final shown = active;
              if (_shown && shown != null) await _show(shown);
            }));
          // A frame (often an ad), the GPU or a helper process: Chromium
          // restarts these itself and the page keeps working.
          default:
            break;
        }
      case 'shortcut':
        final key = e.str('key');
        if (key != null) _shortcuts.add(key);
    }
    notifyListeners();
  }

  void _onDownload(BrowserEvent e) {
    final id = e.integer('download');
    var d = downloads.where((x) => x.id == id).firstOrNull;
    if (d == null) {
      d = BrowserDownload(id, url: e.str('url') ?? '', path: e.str('path') ?? '');
      downloads.insert(0, d);
    }
    d
      ..received = e.integer('received')
      ..total = e.integer('total')
      ..path = e.str('path') ?? d.path
      ..state = switch (e.str('state')) {
        'completed' => BrowserDownloadState.completed,
        'paused' => BrowserDownloadState.paused,
        'failed' => BrowserDownloadState.failed,
        _ => BrowserDownloadState.running,
      };
    if (d.state == BrowserDownloadState.completed || d.state == BrowserDownloadState.failed) {
      appLogger.d('Browser download $id: ${d.state.name}');
    }
  }

  /// Video fullscreen in a page makes the app window fullscreen too, and
  /// leaving it restores the window, unless the app was fullscreen before.
  Future<void> _syncFullscreen(bool value) async {
    final manager = FullscreenStateManager();
    if (value && !manager.isFullscreen) {
      _ownsFullscreen = true;
      await manager.enterFullscreen();
    } else if (!value && _ownsFullscreen) {
      _ownsFullscreen = false;
      await manager.exitFullscreen();
    }
  }

  /// Suspends tabs not shown for [BrowserSettings.suspendMinutes].
  void _suspendIdle({bool all = false}) {
    final minutes = _settings.suspendMinutes;
    if (minutes <= 0 && !all) return;
    final now = DateTime.now();
    var changed = false;
    for (final tab in tabs) {
      if (!tab.live || tab.suspended) continue;
      final isShown = _shown && tab.id == _activeId;
      if (isShown) continue;
      if (_settings.keepPlayingAwake && tab.audio) continue;
      if (!all && now.difference(tab.lastShown).inMinutes < minutes) continue;
      tab.suspended = true;
      changed = true;
      unawaited(_native.suspend(tab.id));
      appLogger.d('Browser: suspended tab ${tab.id}');
    }
    if (changed) notifyListeners();
  }

  @override
  void didHaveMemoryPressure() {
    if (tabs.any((t) => t.live)) _suspendIdle(all: true);
  }

  Future<void> _releaseAll() async {
    final since = _hiddenSince;
    if (_shown || since == null) return;
    if (hasActiveDownloads || tabs.any((t) => t.live && t.audio && _settings.keepPlayingAwake)) {
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
      final index = tabs.where((t) => !t.isPrivate && !t.isInternal).toList().indexWhere((t) => t.id == _activeId);
      await prefs.setString(
        _tabsKey,
        jsonEncode({
          'active': index,
          'tabs': [
            for (final t in tabs.where((t) => !t.isPrivate && !t.isInternal)) {'url': t.url ?? '', 'title': t.title},
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
    if (lower == settingsPage || lower == filtersPage || lower == historyPage) return lower;
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
