import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focus_theme.dart';
import '../../focus/focusable_action_bar.dart';
import '../../focus/input_mode_tracker.dart';
import '../../focus/key_event_utils.dart';
import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../mixins/grid_focus_node_mixin.dart';
import '../../models/download_models.dart';
import '../../providers/download_provider.dart';
import '../../services/music/music_playback_service.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/app_logger.dart';
import '../../utils/dialogs.dart';
import '../../utils/formatters.dart';
import '../../utils/media_image_helper.dart';
import '../../utils/music_navigation.dart';
import '../../utils/platform_detector.dart';
import '../../utils/provider_extensions.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/background_download_warning_banner.dart';
import '../../widgets/desktop_app_bar.dart';
import '../../widgets/download_status_icon.dart';
import '../../widgets/media_context_menu.dart';
import '../../widgets/music/mini_player.dart';
import '../../widgets/music/music_detail_header.dart';
import '../../widgets/music/music_actions.dart';
import '../../widgets/music/track_row.dart';
import '../../widgets/optimized_media_image.dart';
import '../base_media_list_detail_screen.dart';
import '../focusable_detail_screen_mixin.dart';
import '../../utils/error_message_utils.dart';
import '../../i18n/retro_strings.dart';
import '../../services/retrowave/audio/audio_extras.dart';
import '../../services/retrowave/audio/audio_settings.dart';
import '../../services/settings_service.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/overlay_sheet.dart';

/// Detail screen for a music album: square cover header, Play/Shuffle/
/// Instant Mix action row, and the track list rendered as grouped
/// [TrackRow] cards with per-disc headers on multi-disc albums.
class AlbumDetailScreen extends StatefulWidget {
  final MediaItem album;

  /// Offline mode: the track list comes from [DownloadProvider] instead of
  /// the server — the entry point for downloaded albums.
  final bool isOffline;

  const AlbumDetailScreen({super.key, required this.album, this.isOffline = false});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

/// A row of the track list: either a disc header ([discNumber] non-null) or
/// the track at [trackIndex]. [isFirst]/[isLast] mark the track's position
/// within its disc group for the grouped-card corner radii.
class _TrackListEntry {
  final int? discNumber;
  final int? trackIndex;
  final bool isFirst;
  final bool isLast;

  const _TrackListEntry.header(int this.discNumber) : trackIndex = null, isFirst = false, isLast = false;

  const _TrackListEntry.track(int this.trackIndex, {required this.isFirst, required this.isLast}) : discNumber = null;
}

class _AlbumDetailScreenState extends BaseMediaListDetailScreen<AlbumDetailScreen>
    with
        GridFocusNodeMixin<AlbumDetailScreen>,
        FocusableDetailScreenMixin<AlbumDetailScreen>,
        StandardItemLoader<AlbumDetailScreen> {
  final GlobalKey<MediaContextMenuState> _contextMenuKey = GlobalKey<MediaContextMenuState>();

  @override
  Object get mediaItem => widget.album;

  @override
  String get title => widget.album.displayTitle;

  @override
  String get emptyMessage => t.messages.noItemsAvailable;

  @override
  bool get hasItems => items.isNotEmpty;

  @override
  Future<List<MediaItem>> fetchItems() async {
    final fetched = await (widget.isOffline
        ? Future.value(context.read<DownloadProvider>().getDownloadedTracksForAlbum(widget.album.globalKey))
        : mediaClient.fetchAlbumTracks(widget.album.id));
    // Fork: tracks carry the album's library (Jellyfin leaves it out), so
    // the library type applies when they play.
    final libraryId = widget.album.libraryId;
    final tracks = libraryId == null
        ? fetched
        : [for (final t in fetched) t.libraryId == null ? t.copyWith(libraryId: libraryId) : t];
    // Fork: the chosen order (podcasts: newest first unless changed).
    _serverOrder = tracks;
    return AudioSorting.sortTracks(tracks, _sortFor(_modeFor(tracks)));
  }

  /// Tracks in the server's order, for "Track order".
  List<MediaItem> _serverOrder = const [];

  AudioTrackSort _sortFor(AudioMode mode) => SettingsService.instance.read(AudioSorting.trackPrefFor(mode));

  Future<void> _pickSort() async {
    final pref = AudioSorting.trackPrefFor(_mode);
    final current = SettingsService.instance.read(pref);
    final picked = await OverlaySheetController.showAdaptive<AudioTrackSort>(
      context,
      showDragHandle: true,
      builder: (context) => AppMenuSheet<AudioTrackSort>(
        title: RetroStrings.audioSortBy,
        entries: [
          for (final s in AudioTrackSort.values)
            AppMenuItem(value: s, label: RetroStrings.audioTrackSort(s), selected: s == current),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await SettingsService.instance.write(pref, picked);
    if (mounted) setState(() => items = AudioSorting.sortTracks(_serverOrder, picked));
  }

  /// Fork: the library type (music, audiobooks, audio dramas, podcasts).
  AudioMode _modeFor(List<MediaItem> tracks) {
    final album = widget.album;
    final libraryId = album.libraryId ?? tracks.firstOrNull?.libraryId;
    return AudioSettings.modeForLibrary(album.serverId, libraryId);
  }

  AudioMode get _mode => _modeFor(items);

  /// Fork: where a book stopped, with the time left and a restart button.
  Widget _bookProgress() {
    return ListenableBuilder(
      listenable: AudioExtras.instance,
      builder: (context, _) {
        final resume = AudioExtras.instance.resumeOf(widget.album.serverId, widget.album.id);
        if (resume == null || items.isEmpty) return const SizedBox.shrink();
        final ordered = _serverOrder.isEmpty ? items : _serverOrder;
        final index = ordered.indexWhere((t) => t.id == resume.trackId);
        if (index < 0) return const SizedBox.shrink();
        final total = _totalDurationMs;
        var done = resume.position.inMilliseconds;
        for (var i = 0; i < index; i++) {
          done += ordered[i].durationMs ?? 0;
        }
        final left = (total - done).clamp(0, total);
        final tk = tokens(context);
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: total > 0 ? done / total : 0, minHeight: 5),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: .min,
                children: [
                  Text(
                    RetroStrings.audioTimeLeft(formatDurationTextual(left)),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tk.textMuted),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () =>
                        unawaited(AudioExtras.instance.clearResume(widget.album.serverId ?? '', widget.album.id)),
                    child: Text(RetroStrings.audioRestartBook),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Future<void> loadItems() async {
    await super.loadItems();
    autoFocusFirstItemAfterLoad();
  }

  @override
  void dispose() {
    disposeFocusResources();
    super.dispose();
  }

  MusicPlayContext get _playContext =>
      MusicPlayContext(title: widget.album.displayTitle, kind: MusicPlayContextKind.album);

  /// Plays the already-fetched track list — no extra server round-trip.
  Future<void> _playAll({bool shuffle = false}) async {
    if (items.isEmpty) {
      showAppSnackBar(context, emptyMessage);
      return;
    }
    await playTracks(context, tracks: items, playContext: _playContext, shuffle: shuffle);
  }

  Future<void> _openArtist() async {
    final parentId = widget.album.parentId;
    if (parentId == null) return;
    // Offline (or a vanished server) there is no client to resolve the artist.
    final client = context.tryGetMediaClientWithFallback(serverIdOrNull(widget.album.serverId));
    if (client == null) return;
    await openArtistById(context, client, parentId);
  }

  void _showOverflowMenuAt(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject() as RenderBox?;
    Offset? position;
    if (box != null) position = box.localToGlobal(box.size.center(Offset.zero));
    _contextMenuKey.currentState?.showContextMenu(buttonContext, position: position);
  }

  /// Album ⋮ — opens the item's standard context menu (Instant Mix, Go to
  /// artist, Mark played/unplayed…), same pattern as the media detail row.
  FocusableAction _overflowAction() {
    return FocusableAction(
      debugLabel: 'album_more',
      onPressed: () => _contextMenuKey.currentState?.showContextMenu(context),
      builder: (context, state) => MediaContextMenu(
        key: _contextMenuKey,
        item: widget.album,
        child: Builder(
          builder: (buttonContext) => Container(
            decoration: FocusTheme.focusBackgroundDecoration(
              buttonContext,
              isFocused: state.showFocus,
              borderRadius: 20,
            ),
            child: IconButton(
              icon: const AppIcon(Symbols.more_vert_rounded, fill: 1),
              onPressed: () => _showOverflowMenuAt(buttonContext),
            ),
          ),
        ),
      ),
    );
  }

  /// Queue the album (expands to its tracks) or, when fully downloaded,
  /// offer deletion. Queued/downloading states are inert — the button just
  /// reflects progress.
  Future<void> _handleDownloadPressed() async {
    final downloadProvider = context.read<DownloadProvider>();
    final globalKey = widget.album.globalKey;
    final progress = downloadProvider.getProgress(globalKey);

    if (downloadProvider.isQueueing(globalKey) ||
        progress?.status == DownloadStatus.queued ||
        progress?.status == DownloadStatus.downloading) {
      return;
    }

    if (downloadProvider.isDownloaded(globalKey)) {
      final confirmed = await showDeleteConfirmation(
        context,
        title: t.downloads.deleteDownload,
        message: t.downloads.deleteConfirm(title: widget.album.displayTitle),
      );
      if (!confirmed || !mounted) return;
      await downloadProvider.deleteDownload(globalKey);
      if (mounted) showSuccessSnackBar(context, t.downloads.downloadDeleted);
      return;
    }

    if (!await confirmBackgroundDownloadRestrictions(context) || !mounted) return;

    // Not downloaded (or partial/failed): queue the album — already-active
    // tracks are skipped inside the provider, so this also fills gaps.
    try {
      final count = await downloadProvider.queueDownload(widget.album, mediaClient);
      if (!mounted) return;
      showSuccessSnackBar(context, count > 1 ? t.downloads.tracksQueued(count: count) : t.downloads.downloadQueued);
    } on CellularDownloadBlockedException {
      if (mounted) showErrorSnackBar(context, t.settings.cellularDownloadBlocked);
    } catch (e) {
      appLogger.e('Failed to queue album download', error: e);
      if (mounted) showErrorSnackBar(context, t.messages.errorLoading(error: localizedErrorReason(e)));
    }
  }

  /// Album download button — mirrors the media-detail download action's
  /// states in compact form. Hidden on Apple TV (no user-accessible storage)
  /// and when no [DownloadProvider] is in scope.
  FocusableAction? _downloadAction() {
    if (PlatformDetector.isAppleTV()) return null;
    if (widget.album.serverId == null || context.read<DownloadProvider?>() == null) return null;

    return FocusableAction(
      debugLabel: 'album_download',
      onPressed: () => unawaited(_handleDownloadPressed()),
      builder: (context, state) => Consumer<DownloadProvider>(
        builder: (context, downloadProvider, _) {
          final globalKey = widget.album.globalKey;
          final progress = downloadProvider.getProgress(globalKey);
          final isQueueing = downloadProvider.isQueueing(globalKey);
          final status = progress?.status;

          final Widget icon;
          final String tooltip;
          if (isQueueing) {
            icon = const DownloadQueueingSpinner(size: 20);
            tooltip = t.downloads.downloadingTooltip;
          } else if (status == DownloadStatus.queued) {
            icon = const AppIcon(Symbols.schedule_rounded, fill: 1);
            tooltip = t.downloads.queuedTooltip;
          } else if (status == DownloadStatus.downloading) {
            icon = DownloadStatusIcon(
              status: DownloadStatus.downloading,
              size: 20,
              progress: progress?.progressPercent,
            );
            tooltip = t.downloads.downloadingTooltip;
          } else if (status == DownloadStatus.completed) {
            icon = const AppIcon(Symbols.download_done_rounded, fill: 1);
            tooltip = t.downloads.deleteDownload;
          } else if (status == DownloadStatus.partial) {
            icon = const AppIcon(Symbols.downloading_rounded, fill: 1);
            tooltip = t.downloads.partialDownloadClickToComplete;
          } else {
            icon = const AppIcon(Symbols.download_rounded, fill: 1);
            tooltip = t.downloads.downloadNow;
          }

          return Container(
            decoration: FocusTheme.focusBackgroundDecoration(context, isFocused: state.showFocus, borderRadius: 20),
            child: IconButton(icon: icon, tooltip: tooltip, onPressed: () => unawaited(_handleDownloadPressed())),
          );
        },
      ),
    );
  }

  @override
  List<FocusableAction> getAppBarActions() {
    final client = context.tryGetMediaClientWithFallback(serverIdOrNull(widget.album.serverId));
    return buildMusicActions(
      onPlay: () => unawaited(_playAll()),
      onShuffle: () => unawaited(_playAll(shuffle: true)),
      onInstantMix: (client?.capabilities.instantMix ?? false)
          ? () => unawaited(playInstantMix(context, widget.album))
          : null,
      download: _downloadAction(),
      trailing: _overflowAction(),
    )..insert(
      2,
      FocusableAction(
        debugLabel: 'album_sort',
        icon: Symbols.sort_rounded,
        tooltip: RetroStrings.audioSortBy,
        onPressed: () => unawaited(_pickSort()),
      ),
    );
  }

  int get _totalDurationMs => items.fold(0, (sum, item) => sum + (item.durationMs ?? 0));

  Widget _buildHeader() {
    final tk = tokens(context);
    final textTheme = Theme.of(context).textTheme;
    final client = context.tryGetMediaClientWithFallback(serverIdOrNull(widget.album.serverId));
    final artistName = widget.album.albumArtistTitle;

    final metaParts = <String>[
      if (widget.album.year != null) '${widget.album.year}',
      if (items.isNotEmpty) t.music.trackCount(n: items.length),
      if (_totalDurationMs > 0) formatDurationTextual(_totalDurationMs),
    ];

    Widget cover(double size) => ClipRRect(
      borderRadius: BorderRadius.circular(tk.radiusLg),
      child: OptimizedMediaImage(
        client: client,
        imagePath: widget.album.thumbPath,
        imageType: ImageType.square,
        width: size,
        height: size,
        fallbackIcon: Symbols.album_rounded,
      ),
    );

    Widget info({required bool centered}) => Column(
      mainAxisSize: .min,
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          widget.album.displayTitle,
          style: textTheme.titleLarge,
          textAlign: centered ? TextAlign.center : TextAlign.start,
        ),
        if (artistName != null && artistName.isNotEmpty) ...[
          const SizedBox(height: 4),
          _ArtistLink(name: artistName, onTap: widget.album.parentId == null ? null : () => unawaited(_openArtist())),
        ],
        if (metaParts.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(toBulletedString(metaParts), style: textTheme.bodyMedium?.copyWith(color: tk.textMuted)),
        ],
        if (_mode.isBookLike) _bookProgress(),
      ],
    );

    final actionRow = FocusableActionBar(
      key: actionBarKey,
      spacing: 4,
      actions: getAppBarActions(),
      onNavigateDown: navigateToGrid,
      onBack: () => Navigator.pop(context),
    );

    return MusicDetailHeader(
      artworkBuilder: cover,
      infoBuilder: info,
      actionBar: actionRow,
      compactArtworkSize: 200,
      compactArtworkSpacing: 16,
      wideAlignment: CrossAxisAlignment.end,
    );
  }

  /// Flattens tracks into list rows, inserting disc headers when the album
  /// spans multiple discs. Tracks arrive in disc/track order from both
  /// backends, so grouping is a single pass.
  List<_TrackListEntry> _rowModels() {
    final multiDisc =
        _sortFor(_mode) == AudioTrackSort.trackOrder && items.map((item) => item.discNumber ?? 1).toSet().length > 1;
    final rows = <_TrackListEntry>[];
    for (var i = 0; i < items.length; i++) {
      final disc = items[i].discNumber ?? 1;
      final previousDisc = i > 0 ? (items[i - 1].discNumber ?? 1) : null;
      final nextDisc = i < items.length - 1 ? (items[i + 1].discNumber ?? 1) : null;
      if (multiDisc && disc != previousDisc) rows.add(_TrackListEntry.header(disc));
      rows.add(
        _TrackListEntry.track(
          i,
          isFirst: multiDisc ? disc != previousDisc : i == 0,
          isLast: multiDisc ? disc != nextDisc : i == items.length - 1,
        ),
      );
    }
    return rows;
  }

  Widget _buildTrackList() {
    final tk = tokens(context);
    final rows = _rowModels();
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      sliver: SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          final disc = row.discNumber;
          if (disc != null) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, index == 0 ? 0 : 16, 16, 8),
              child: Text(
                t.music.discNumber(n: disc),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: tk.textMuted, fontWeight: .w600),
              ),
            );
          }
          final trackIndex = row.trackIndex!;
          final item = items[trackIndex];
          final trackRow = Padding(
            padding: EdgeInsets.only(top: row.isFirst ? 0 : tk.groupGap),
            child: TrackRow(
              key: ValueKey(item.id),
              item: item,
              isFirst: row.isFirst,
              isLast: row.isLast,
              showDownloadStatus: true,
              focusNode: focusNodeForIndex(trackIndex, firstItemFocusNode, prefix: 'detail_grid_item'),
              onNavigateUp: trackIndex == 0 ? navigateToAppBar : null,
              onBack: handleBackFromContent,
              onFocusChange: (hasFocus) => trackGridItemFocus(trackIndex, hasFocus),
              onRefresh: updateItem,
              onTap: () => unawaited(playTracks(context, tracks: items, startTrack: item, playContext: _playContext)),
            ),
          );
          // Fork: played podcast episodes are dimmed.
          if (_mode != AudioMode.podcast) return trackRow;
          return ListenableBuilder(
            listenable: AudioExtras.instance,
            builder: (context, child) =>
                Opacity(opacity: AudioExtras.instance.isPlayed(item) ? 0.5 : 1, child: child),
            child: trackRow,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return buildDetailScaffold(
      slivers: [
        CustomAppBar(title: Text(widget.album.displayTitle), onBackPressed: popFromAppBar),
        SliverToBoxAdapter(child: _buildHeader()),
        ...buildStateSlivers(),
        if (hasItems) _buildTrackList(),
        // Keep the last rows reachable above the floating mini-player.
        SliverToBoxAdapter(child: SizedBox(height: context.watch<MiniPlayerInsetController?>()?.overlayHeight ?? 0)),
      ],
    );
  }
}

/// Tappable, focusable artist line under the album title. Focus renders as a
/// background fill (never an outline); SELECT activates like a tap.
class _ArtistLink extends StatefulWidget {
  final String name;
  final VoidCallback? onTap;

  const _ArtistLink({required this.name, this.onTap});

  @override
  State<_ArtistLink> createState() => _ArtistLinkState();
}

class _ArtistLinkState extends State<_ArtistLink> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'album_artist_link');
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: .w500);
    if (widget.onTap == null) return Text(widget.name, style: style);

    final showFocus = _focused && InputModeTracker.isKeyboardMode(context);
    return Semantics(
      button: true,
      enabled: true,
      label: widget.name,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: Focus(
          focusNode: _focusNode,
          onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
          onKeyEvent: dpadKeyHandler(onSelect: widget.onTap),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: FocusTheme.getAnimationDuration(context),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: FocusTheme.focusBackgroundDecoration(context, isFocused: showFocus),
                child: Text(widget.name, style: style),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
