import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/retro_strings.dart';
import '../../../media/ids.dart';
import '../../../media/library_query.dart';
import '../../../media/media_item.dart';
import '../../../media/media_item_types.dart';
import '../../../mixins/grid_focus_node_mixin.dart';
import '../../../mixins/library_tab_focus_mixin.dart';
import '../../../services/retrowave/upcoming_episodes.dart';
import '../../../services/settings_service.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/layout_constants.dart';
import '../../../utils/provider_extensions.dart';
import '../../../widgets/focusable_media_card.dart';
import '../../../widgets/media_card_sliver_layout.dart';
import '../../../widgets/nested_tab_scrollbar.dart';
import '../../main_screen.dart';
import 'base_library_tab.dart';

/// Fork: shows of a TV library with an episode still to air, soonest first.
/// Air dates come from TVmaze; the first visit checks every show (a few
/// minutes for big libraries), later visits answer from the device cache.
class LibraryUpcomingTab extends BaseLibraryTab<MediaItem> {
  const LibraryUpcomingTab({
    super.key,
    required super.library,
    super.onDataLoaded,
    super.isActive,
    super.suppressAutoFocus,
    super.onBack,
  });

  @override
  State<LibraryUpcomingTab> createState() => _LibraryUpcomingTabState();
}

class _LibraryUpcomingTabState extends BaseLibraryTabState<MediaItem, LibraryUpcomingTab>
    with GridFocusNodeMixin, LibraryTabFocusMixin {
  List<UpcomingEpisode> _results = const [];
  int _checked = 0;
  int _scanId = 0;
  bool _scanning = false;

  @override
  String get focusNodeDebugLabel => 'upcoming_first_item';

  @override
  int get itemCount => _results.length;

  @override
  IconData get emptyIcon => Symbols.calendar_month_rounded;

  @override
  String get emptyMessage => RetroStrings.upcomingNone;

  @override
  String get errorContext => RetroStrings.upcomingEpisodes;

  @override
  Future<void> loadItems() async {
    await runLoadTransaction(() async {
      final library = widget.library;
      final page = await getMediaClientForLibrary().fetchLibraryPagedContent(
        library.id,
        libraryKind: library.kind,
        query: LibraryQuery(kind: library.kind, limit: 5000),
      );
      // Shows being watched first, so the likely ones turn up early.
      final shows = page.items.where((i) => i.isShow).toList()
        ..sort((a, b) => ((b.viewedLeafCount ?? 0) > 0 ? 1 : 0).compareTo((a.viewedLeafCount ?? 0) > 0 ? 1 : 0));
      return shows;
    });
    if (items.isNotEmpty) unawaited(_scan(items));
  }

  Future<void> _scan(List<MediaItem> shows) async {
    final id = ++_scanId;
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _checked = 0;
      _results = const [];
    });
    await UpcomingEpisodes.instance.forShows(
      shows,
      (show) => context.tryGetMediaClientForServer(serverIdOrNull(show.serverId)),
      isCancelled: () => !mounted || id != _scanId,
      onProgress: (soFar, done) {
        if (!mounted || id != _scanId) return;
        final first = _results.isEmpty && soFar.isNotEmpty;
        setState(() {
          _results = soFar;
          _checked = done;
        });
        if (first) tryFocus();
      },
    );
    if (mounted && id == _scanId) setState(() => _scanning = false);
  }

  @override
  void dispose() {
    _scanId++;
    disposeGridFocusNodes();
    super.dispose();
  }

  void _focusCard(int index) {
    if (index < 0 || index >= _results.length) return;
    final node = _cardFocusNode(index);
    if (node.context != null) {
      node.requestFocus();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) node.requestFocus();
      });
    }
  }

  FocusNode _cardFocusNode(int index) => focusNodeForIndex(
    index,
    firstItemFocusNode,
    prefix: 'upcoming_item',
    itemIdentity: '${_results[index].show.serverId}:${_results[index].show.id}',
  );

  @override
  Widget buildContent(List<MediaItem> items) {
    final mono = tokens(context);
    final results = _results;
    final status = _scanning
        ? RetroStrings.upcomingChecking(_checked, items.length)
        : (results.isEmpty ? RetroStrings.upcomingNone : null);
    final base = GridLayoutConstants.gridPadding;
    return NestedTabScrollbar(
      child: UpcomingLabelScope(
        child: CustomScrollView(
          clipBehavior: Clip.none,
          slivers: [
            SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
            if (status != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(base.left, 8, base.right, 4),
                  child: Row(
                    children: [
                      if (_scanning) ...[
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(status, style: TextStyle(color: mono.textMuted)),
                      ),
                    ],
                  ),
                ),
              ),
            MediaCardSliverLayout(
              viewMode: ViewMode.grid,
              itemCount: results.length,
              density: SettingsService.instance.read(SettingsService.libraryDensity),
              padding: base.copyWith(top: base.top + 3),
              itemBuilder: (context, position) {
                final index = position.index;
                final columns = position.columnCount;
                final show = results[index].show;
                return FocusableMediaCard(
                  key: ValueKey('${show.serverId}:${show.id}'),
                  item: show,
                  focusNode: _cardFocusNode(index),
                  disableScale: position.disableScale,
                  onNavigateUp: position.isFirstRow ? widget.onBack : () => _focusCard(index - columns),
                  onNavigateDown: index + columns < results.length ? () => _focusCard(index + columns) : null,
                  onNavigateLeft: position.isFirstColumn
                      ? () => MainScreenFocusScope.focusSidebarOf(context)
                      : () => _focusCard(index - 1),
                  onNavigateRight: !position.isLastColumn && index + 1 < results.length
                      ? () => _focusCard(index + 1)
                      : null,
                  onBack: widget.onBack,
                  onFocusChange: (hasFocus) => trackGridItemFocus(index, hasFocus),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
