import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BrowserSearchEngine {
  ecosia('Ecosia', 'https://www.ecosia.org/search?q=%s'),
  duckDuckGo('DuckDuckGo', 'https://duckduckgo.com/?q=%s'),
  startpage('Startpage', 'https://www.startpage.com/do/search?q=%s'),
  brave('Brave Search', 'https://search.brave.com/search?q=%s'),
  google('Google', 'https://www.google.com/search?q=%s'),
  bing('Bing', 'https://www.bing.com/search?q=%s'),
  custom('', '');

  const BrowserSearchEngine(this.label, this.template);

  final String label;
  final String template;
}

enum BrowserNewTabPage { recent, blank, custom }

/// Options of the in-app browser.
class BrowserSettings extends ChangeNotifier {
  BrowserSettings._();

  static final BrowserSettings instance = BrowserSettings._();

  static const _prefix = 'browser.';
  SharedPreferences? _prefs;

  BrowserSearchEngine searchEngine = BrowserSearchEngine.ecosia;
  String customSearch = '';
  BrowserNewTabPage newTabPage = BrowserNewTabPage.recent;

  /// How many recently visited pages the new tab page lists.
  int recentCount = 10;
  String customNewTab = '';

  /// Tabs not shown for this long are suspended. 0 = never.
  int suspendMinutes = 5;

  /// Tabs that play audio are not suspended.
  bool keepPlayingAwake = true;
  bool restoreTabs = true;

  /// Recently visited pages are kept after the app closes.
  bool keepHistory = true;
  bool httpsUpgrade = true;

  /// Sites allowed to open pop-ups without a click on a link.
  List<String> popupSites = const [];

  /// Dark mode for websites (Dark Reader).
  bool darkMode = false;
  int darkBrightness = 100;
  int darkContrast = 100;

  /// Sites shown as they are, without dark mode.
  List<String> darkExcluded = const [];

  /// Tracking prevention: 0 off, 1 basic, 2 balanced, 3 strict (like Edge).
  int trackingLevel = 2;

  /// Cookies and site data are deleted when the app starts again.
  bool clearSiteDataOnExit = false;

  /// Remembered answers to permission requests: "site|kind" → allowed.
  Map<String, bool> permissions = const {};

  /// Disk cache limit in MB, applied when the browser starts.
  int cacheLimitMb = defaultCacheLimitMb;
  static const int defaultCacheLimitMb = 200;
  static const int minCacheLimitMb = 50;
  static const int maxCacheLimitMb = 20000;

  bool get isLoaded => _prefs != null;

  Future<void> load() async {
    if (_prefs != null) return;
    final p = _prefs = await SharedPreferences.getInstance();
    searchEngine = BrowserSearchEngine.values.asNameMap()[p.getString('${_prefix}search')] ?? searchEngine;
    customSearch = p.getString('${_prefix}customSearch') ?? '';
    newTabPage = BrowserNewTabPage.values.asNameMap()[p.getString('${_prefix}newTab')] ?? newTabPage;
    customNewTab = p.getString('${_prefix}customNewTab') ?? '';
    recentCount = p.getInt('${_prefix}recentCount') ?? recentCount;
    suspendMinutes = p.getInt('${_prefix}suspendMinutes') ?? suspendMinutes;
    keepPlayingAwake = p.getBool('${_prefix}keepPlayingAwake') ?? keepPlayingAwake;
    restoreTabs = p.getBool('${_prefix}restoreTabs') ?? restoreTabs;
    keepHistory = p.getBool('${_prefix}keepHistory') ?? keepHistory;
    httpsUpgrade = p.getBool('${_prefix}httpsUpgrade') ?? httpsUpgrade;
    popupSites = p.getStringList('${_prefix}popupSites') ?? const [];
    trackingLevel = p.getInt('${_prefix}tracking') ?? trackingLevel;
    darkMode = p.getBool('${_prefix}darkMode') ?? darkMode;
    darkBrightness = p.getInt('${_prefix}darkBrightness') ?? darkBrightness;
    darkContrast = p.getInt('${_prefix}darkContrast') ?? darkContrast;
    darkExcluded = p.getStringList('${_prefix}darkExcluded') ?? const [];
    clearSiteDataOnExit = p.getBool('${_prefix}clearSiteDataOnExit') ?? clearSiteDataOnExit;
    permissions = {
      for (final entry in p.getStringList('${_prefix}permissions') ?? const <String>[])
        if (entry.lastIndexOf('|') > 0)
          entry.substring(0, entry.lastIndexOf('|')): entry.substring(entry.lastIndexOf('|') + 1) == '1',
    };
    cacheLimitMb = p.getInt('${_prefix}cacheLimitMb') ?? cacheLimitMb;
    notifyListeners();
  }

  Future<void> setPopupAllowed(String site, bool allowed) async {
    await load();
    final sites = {...popupSites};
    if (allowed) {
      sites.add(site);
    } else {
      sites.remove(site);
    }
    popupSites = sites.toList()..sort();
    await _prefs!.setStringList('${_prefix}popupSites', popupSites);
    notifyListeners();
  }

  bool isDarkExcluded(String host) {
    final h = host.replaceFirst(RegExp(r'^www\.'), '');
    return darkExcluded.any((s) => h == s || h.endsWith('.$s'));
  }

  Future<void> setDarkExcluded(String site, bool excluded) async {
    await load();
    final sites = {...darkExcluded};
    if (excluded) {
      sites.add(site);
    } else {
      sites.remove(site);
    }
    darkExcluded = sites.toList()..sort();
    await _prefs!.setStringList('${_prefix}darkExcluded', darkExcluded);
    notifyListeners();
  }

  /// A remembered answer for permission [kind] on [site], or null.
  bool? permissionFor(String site, int kind) => permissions['$site|$kind'];

  Future<void> setPermission(String site, int kind, bool? allowed) async {
    await load();
    final map = {...permissions};
    if (allowed == null) {
      map.remove('$site|$kind');
    } else {
      map['$site|$kind'] = allowed;
    }
    permissions = map;
    await _prefs!.setStringList('${_prefix}permissions', [
      for (final e in map.entries) '${e.key}|${e.value ? 1 : 0}',
    ]);
    notifyListeners();
  }

  /// The search URL for [query]. A custom engine without a `%s` template
  /// falls back to Ecosia.
  String searchUrl(String query) {
    final template = searchEngine == BrowserSearchEngine.custom && customSearch.contains('%s')
        ? customSearch
        : (searchEngine == BrowserSearchEngine.custom ? BrowserSearchEngine.ecosia.template : searchEngine.template);
    return template.replaceAll('%s', Uri.encodeQueryComponent(query));
  }

  String get searchLabel => searchEngine == BrowserSearchEngine.custom ? (Uri.tryParse(customSearch)?.host ?? '') : searchEngine.label;

  Future<void> update({
    BrowserSearchEngine? searchEngine,
    String? customSearch,
    BrowserNewTabPage? newTabPage,
    String? customNewTab,
    int? recentCount,
    int? suspendMinutes,
    bool? keepPlayingAwake,
    bool? restoreTabs,
    bool? keepHistory,
    bool? httpsUpgrade,
    int? cacheLimitMb,
    int? trackingLevel,
    bool? clearSiteDataOnExit,
    bool? darkMode,
    int? darkBrightness,
    int? darkContrast,
  }) async {
    await load();
    final p = _prefs!;
    if (searchEngine != null) {
      this.searchEngine = searchEngine;
      await p.setString('${_prefix}search', searchEngine.name);
    }
    if (customSearch != null) {
      this.customSearch = customSearch;
      await p.setString('${_prefix}customSearch', customSearch);
    }
    if (newTabPage != null) {
      this.newTabPage = newTabPage;
      await p.setString('${_prefix}newTab', newTabPage.name);
    }
    if (customNewTab != null) {
      this.customNewTab = customNewTab;
      await p.setString('${_prefix}customNewTab', customNewTab);
    }
    if (recentCount != null) {
      this.recentCount = recentCount;
      await p.setInt('${_prefix}recentCount', recentCount);
    }
    if (suspendMinutes != null) {
      this.suspendMinutes = suspendMinutes;
      await p.setInt('${_prefix}suspendMinutes', suspendMinutes);
    }
    if (keepPlayingAwake != null) {
      this.keepPlayingAwake = keepPlayingAwake;
      await p.setBool('${_prefix}keepPlayingAwake', keepPlayingAwake);
    }
    if (restoreTabs != null) {
      this.restoreTabs = restoreTabs;
      await p.setBool('${_prefix}restoreTabs', restoreTabs);
    }
    if (keepHistory != null) {
      this.keepHistory = keepHistory;
      await p.setBool('${_prefix}keepHistory', keepHistory);
    }
    if (httpsUpgrade != null) {
      this.httpsUpgrade = httpsUpgrade;
      await p.setBool('${_prefix}httpsUpgrade', httpsUpgrade);
    }
    if (darkMode != null) {
      this.darkMode = darkMode;
      await p.setBool('${_prefix}darkMode', darkMode);
    }
    if (darkBrightness != null) {
      this.darkBrightness = darkBrightness;
      await p.setInt('${_prefix}darkBrightness', darkBrightness);
    }
    if (darkContrast != null) {
      this.darkContrast = darkContrast;
      await p.setInt('${_prefix}darkContrast', darkContrast);
    }
    if (trackingLevel != null) {
      this.trackingLevel = trackingLevel;
      await p.setInt('${_prefix}tracking', trackingLevel);
    }
    if (clearSiteDataOnExit != null) {
      this.clearSiteDataOnExit = clearSiteDataOnExit;
      await p.setBool('${_prefix}clearSiteDataOnExit', clearSiteDataOnExit);
    }
    if (cacheLimitMb != null) {
      this.cacheLimitMb = cacheLimitMb.clamp(minCacheLimitMb, maxCacheLimitMb);
      await p.setInt('${_prefix}cacheLimitMb', this.cacheLimitMb);
    }
    notifyListeners();
  }
}
