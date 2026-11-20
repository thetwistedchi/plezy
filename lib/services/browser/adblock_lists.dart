import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/strings.g.dart';
import '../../utils/app_logger.dart';
import 'browser_native.dart';

enum FilterGroup { builtin, ads, privacy, malware, annoyances, multipurpose, regional, custom }

/// A filter list the browser's ad blocker can use, like in uBlock Origin.
class FilterListInfo {
  const FilterListInfo({
    required this.id,
    required this.name,
    required this.group,
    required this.urls,
    this.defaultOn = false,
    this.trusted = false,
    this.language,
  });

  final String id;
  final String name;
  final FilterGroup group;

  /// The address and mirrors, tried in order.
  final List<String> urls;
  final bool defaultOn;

  /// Lists by uBlock Origin's maintainers may run trusted scriptlets.
  final bool trusted;

  /// Regional lists are on by default when the app uses this language.
  final String? language;
}

const _uAssets = 'https://ublockorigin.github.io/uAssets';
const _uAssetsCdn = 'https://ublockorigin.github.io/uAssetsCDN';
const _uPages = 'https://ublockorigin.pages.dev';
const _jsdelivr = 'https://cdn.jsdelivr.net/gh/uBlockOrigin/uAssetsCDN@main';

/// The lists offered, after uBlock Origin's own selection and defaults.
const filterListCatalog = <FilterListInfo>[
  FilterListInfo(
    id: 'ublock-filters',
    name: 'uBlock filters – Ads',
    group: FilterGroup.builtin,
    urls: ['$_uAssets/filters/filters.txt', '$_uAssetsCdn/filters/filters.min.txt', '$_uPages/filters/filters.min.txt'],
    defaultOn: true,
    trusted: true,
  ),
  FilterListInfo(
    id: 'ublock-badware',
    name: 'uBlock filters – Badware risks',
    group: FilterGroup.builtin,
    urls: ['$_uAssets/filters/badware.txt', '$_uAssetsCdn/filters/badware.min.txt', '$_uPages/filters/badware.min.txt'],
    defaultOn: true,
    trusted: true,
  ),
  FilterListInfo(
    id: 'ublock-privacy',
    name: 'uBlock filters – Privacy',
    group: FilterGroup.builtin,
    urls: ['$_uAssets/filters/privacy.txt', '$_uAssetsCdn/filters/privacy.min.txt', '$_uPages/filters/privacy.min.txt'],
    defaultOn: true,
    trusted: true,
  ),
  FilterListInfo(
    id: 'ublock-unbreak',
    name: 'uBlock filters – Unbreak',
    group: FilterGroup.builtin,
    urls: ['$_uAssets/filters/unbreak.txt', '$_uAssetsCdn/filters/unbreak.min.txt', '$_uPages/filters/unbreak.min.txt'],
    defaultOn: true,
    trusted: true,
  ),
  FilterListInfo(
    id: 'ublock-quick-fixes',
    name: 'uBlock filters – Quick fixes',
    group: FilterGroup.builtin,
    urls: [
      '$_uAssets/filters/quick-fixes.txt',
      '$_uAssetsCdn/filters/quick-fixes.min.txt',
      '$_uPages/filters/quick-fixes.min.txt',
    ],
    defaultOn: true,
    trusted: true,
  ),
  FilterListInfo(
    id: 'easylist',
    name: 'EasyList',
    group: FilterGroup.ads,
    urls: [
      '$_uAssets/thirdparties/easylist.txt',
      '$_jsdelivr/thirdparties/easylist.txt',
      '$_uPages/thirdparties/easylist.txt',
      'https://easylist.to/easylist/easylist.txt',
    ],
    defaultOn: true,
  ),
  FilterListInfo(
    id: 'easyprivacy',
    name: 'EasyPrivacy',
    group: FilterGroup.privacy,
    urls: [
      '$_uAssets/thirdparties/easyprivacy.txt',
      '$_jsdelivr/thirdparties/easyprivacy.txt',
      '$_uPages/thirdparties/easyprivacy.txt',
      'https://easylist.to/easylist/easyprivacy.txt',
    ],
    defaultOn: true,
  ),
  FilterListInfo(
    id: 'adguard-spyware-url',
    name: 'AdGuard/uBO – URL Tracking Protection',
    group: FilterGroup.privacy,
    urls: ['$_uAssets/filters/privacy-removeparam.txt', '$_uAssetsCdn/filters/privacy-removeparam.txt'],
    trusted: true,
  ),
  FilterListInfo(
    id: 'block-lan',
    name: 'Block Outsider Intrusion into LAN',
    group: FilterGroup.privacy,
    urls: ['$_uAssets/filters/lan-block.txt', '$_uAssetsCdn/filters/lan-block.txt'],
    trusted: true,
  ),
  FilterListInfo(
    id: 'urlhaus-1',
    name: 'Online Malicious URL Blocklist',
    group: FilterGroup.malware,
    urls: [
      'https://malware-filter.gitlab.io/urlhaus-filter/urlhaus-filter-vivaldi-online.txt',
      'https://curbengh.github.io/malware-filter/urlhaus-filter-vivaldi-online.txt',
    ],
    defaultOn: true,
  ),
  FilterListInfo(
    id: 'curben-phishing',
    name: 'Phishing URL Blocklist',
    group: FilterGroup.malware,
    urls: [
      'https://malware-filter.gitlab.io/phishing-filter/phishing-filter.txt',
      'https://curbengh.github.io/phishing-filter/phishing-filter.txt',
    ],
  ),
  FilterListInfo(
    id: 'plowe-0',
    name: 'Peter Lowe’s Ad and tracking server list',
    group: FilterGroup.multipurpose,
    urls: ['https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=1&mimetype=plaintext'],
    defaultOn: true,
  ),
  FilterListInfo(
    id: 'ublock-annoyances',
    name: 'uBlock filters – Annoyances',
    group: FilterGroup.annoyances,
    urls: ['$_uAssets/filters/annoyances.txt', '$_uAssetsCdn/filters/annoyances.min.txt'],
    trusted: true,
  ),
  FilterListInfo(
    id: 'ublock-cookies-easylist',
    name: 'uBlock filters – Cookie Notices',
    group: FilterGroup.annoyances,
    urls: ['$_uAssets/filters/annoyances-cookies.txt', '$_uAssetsCdn/filters/annoyances-cookies.txt'],
    trusted: true,
  ),
  FilterListInfo(
    id: 'fanboy-cookiemonster',
    name: 'EasyList – Cookie Notices',
    group: FilterGroup.annoyances,
    urls: ['$_uAssets/thirdparties/easylist-cookies.txt', '$_uAssetsCdn/thirdparties/easylist-cookies.txt'],
  ),
  FilterListInfo(
    id: 'easylist-annoyances',
    name: 'EasyList – Annoyances',
    group: FilterGroup.annoyances,
    urls: ['$_uAssets/thirdparties/easylist-annoyances.txt', '$_uAssetsCdn/thirdparties/easylist-annoyances.txt'],
  ),
  FilterListInfo(
    id: 'DEU-0',
    name: 'EasyList Germany (de, ch, at)',
    group: FilterGroup.regional,
    urls: ['https://easylist.to/easylistgermany/easylistgermany.txt', 'https://easylist-downloads.adblockplus.org/easylistgermany.txt'],
    language: 'de',
  ),
  FilterListInfo(
    id: 'FRA-0',
    name: 'Liste FR (fr)',
    group: FilterGroup.regional,
    urls: ['https://easylist-downloads.adblockplus.org/liste_fr.txt'],
    language: 'fr',
  ),
  FilterListInfo(
    id: 'ITA-0',
    name: 'EasyList Italy (it)',
    group: FilterGroup.regional,
    urls: ['https://easylist-downloads.adblockplus.org/easylistitaly.txt'],
    language: 'it',
  ),
  FilterListInfo(
    id: 'NLD-0',
    name: 'EasyDutch (nl)',
    group: FilterGroup.regional,
    urls: ['https://easydutch-ubo.github.io/EasyDutch/EasyDutch.txt'],
    language: 'nl',
  ),
  FilterListInfo(
    id: 'ESP-0',
    name: 'EasyList Spanish (es)',
    group: FilterGroup.regional,
    urls: ['https://easylist-downloads.adblockplus.org/easylistspanish.txt'],
    language: 'es',
  ),
  FilterListInfo(
    id: 'POL-0',
    name: 'Oficjalne Polskie Filtry (pl)',
    group: FilterGroup.regional,
    urls: ['https://raw.githubusercontent.com/MajkiIT/polish-ads-filter/master/polish-adblock-filters/adblock.txt'],
    language: 'pl',
  ),
];

class FilterListState {
  FilterListState({this.updatedAt, this.rules = 0, this.error});

  DateTime? updatedAt;
  int rules;
  String? error;

  Map<String, Object?> toJson() => {'updatedAt': updatedAt?.toIso8601String(), 'rules': rules, 'error': error};

  static FilterListState fromJson(Object? json) {
    if (json is! Map) return FilterListState();
    return FilterListState(
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      rules: (json['rules'] as num?)?.toInt() ?? 0,
      error: json['error'] as String?,
    );
  }
}

/// The ad blocker: which lists are used, keeping them up to date, and
/// building the engine (Brave's adblock-rust, see windows/runner/adblock).
class AdblockManager extends ChangeNotifier {
  AdblockManager._();

  static final AdblockManager instance = AdblockManager._();

  static const _prefix = 'browser.adblock.';
  static const updateEvery = Duration(hours: 24);

  /// Bump when the bundled scriptlet resources change.
  static const _resourcesVersion = 'ubo-2026-11-20';

  SharedPreferences? _prefs;
  Directory? _dir;

  bool enabled = true;
  Set<String> enabledLists = {};
  List<String> customUrls = const [];
  String userFilters = '';
  List<String> offSites = const [];
  final Map<String, FilterListState> states = {};

  bool updating = false;
  bool building = false;
  DateTime? lastBuilt;
  Future<void>? _started;
  Timer? _timer;

  bool get isLoaded => _prefs != null;

  Future<void> load() async {
    if (_prefs != null) return;
    final p = _prefs = await SharedPreferences.getInstance();
    final support = await getApplicationSupportDirectory();
    _dir = Directory('${support.path}${Platform.pathSeparator}browser_adblock');
    await Directory('${_dir!.path}${Platform.pathSeparator}lists').create(recursive: true);
    enabled = p.getBool('${_prefix}enabled') ?? true;
    final saved = p.getStringList('${_prefix}lists');
    final language = LocaleSettings.currentLocale.languageCode;
    enabledLists = saved?.toSet() ??
        {
          for (final l in filterListCatalog)
            if (l.defaultOn || l.language == language) l.id,
        };
    customUrls = p.getStringList('${_prefix}custom') ?? const [];
    userFilters = p.getString('${_prefix}userFilters') ?? '';
    offSites = p.getStringList('${_prefix}offSites') ?? const [];
    try {
      final json = jsonDecode(p.getString('${_prefix}states') ?? '{}');
      if (json is Map) {
        for (final e in json.entries) {
          states[e.key as String] = FilterListState.fromJson(e.value);
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _saveStates() async {
    await _prefs?.setString('${_prefix}states', jsonEncode({for (final e in states.entries) e.key: e.value.toJson()}));
  }

  static String customId(String url) => 'custom-${sha1.convert(utf8.encode(url)).toString().substring(0, 12)}';

  File _fileFor(String id) => File('${_dir!.path}${Platform.pathSeparator}lists${Platform.pathSeparator}$id.txt');

  /// Every list in use: (id, addresses, trusted).
  List<(String, List<String>, bool)> get _activeLists => [
    for (final l in filterListCatalog)
      if (enabledLists.contains(l.id)) (l.id, l.urls, l.trusted),
    for (final url in customUrls) (customId(url), [url], false),
  ];

  /// Starts the engine with the lists on disk, then updates lists that are
  /// missing or older than [updateEvery]. Called when the browser starts.
  Future<void> start() => _started ??= _start();

  Future<void> _start() async {
    await load();
    await _apply();
    if (enabled) {
      unawaited(_ensureResources().then((_) => rebuild()));
    }
    _timer ??= Timer.periodic(const Duration(hours: 1), (_) => unawaited(update()));
    unawaited(update());
  }

  Future<void> _apply() async {
    final native = BrowserNative.instance;
    await native.adblockSetEnabled(enabled);
    await native.adblockSetOffSites(offSites);
  }

  Future<String> _ensureResources() async {
    final file = File('${_dir!.path}${Platform.pathSeparator}resources.json');
    final marker = File('${file.path}.version');
    final current = await marker.exists() ? await marker.readAsString() : '';
    if (current != _resourcesVersion || !await file.exists()) {
      final data = await rootBundle.load('assets/browser/ubo-resources.json');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await marker.writeAsString(_resourcesVersion, flush: true);
    }
    return file.path;
  }

  /// Rebuilds the engine from the lists on disk. Unchanged input loads the
  /// saved engine instead, which takes a few milliseconds.
  Future<void> rebuild() async {
    await load();
    // Built when the browser engine starts ([start]).
    if (!BrowserNative.instance.isReady) return;
    final lists = <Map<String, Object>>[];
    final key = StringBuffer('$_resourcesVersion|');
    for (final (id, _, trusted) in _activeLists) {
      final file = _fileFor(id);
      if (!await file.exists()) continue;
      final stat = await file.stat();
      lists.add({'path': file.path, 'trusted': trusted});
      key.write('$id:${stat.size}:${stat.modified.millisecondsSinceEpoch};');
    }
    key.write(sha1.convert(utf8.encode(userFilters)));
    building = true;
    notifyListeners();
    final config = jsonEncode({
      'lists': lists,
      'userFilters': userFilters,
      'resources': await _ensureResources(),
      'cache': '${_dir!.path}${Platform.pathSeparator}engine.dat',
      'cacheKey': sha1.convert(utf8.encode(key.toString())).toString(),
    });
    await BrowserNative.instance.adblockLoad(config);
  }

  /// Called when the native side swapped in a new engine.
  void onReady(bool ok, int ms) {
    building = false;
    lastBuilt = DateTime.now();
    appLogger.i('Ad blocker: engine ${ok ? 'ready' : 'failed'} in $ms ms (${_activeLists.length} lists)');
    notifyListeners();
  }

  /// Downloads lists that are missing, older than [updateEvery], or all of
  /// them with [force]; rebuilds the engine when any changed.
  Future<void> update({bool force = false}) async {
    await load();
    if (updating || !enabled) return;
    updating = true;
    notifyListeners();
    var changed = false;
    try {
      for (final (id, urls, _) in _activeLists) {
        final state = states[id] ??= FilterListState();
        final file = _fileFor(id);
        final fresh = state.updatedAt != null &&
            DateTime.now().difference(state.updatedAt!) < updateEvery &&
            await file.exists();
        if (fresh && !force) continue;
        final text = await _download(urls);
        if (text == null) {
          state.error = 'download failed';
          continue;
        }
        await file.writeAsString(text, flush: true);
        state
          ..updatedAt = DateTime.now()
          ..rules = _countRules(text)
          ..error = null;
        changed = true;
        notifyListeners();
      }
    } finally {
      updating = false;
      await _saveStates();
      notifyListeners();
    }
    if (changed) await rebuild();
  }

  static int _countRules(String text) {
    var n = 0;
    for (final line in const LineSplitter().convert(text)) {
      final t = line.trimLeft();
      if (t.isEmpty || t.startsWith('!') || t.startsWith('[') || t.startsWith('#') && !t.startsWith('##')) continue;
      n++;
    }
    return n;
  }

  Future<String?> _download(List<String> urls) async {
    for (final url in urls) {
      try {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
        if (response.statusCode == 200 && response.bodyBytes.length > 32) {
          return utf8.decode(response.bodyBytes, allowMalformed: true);
        }
        appLogger.d('Ad blocker: $url answered ${response.statusCode}');
      } catch (e) {
        appLogger.d('Ad blocker: $url failed: $e');
      }
    }
    return null;
  }

  Future<void> setEnabled(bool value) async {
    await load();
    enabled = value;
    await _prefs!.setBool('${_prefix}enabled', value);
    await _apply();
    notifyListeners();
    if (value) {
      await update();
      await rebuild();
    }
  }

  Future<void> setListEnabled(String id, bool value) async {
    await load();
    if (value) {
      enabledLists.add(id);
    } else {
      enabledLists.remove(id);
    }
    await _prefs!.setStringList('${_prefix}lists', enabledLists.toList());
    notifyListeners();
    if (value && !await _fileFor(id).exists()) {
      await update();
    }
    await rebuild();
  }

  Future<bool> addCustomList(String url) async {
    await load();
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || customUrls.contains(url.trim())) return false;
    customUrls = [...customUrls, url.trim()];
    await _prefs!.setStringList('${_prefix}custom', customUrls);
    notifyListeners();
    await update();
    return states[customId(url.trim())]?.error == null;
  }

  Future<void> removeCustomList(String url) async {
    await load();
    customUrls = customUrls.where((u) => u != url).toList();
    await _prefs!.setStringList('${_prefix}custom', customUrls);
    final file = _fileFor(customId(url));
    if (await file.exists()) await file.delete();
    states.remove(customId(url));
    await _saveStates();
    notifyListeners();
    await rebuild();
  }

  Future<void> setUserFilters(String text) async {
    await load();
    userFilters = text;
    await _prefs!.setString('${_prefix}userFilters', text);
    notifyListeners();
    await rebuild();
  }

  bool isOffFor(String site) => offSites.contains(site);

  Future<void> setOffForSite(String site, bool off) async {
    await load();
    final sites = {...offSites};
    if (off) {
      sites.add(site);
    } else {
      sites.remove(site);
    }
    offSites = sites.toList()..sort();
    await _prefs!.setStringList('${_prefix}offSites', offSites);
    await _apply();
    notifyListeners();
  }
}
