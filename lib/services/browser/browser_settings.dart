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
  bool httpsUpgrade = true;

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
    httpsUpgrade = p.getBool('${_prefix}httpsUpgrade') ?? httpsUpgrade;
    cacheLimitMb = p.getInt('${_prefix}cacheLimitMb') ?? cacheLimitMb;
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
    bool? httpsUpgrade,
    int? cacheLimitMb,
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
    if (httpsUpgrade != null) {
      this.httpsUpgrade = httpsUpgrade;
      await p.setBool('${_prefix}httpsUpgrade', httpsUpgrade);
    }
    if (cacheLimitMb != null) {
      this.cacheLimitMb = cacheLimitMb.clamp(minCacheLimitMb, maxCacheLimitMb);
      await p.setInt('${_prefix}cacheLimitMb', this.cacheLimitMb);
    }
    notifyListeners();
  }
}
