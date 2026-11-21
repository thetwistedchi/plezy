import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../focus/focusable_text_field.dart';
import '../focus/hub_vertical_navigation.dart';
import '../focus/locked_hub_controller.dart';
import '../i18n/retro_strings.dart';
import '../media/media_backend.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../models/catalog/catalog_item.dart';
import '../models/catalog/catalog_metadata.dart';
import '../providers/catalog_sources_provider.dart';
import '../providers/multi_server_provider.dart';
import '../services/catalog/plex_catalog_source.dart';
import '../services/plex_discover_client.dart';
import '../utils/app_logger.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/hub_section.dart';
import '../widgets/loading_indicator_box.dart';
import '../widgets/pill_input_decoration.dart';
import 'libraries/state_messages.dart';

/// Whether to offer the free catalog: a Plex server is connected (it needs
/// a Plex account). On Android the titles play in the in-app browser.
bool hasPlexServer(BuildContext context) =>
    context
    .read<MultiServerProvider>()
    .serverManager
    .onlineClients
    .values
    .any((client) => client.backend == MediaBackend.plex);

/// Fork: Plex's free, ad-supported Movies & Shows as its own library-like
/// page. The titles are listed here; playing them happens in Plex's own app
/// or Plex Web, which carry the DRM and the ads the service requires. Each
/// title's details page has a "Plex" button for that.
class FreeOnPlexScreen extends StatefulWidget {
  const FreeOnPlexScreen({super.key});

  /// Plex Web's page for a free title, where it plays.
  static String watchUrl(String ratingKey) =>
      'https://app.plex.tv/desktop/#!/provider/tv.plex.provider.vod/details?key=${Uri.encodeComponent('/library/metadata/$ratingKey')}';

  @override
  State<FreeOnPlexScreen> createState() => _FreeOnPlexScreenState();
}

class _FreeOnPlexScreenState extends State<FreeOnPlexScreen> {
  static const _section = '/hubs/sections/movies';
  static const _defaultAllKey = '/library/sections/movies/all';

  /// The full movie list's address: the usual one, or the movie section
  /// Plex lists when that one answers 404.
  static String _allKey = _defaultAllKey;
  static bool _allKeyResolved = false;

  /// Finds the movie section in the provider's section list.
  Future<String?> _resolveAllKey(PlexDiscoverClient client) async {
    if (_allKeyResolved) return null;
    _allKeyResolved = true;
    try {
      final sections = await client.getSections();
      final movies = sections.firstWhereOrNull((s) => s['type'] == 'movie') ??
          sections.firstWhereOrNull((s) => '${s['title']}'.toLowerCase().contains('movie'));
      final key = movies?['key']?.toString();
      if (key == null || key.isEmpty) return null;
      final path = key.startsWith('/') ? key : '/library/sections/$key';
      _allKey = path.endsWith('/all') ? path : '$path/all';
      appLogger.i('Free on Plex: full list found at the movie section');
      return _allKey;
    } catch (e) {
      appLogger.w('Free on Plex: section list unavailable', error: e);
      return null;
    }
  }
  static const _rowLimit = 30;
  static const _viewAllCap = 500;

  final _focusMemory = HubFocusMemory();

  // Search and the watchlist: Plex Discover (the app's Plex sign-in), each
  // title checked against the free catalog.
  final _searchText = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'free-plex-search');
  PlexDiscoverSession? _session;
  MediaHub? _searchHub;
  bool _searching = false;
  String? _searchMessage;
  int _searchRun = 0;
  MediaHub? _watchlistHub;

  /// Rating key -> the free catalog's entry (null: not free), for the app run.
  static final Map<String, Map<String, dynamic>?> _freeEntries = {};
  static MediaHub? _cachedWatchlist;
  static int? _cachedWatchlistFor;

  /// The rows on screen: search results, the full list, the watchlist,
  /// then Plex's shelves.
  List<MediaHub> get _shown {
    final rows = <MediaHub>[?_searchHub];
    for (final hub in _hubs) {
      rows.add(hub);
      if (hub.id == 'vod:all' && _watchlistHub != null) rows.add(_watchlistHub!);
    }
    if (_watchlistHub != null && !_hubs.any((h) => h.id == 'vod:all')) rows.insert(_searchHub == null ? 0 : 1, _watchlistHub!);
    return rows;
  }

  /// The free catalog's entries for [keys] (in that order), a few at a time.
  Future<List<Map<String, dynamic>>> _freeOf(List<String> keys) async {
    final client = _client;
    if (client == null) return const [];
    final todo = [for (final k in keys) if (!_freeEntries.containsKey(k)) k];
    var next = 0;
    Future<void> worker() async {
      while (next < todo.length) {
        final key = todo[next++];
        try {
          _freeEntries[key] = await client.getMetadata(key);
        } catch (e) {
          appLogger.d('Free on Plex: lookup failed for $key: $e');
        }
      }
    }
    await Future.wait([for (var i = 0; i < 12; i++) worker()]);
    return [for (final k in keys) if (_freeEntries[k] case final Map<String, dynamic> entry) entry];
  }

  MediaHub? _hubFrom(String id, String title, List<Map<String, dynamic>> entries) {
    final items = _mapper.mediaItems(entries);
    if (items.isEmpty) return null;
    return MediaHub(id: id, identifier: id.replaceFirst(':', '.'), title: title, type: 'mixed', items: items, size: items.length);
  }

  Future<void> _loadWatchlist({bool useCache = true}) async {
    final session = _session;
    if (session == null || _mapperOrNull == null) return;
    final owner = session.accessToken.hashCode;
    if (useCache && _cachedWatchlistFor == owner && _cachedWatchlist != null) {
      setState(() => _watchlistHub = _cachedWatchlist);
      return;
    }
    try {
      final discover = PlexDiscoverClient(session);
      final keys = <String>[];
      for (var page = 1; page <= 8; page++) {
        final result = await discover.getWatchlist(page: page, limit: 25);
        for (final entry in result.items) {
          final key = entry['ratingKey']?.toString();
          if (key != null && key.isNotEmpty) keys.add(key);
        }
        if (!result.hasMore || result.items.isEmpty) break;
      }
      final hub = _hubFrom('vod:watchlist', RetroStrings.freeOnPlexWatchlist, await _freeOf(keys));
      appLogger.i('Free on Plex: ${hub?.items.length ?? 0} of ${keys.length} watchlist titles are free');
      _cachedWatchlist = hub;
      _cachedWatchlistFor = owner;
      if (mounted) setState(() => _watchlistHub = hub);
    } catch (e) {
      appLogger.w('Free on Plex: watchlist not loaded', error: e);
    }
  }

  Future<void> _search(String text) async {
    final query = text.trim();
    final run = ++_searchRun;
    if (query.isEmpty) {
      setState(() {
        _searchHub = null;
        _searchMessage = null;
        _searching = false;
      });
      return;
    }
    final session = _session;
    if (session == null || _mapperOrNull == null) return;
    setState(() {
      _searching = true;
      _searchMessage = null;
    });
    try {
      final results = await PlexDiscoverClient(session).search(query, limit: 25);
      final keys = [
        for (final r in results)
          if (r.metadata['ratingKey']?.toString() case final String key when key.isNotEmpty) key,
      ];
      final hub = _hubFrom('vod:search', RetroStrings.freeOnPlexResults(query), await _freeOf(keys));
      if (!mounted || run != _searchRun) return;
      setState(() {
        _searching = false;
        _searchHub = hub;
        _searchMessage = hub == null ? RetroStrings.freeOnPlexNoResults : null;
      });
      if (hub != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_searchFocus.hasFocus) return;
          if (mounted) _hubKey(0).currentState?.requestFocusFromMemory();
        });
      }
    } catch (e) {
      appLogger.w('Free on Plex: search failed', error: e);
      if (!mounted || run != _searchRun) return;
      setState(() {
        _searching = false;
        _searchMessage = RetroStrings.freeOnPlexFailed;
      });
    }
  }

  @override
  void dispose() {
    _searchText.dispose();
    _searchFocus.dispose();
    super.dispose();
  }
  final Map<String, GlobalKey<HubSectionState>> _hubKeys = {};
  /// One per row (rows can share an id), for moving the focus between them.
  GlobalKey<HubSectionState> _hubKey(int index) =>
      _hubKeys.putIfAbsent('${_shown[index].id}#$index', GlobalKey<HubSectionState>.new);
  PlexDiscoverClient? _client;
  _VodMapper? _mapperOrNull;
  _VodMapper get _mapper => _mapperOrNull!;
  List<MediaHub> _hubs = const [];
  bool _loading = true;
  String? _error;

  // The catalog changes rarely: kept for the app run, refreshed in the
  // background when older than [_cacheFor].
  static List<MediaHub>? _cachedHubs;
  static DateTime? _cachedAt;

  /// Whose catalog is kept (the Plex profile's token, hashed): another
  /// profile loads its own.
  static int? _cachedFor;
  static const _cacheFor = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    unawaited(_load(useCache: true));
  }

  MediaHub? _hubOf(String id, String title, PlexDiscoverPage page) {
    final items = _mapper.mediaItems(page.items);
    if (items.isEmpty) return null;
    return MediaHub(
      id: id,
      identifier: id.replaceFirst(':', '.'),
      title: title,
      type: 'mixed',
      items: items,
      size: page.totalResults ?? items.length,
      more: page.hasMore,
    );
  }

  /// Loads the full list and Plex's shelves at the same time; the full list
  /// shows as soon as it is there. [quiet] keeps what is on screen while it
  /// loads; [connectOnly] only prepares the client for "View all".
  Future<void> _load({bool quiet = false, bool connectOnly = false, bool useCache = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final session = await context.read<CatalogSourcesProvider>().resolvePlexSession();
      if (!mounted) return;
      if (session == null) {
        if (quiet) return;
        setState(() {
          _loading = false;
          _error = RetroStrings.freeOnPlexNoAccount;
        });
        return;
      }
      final client = _client ??= PlexDiscoverClient(session, baseUri: PlexDiscoverClient.vodBaseUri);
      _mapperOrNull ??= _VodMapper(client);
      final firstSession = _session == null;
      _session = session;
      if (firstSession && !connectOnly) unawaited(_loadWatchlist());
      final owner = session.accessToken.hashCode;
      final cached = _cachedHubs;
      if (useCache && cached != null && cached.isNotEmpty && _cachedFor == owner) {
        setState(() {
          _hubs = cached;
          _loading = false;
          _error = null;
        });
        final fresh = _cachedAt != null && DateTime.now().difference(_cachedAt!) < _cacheFor;
        if (fresh) return;
        quiet = true;
      }
      if (connectOnly) return;

      final allFuture = client.getPage(_allKey, limit: _rowLimit);
      final shelvesFuture = client.getHomeHubs(section: _section, limit: _rowLimit, concurrency: 10);
      // Handled where it is awaited below; this keeps an early failure from
      // counting as unhandled meanwhile.
      unawaited(shelvesFuture.then((_) {}, onError: (_) {}));

      MediaHub? all;
      try {
        all = _hubOf('vod:all', RetroStrings.freeOnPlexAll, await allFuture);
      } catch (e) {
        appLogger.w('Free on Plex: full list unavailable', error: e);
        // The usual address is gone: look the movie section up once.
        final key = await _resolveAllKey(client);
        if (key != null) {
          try {
            all = _hubOf('vod:all', RetroStrings.freeOnPlexAll, await client.getPage(key, limit: _rowLimit));
          } catch (e) {
            appLogger.w('Free on Plex: movie section list unavailable', error: e);
          }
        }
      }
      // Everything in the catalog first, like a library's Browse, already
      // while the shelves still load.
      if (all != null && mounted && !quiet) {
        setState(() {
          _hubs = [all!];
          _loading = false;
        });
      }

      final shelves = await shelvesFuture;
      final hubs = <MediaHub>[];
      for (final shelf in shelves) {
        final hub = _hubOf('vod:${shelf.id}', shelf.title, shelf.page);
        if (hub == null) continue;
        hubs.add(hub);
        _shelfKeys['vod:${shelf.id}'] = shelf.key;
      }
      if (shelves.isNotEmpty) appLogger.d('Free on Plex: shelf addresses ${shelves.take(3).map((s) => s.key).join(', ')}');
      // Without Plex's full list: everything the shelves hold, each title once.
      if (all == null && hubs.isNotEmpty) {
        final seen = <String>{};
        final items = [
          for (final hub in hubs)
            for (final item in hub.items)
              if (seen.add(item.id)) item,
        ];
        _allFromShelves = true;
        all = MediaHub(
          id: 'vod:all',
          identifier: 'vod.all',
          title: RetroStrings.freeOnPlexAll,
          type: 'mixed',
          items: items,
          size: items.length,
          more: true,
        );
      } else if (all != null) {
        _allFromShelves = false;
      }
      final allHub = all;
      if (allHub != null) hubs.insert(0, allHub);
      if (hubs.isNotEmpty) {
        _cachedHubs = hubs;
        _cachedAt = DateTime.now();
        _cachedFor = owner;
      }
      if (!mounted) return;
      setState(() {
        _hubs = hubs.isNotEmpty ? hubs : _hubs;
        _loading = false;
        _error = _hubs.isEmpty ? RetroStrings.freeOnPlexEmpty : null;
      });
    } catch (e) {
      appLogger.w('Free on Plex failed to load', error: e);
      if (!mounted || quiet) return;
      setState(() {
        _loading = false;
        _error = _hubs.isEmpty ? RetroStrings.freeOnPlexFailed : null;
      });
    }
  }

  static final Map<String, String> _shelfKeys = {};

  /// Plex's full list is not available: "All" is made of the shelves.
  static bool _allFromShelves = false;

  /// "View all" for a row: the whole list, up to [_viewAllCap] titles.
  Future<List<MediaItem>> _loadAll(MediaHub hub) async {
    final client = _client;
    if (client == null) return hub.items;
    if (hub.id == 'vod:all' && _allFromShelves) {
      // Every shelf in full, each title once.
      final seen = <String>{};
      final items = <MediaItem>[];
      for (final key in _shelfKeys.values) {
        if (items.length >= _viewAllCap) break;
        try {
          final page = await client.getHub(key, limit: 100);
          for (final item in _mapper.mediaItems(page.items)) {
            if (seen.add(item.id)) items.add(item);
          }
        } catch (e) {
          appLogger.d('Free on Plex: shelf not loaded for the full list: $e');
        }
      }
      return items;
    }
    if (hub.id == 'vod:all') {
      final items = <MediaItem>[];
      var offset = 0;
      while (items.length < _viewAllCap) {
        final page = await client.getPage(_allKey, offset: offset, limit: 100);
        items.addAll(_mapper.mediaItems(page.items));
        offset += page.items.length;
        if (!page.hasMore || page.items.isEmpty) break;
      }
      return items;
    }
    final key = _shelfKeys[hub.id];
    if (key == null) return hub.items;
    final page = await client.getHub(key, limit: _viewAllCap);
    return _mapper.mediaItems(page.items);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final slivers = <Widget>[
      CustomAppBar(title: Text(RetroStrings.freeOnPlex), pinned: true),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            RetroStrings.freeOnPlexHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: FocusableTextField(
            controller: _searchText,
            focusNode: _searchFocus,
            decoration: pillInputDecoration(
              context,
              hintText: RetroStrings.freeOnPlexSearch,
              prefixIcon: const Icon(Symbols.search_rounded),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
            textInputAction: TextInputAction.search,
            // The keyboard only opens when the field is pressed, not on passing by.
            tvTextInputAutoOpenBehavior: TvTextInputAutoOpenBehavior.never,
            onSubmitted: (value) => unawaited(_search(value)),
            onNavigateDown: () {
              if (shown.isNotEmpty) _hubKey(0).currentState?.requestFocusFromMemory();
            },
          ),
        ),
      ),
      if (_searchMessage != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
            child: Text(_searchMessage!, style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      if (_loading)
        LoadingIndicatorBox.sliver
      else if (_error != null)
        SliverFillRemaining(
          child: StateMessageWidget(message: _error!, icon: Symbols.error_outline_rounded, iconSize: 64),
        )
      else
        for (final (index, hub) in shown.indexed)
          SliverToBoxAdapter(
            child: HubSection(
              key: _hubKey(index),
              hub: hub,
              // Up/Down move between the rows (the remote); Up from the first
              // row reaches the search field.
              onNavigateUp: index == 0 ? _searchFocus.requestFocus : null,
              onVerticalNavigation: (isUp) => navigateVerticalHubRows(
                hubCount: shown.length,
                hubIndex: index,
                isUp: isUp,
                propagateTopBoundary: true,
                requestFocus: (target) => _hubKey(target).currentState?.requestFocusFromMemory(),
              ),
              focusMemory: _focusMemory,
              icon: switch (hub.id) {
                'vod:all' => Symbols.local_activity_rounded,
                'vod:search' => Symbols.search_rounded,
                'vod:watchlist' => Symbols.bookmark_rounded,
                _ => Symbols.movie_rounded,
              },
              loadMoreItems: hub.more ? () => _loadAll(hub) : null,
              // The free catalog's listings carry no file details (quality,
              // languages), so the pill row would only leave a gap.
              showInfoPills: false,
            ),
          ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: slivers),
      ),
    );
  }
}

/// Free catalog entries as catalog items (their rating keys are Discover's,
/// so the details page loads them from Discover) with a "Plex" streaming
/// link to where they play.
class _VodMapper {
  _VodMapper(PlexDiscoverClient client) : _source = PlexCatalogSource(client);

  /// Only its mapping is used here.
  final PlexCatalogSource _source;

  List<MediaItem> mediaItems(List<Map<String, dynamic>> metadata) => [
    for (final entry in metadata)
      if (_item(entry) case final item?) item.toMediaItem(),
  ];

  CatalogItem? _item(Map<String, dynamic> metadata) {
    final item = _source.toCatalogItem(metadata);
    final ratingKey = item?.ids.plex;
    if (item == null || ratingKey == null || ratingKey.isEmpty) return item;
    final watch = CatalogLink(
      label: RetroStrings.freeOnPlexWatch,
      url: FreeOnPlexScreen.watchUrl(ratingKey),
      isStreaming: true,
    );
    return CatalogItem.fromJson({
      ...item.toJson(),
      'links': [watch.toJson(), for (final link in item.links ?? const <CatalogLink>[]) link.toJson()],
    });
  }
}
