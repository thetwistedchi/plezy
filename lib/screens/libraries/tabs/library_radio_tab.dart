import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../i18n/retro_strings.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../mixins/grid_focus_node_mixin.dart';
import '../../../mixins/library_tab_focus_mixin.dart';
import '../../../services/music/music_playback_service.dart';
import '../../../services/plex_client.dart';
import '../../../utils/layout_constants.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/nested_tab_scrollbar.dart';
import 'base_library_tab.dart';

/// Fork: Plex radio stations of a music library (Library radio, Time travel
/// radio, Deep cuts…). A station plays as a queue of up to 100 tracks.
class LibraryRadioTab extends BaseLibraryTab<MediaItem> {
  const LibraryRadioTab({
    super.key,
    required super.library,
    super.onDataLoaded,
    super.isActive,
    super.suppressAutoFocus,
    super.onBack,
  });

  @override
  State<LibraryRadioTab> createState() => _LibraryRadioTabState();
}

class _LibraryRadioTabState extends BaseLibraryTabState<MediaItem, LibraryRadioTab>
    with GridFocusNodeMixin, LibraryTabFocusMixin {
  @override
  String get focusNodeDebugLabel => 'radio_first_item';

  @override
  int get itemCount => items.length;

  @override
  IconData get emptyIcon => Symbols.radio_rounded;

  @override
  String get emptyMessage => RetroStrings.audioNoStations;

  @override
  String get errorContext => RetroStrings.audioStations;

  @override
  Future<void> loadItems() async {
    await runLoadTransaction(() async {
      final client = getMediaClientForLibrary();
      if (client is! PlexClient) return const <MediaItem>[];
      final stations = await client.fetchMusicStations(widget.library.id);
      return [
        for (final s in stations)
          MediaItem(
            id: s.key,
            backend: widget.library.backend,
            kind: MediaKind.playlist,
            title: s.title,
            summary: s.summary,
            serverId: widget.library.serverId,
          ),
      ];
    });
  }

  Future<void> _play(MediaItem station) async {
    final client = getMediaClientForLibrary();
    if (client is! PlexClient) return;
    try {
      final tracks = await client.fetchStationTracks(station.id);
      if (!mounted) return;
      if (tracks.isEmpty) {
        showErrorSnackBar(context, t.music.instantMixEmpty);
        return;
      }
      await context.read<MusicPlaybackService>().playFromList(
        tracks: tracks,
        playContext: MusicPlayContext(title: station.title ?? '', kind: MusicPlayContextKind.mix),
      );
    } catch (e) {
      if (mounted) showErrorSnackBar(context, t.music.instantMixFailed);
    }
  }

  @override
  void dispose() {
    disposeGridFocusNodes();
    super.dispose();
  }

  @override
  Widget buildContent(List<MediaItem> items) {
    final base = GridLayoutConstants.gridPadding;
    return NestedTabScrollbar(
      child: CustomScrollView(
        slivers: [
          SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
          SliverPadding(
            padding: base,
            sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final station = items[index];
                return ListTile(
                  focusNode: index == 0
                      ? firstItemFocusNode
                      : getGridItemFocusNode(index, debugLabel: 'radio_item_$index'),
                  leading: const AppIcon(Symbols.radio_rounded, fill: 1),
                  title: Text(station.title ?? ''),
                  subtitle: (station.summary ?? '').isEmpty ? null : Text(station.summary!, maxLines: 2),
                  trailing: const AppIcon(Symbols.play_arrow_rounded, fill: 1),
                  onTap: () => unawaited(_play(station)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
