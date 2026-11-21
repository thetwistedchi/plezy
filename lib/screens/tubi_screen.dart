import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/focusable_text_field.dart';
import '../focus/hub_vertical_navigation.dart';
import '../focus/locked_hub_controller.dart';
import '../i18n/retro_strings.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../models/catalog/catalog_item.dart';
import '../models/catalog/catalog_metadata.dart';
import '../services/tubi/tubi_client.dart';
import '../utils/app_logger.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/hub_section.dart';
import '../widgets/loading_indicator_box.dart';
import '../widgets/pill_input_decoration.dart';
import 'libraries/state_messages.dart';

/// Fork (beta): Tubi's free catalog. Rows and search from Tubi's website;
/// a title's details page plays it on tubitv.com (on Android in its own
/// full-screen page, on Windows in the browser).
class TubiScreen extends StatefulWidget {
  const TubiScreen({super.key});

  /// A Tubi title as a catalog item, so the usual details page shows it.
  static MediaItem mediaItem(TubiTitle t) => CatalogItem.fromJson({
    'source': CatalogSourceId.plex.name,
    'kind': (t.isSeries ? MediaKind.show : MediaKind.movie).id,
    'title': t.title,
    if (t.year != null) 'year': t.year,
    if (t.description != null) 'overview': t.description,
    if (t.minutes != null && !t.isSeries) 'runtimeMinutes': t.minutes,
    'ids': {'slug': 'tubi-${t.isSeries ? 's' : 'm'}${t.id}', if (t.imdb != null) 'imdb': t.imdb},
    if (t.posterUrl != null) 'posterUrl': t.posterUrl,
    if (t.backdropUrl != null) 'backdropUrl': t.backdropUrl,
    'links': [CatalogLink(label: RetroStrings.tubiWatch, url: t.watchUrl, isStreaming: true).toJson()],
  }).toMediaItem();

  @override
  State<TubiScreen> createState() => _TubiScreenState();
}

class _TubiScreenState extends State<TubiScreen> {
  final _client = TubiClient();
  final _focusMemory = HubFocusMemory();
  final Map<String, GlobalKey<HubSectionState>> _hubKeys = {};
  final _searchText = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'tubi-search');

  List<MediaHub> _hubs = const [];
  MediaHub? _searchHub;
  bool _loading = true;
  bool _searching = false;
  String? _error;
  String? _searchMessage;
  int _searchRun = 0;

  static List<MediaHub>? _cached;
  static DateTime? _cachedAt;

  List<MediaHub> get _shown => [?_searchHub, ..._hubs];

  GlobalKey<HubSectionState> _hubKey(int index) =>
      _hubKeys.putIfAbsent('${_shown[index].id}#$index', GlobalKey<HubSectionState>.new);

  static MediaHub _hub(String id, String title, List<TubiTitle> items) => MediaHub(
    id: id,
    identifier: id.replaceFirst(':', '.'),
    title: title,
    type: 'mixed',
    items: [for (final t in items) TubiScreen.mediaItem(t)],
    size: items.length,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _client.dispose();
    _searchText.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    final cached = _cached;
    if (!force && cached != null && DateTime.now().difference(_cachedAt!) < const Duration(minutes: 30)) {
      setState(() {
        _hubs = cached;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _client.home();
      final hubs = [for (final (i, row) in rows.indexed) _hub('tubi:$i', row.title, row.items)];
      _cached = hubs;
      _cachedAt = DateTime.now();
      if (!mounted) return;
      setState(() {
        _hubs = hubs;
        _loading = false;
        _error = hubs.isEmpty ? RetroStrings.tubiFailed : null;
      });
    } on TubiUnavailableException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = RetroStrings.tubiUnavailable;
      });
    } catch (e) {
      appLogger.w('Tubi failed to load', error: e);
      if (!mounted) return;
      setState(() {
        _loading = false;
        // The reason too: this beta reads Tubi's website, which can change.
        _error = _hubs.isEmpty ? '${RetroStrings.tubiFailed}\n$e' : null;
      });
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
    setState(() {
      _searching = true;
      _searchMessage = null;
    });
    try {
      final results = await _client.search(query);
      if (!mounted || run != _searchRun) return;
      setState(() {
        _searching = false;
        _searchHub = results.isEmpty ? null : _hub('tubi:search', RetroStrings.tubiResults(query), results);
        _searchMessage = results.isEmpty ? RetroStrings.freeOnPlexNoResults : null;
      });
      if (results.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _searchFocus.hasFocus) _hubKey(0).currentState?.requestFocusFromMemory();
        });
      }
    } catch (e) {
      appLogger.w('Tubi search failed', error: e);
      if (!mounted || run != _searchRun) return;
      setState(() {
        _searching = false;
        _searchMessage = e is TubiUnavailableException ? RetroStrings.tubiUnavailable : RetroStrings.tubiFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final theme = Theme.of(context);
    final slivers = <Widget>[
      CustomAppBar(
        title: Text('${RetroStrings.tubi} (beta)'),
        pinned: true,
        actions: [
          IconButton(
            tooltip: RetroStrings.reload,
            icon: const Icon(Symbols.refresh_rounded),
            onPressed: _loading ? null : () => unawaited(_load(force: true)),
          ),
        ],
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(RetroStrings.tubiHint, style: theme.textTheme.bodySmall),
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
              hintText: RetroStrings.tubiSearch,
              prefixIcon: const Icon(Symbols.search_rounded),
            ),
            textInputAction: TextInputAction.search,
            tvTextInputAutoOpenBehavior: TvTextInputAutoOpenBehavior.never,
            onSubmitted: (value) => unawaited(_search(value)),
            onNavigateDown: () {
              if (shown.isNotEmpty) _hubKey(0).currentState?.requestFocusFromMemory();
            },
          ),
        ),
      ),
      if (_searching)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(RetroStrings.tubiSearching(_searchText.text.trim()), style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                const ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              ],
            ),
          ),
        ),
      if (_searchMessage != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
            child: Text(_searchMessage!, style: theme.textTheme.bodySmall),
          ),
        ),
      if (_loading)
        LoadingIndicatorBox.sliver
      else if (_error != null && shown.isEmpty)
        SliverFillRemaining(
          child: StateMessageWidget(message: _error!, icon: Symbols.public_off_rounded, iconSize: 64),
        )
      else
        for (final (index, hub) in shown.indexed)
          SliverToBoxAdapter(
            child: HubSection(
              key: _hubKey(index),
              hub: hub,
              onNavigateUp: index == 0 ? _searchFocus.requestFocus : null,
              onVerticalNavigation: (isUp) => navigateVerticalHubRows(
                hubCount: shown.length,
                hubIndex: index,
                isUp: isUp,
                propagateTopBoundary: true,
                requestFocus: (target) => _hubKey(target).currentState?.requestFocusFromMemory(),
              ),
              focusMemory: _focusMemory,
              icon: hub.id == 'tubi:search' ? Symbols.search_rounded : Symbols.live_tv_rounded,
              showInfoPills: false,
            ),
          ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: CustomScrollView(slivers: slivers),
      ),
    );
  }
}
