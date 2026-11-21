import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

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
  static const _allKey = '/library/sections/movies/all';
  static const _rowLimit = 30;
  static const _viewAllCap = 500;

  final _focusMemory = HubFocusMemory();
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
  static const _cacheFor = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    final cached = _cachedHubs;
    if (cached != null && cached.isNotEmpty) {
      _hubs = cached;
      _loading = false;
      final fresh = _cachedAt != null && DateTime.now().difference(_cachedAt!) < _cacheFor;
      unawaited(_load(quiet: true, connectOnly: fresh));
    } else {
      unawaited(_load());
    }
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
  Future<void> _load({bool quiet = false, bool connectOnly = false}) async {
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
      final hubs = <MediaHub>[?all];
      for (final shelf in shelves) {
        final hub = _hubOf('vod:${shelf.id}', shelf.title, shelf.page);
        if (hub == null) continue;
        hubs.add(hub);
        _shelfKeys['vod:${shelf.id}'] = shelf.key;
      }
      if (hubs.isNotEmpty) {
        _cachedHubs = hubs;
        _cachedAt = DateTime.now();
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

  /// "View all" for a row: the whole list, up to [_viewAllCap] titles.
  Future<List<MediaItem>> _loadAll(MediaHub hub) async {
    final client = _client;
    if (client == null) return hub.items;
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
      if (_loading)
        LoadingIndicatorBox.sliver
      else if (_error != null)
        SliverFillRemaining(
          child: StateMessageWidget(message: _error!, icon: Symbols.error_outline_rounded, iconSize: 64),
        )
      else
        for (final hub in _hubs)
          SliverToBoxAdapter(
            child: HubSection(
              hub: hub,
              focusMemory: _focusMemory,
              icon: hub.id == 'vod:all' ? Symbols.local_activity_rounded : Symbols.movie_rounded,
              loadMoreItems: hub.more ? () => _loadAll(hub) : null,
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
