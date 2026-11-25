part of '../media_detail_screen.dart';

/// The action row's trailing status: what Play will do with this item's
/// picture, audio, and subtitles, computed by the player's own selection
/// ladder ([previewPlaybackTracks]). Read-only — it describes the episode the
/// hero shows, and on TV that changes with rail focus, so there is no per-
/// episode target for a control here to act on.
extension _MediaDetailPlaybackTracksStatus on _MediaDetailScreenState {
  /// The item Play would start: the hero's episode for a show, the first
  /// episode for a season, the item itself otherwise. Null while a show has
  /// not resolved any episode yet.
  MediaItem? _playbackTargetItem(MediaItem metadata) {
    if (!_canUseDetail) return null;
    final MediaItem? target;
    if (metadata.isShow) {
      // Fork: without an on-deck episode, the first loaded one, so the track
      // menus show for a series that was never started too.
      target = _showPlayEpisode() ?? (_episodes.isEmpty ? null : _episodes.first);
    } else if (metadata.isSeason) {
      target = _episodes.isEmpty ? null : _episodes.first;
    } else {
      target = metadata;
    }
    return target;
  }

  Future<void> _listenForPlaybackVersionChanges() async {
    final settings = await SettingsService.getInstance();
    if (!_canUseDetail) return;
    bindListenable(settings.listenableOf(SettingsService.mediaVersionPreferences), _onPlaybackVersionChanged);
  }

  void _onPlaybackVersionChanged() {
    if (!_canUseDetail) return;
    _invalidatePlaybackProbes(refreshItems: false);
  }

  void _invalidatePlaybackProbes({required bool refreshItems}) {
    _playbackProbeGeneration++;
    _playbackProbeTimer?.cancel();
    _playbackProbeRequests.clear();
    _playbackSources.clear();
    if (refreshItems) _probedPlaybackItems.clear();
    _playbackStatusRevision.value++;
  }

  /// Fetch metadata once, then resolve the saved selection independently.
  /// Rendering never starts PlaybackInfo or a transcode. Offline only reads
  /// the completed download's identity, never a server or track probe.
  void _scheduleTargetProbe(BuildContext context, MediaItem target) {
    if (!_canUseDetail) return;
    final key = target.globalKey;
    if (_playbackSources.containsKey(key) || _playbackProbeRequests.containsKey(key)) return;
    final client = widget.isOffline ? null : _getMediaClientForMetadata(context);
    if (!widget.isOffline && client == null) return;
    final downloads = widget.isOffline ? context.read<DownloadProvider>() : null;
    _playbackProbeTimer?.cancel();
    final generation = _playbackProbeGeneration;
    _playbackProbeTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || generation != _playbackProbeGeneration || _playbackProbeRequests.containsKey(key)) return;
      unawaited(_probeTarget(client, downloads, target, generation));
    });
  }

  Future<void> _probeTarget(
    MediaServerClient? client,
    DownloadProvider? downloads,
    MediaItem target,
    int generation,
  ) async {
    final key = target.globalKey;
    final request = Object();
    _playbackProbeRequests[key] = request;
    bool current() => _canUseDetail && generation == _playbackProbeGeneration && _playbackProbeRequests[key] == request;
    try {
      MediaItem item;
      MediaSourceInfo? source;
      int? mediaIndex;
      if (downloads != null) {
        final downloaded = await downloads.getCompletedDownload(key);
        if (!current()) return;
        item = target;
        if (downloaded != null) {
          final versions = item.mediaVersions;
          final byId = downloaded.mediaSourceId == null
              ? -1
              : versions?.indexWhere((version) => version.id == downloaded.mediaSourceId) ?? -1;
          mediaIndex = byId >= 0 ? byId : downloaded.mediaIndex;
          if (versions == null || mediaIndex < 0 || mediaIndex >= versions.length) mediaIndex = null;
        }
      } else {
        final fetched = _probedPlaybackItems[key] ?? await client!.fetchItem(target.id);
        if (!current() || fetched == null) return;
        item = fetched.copyWith(
          serverId: target.serverId ?? fetched.serverId,
          serverName: target.serverName ?? fetched.serverName,
        );
        _probedPlaybackItems[key] = item;
        _recordProbedRatings(key, item.ratings);
        final selection = await resolveSavedMediaVersionFor(item);
        if (!current()) return;
        source = await client!.fetchCachedMediaSourceInfo(
          item.id,
          mediaIndex: selection?.index ?? 0,
          mediaSourceId: selection?.sourceId,
          preferredVersionSignature: selection?.signature,
        );
        if (!current() || source == null) return;
        mediaIndex = source.mediaIndex ?? selection?.index ?? 0;
      }
      if (!current()) return;
      _playbackSources[key] = (item: item, source: source, mediaIndex: mediaIndex);
      // Only the status repaints: do not rebuild the rail or replace its
      // focused item with a cached probe snapshot.
      _playbackStatusRevision.value++;
    } catch (e, stackTrace) {
      appLogger.d('Playback track probe failed for ${target.id}', error: e, stackTrace: stackTrace);
    } finally {
      if (_playbackProbeRequests[key] == request) _playbackProbeRequests.remove(key);
    }
  }

  /// Repaints the TV hero only when the scores are new for the episode it
  /// shows; a re-probe after a refresh returns the same scores.
  void _recordProbedRatings(String key, List<MediaRatingSource>? ratings) {
    if (ratings == null || ratings.isEmpty) return;
    final isNew = !_probedRatings.containsKey(key);
    _probedRatings[key] = ratings;
    if (isNew && _tvDetailFocusedEpisode.value?.globalKey == key) _focusedEpisodeRatingsRevision.value++;
  }

  /// The listener stays mounted while a source is resolving, without adding
  /// a semantic or focus target when there is nothing to predict.
  Widget _buildPlaybackTracksStatus(
    BuildContext context,
    MediaItem metadata, {
    required bool isTv,
    required double tvScale,
    required double maxWidth,
  }) {
    return ValueListenableBuilder<int>(
      valueListenable: _playbackStatusRevision,
      builder: (context, _, _) =>
          _playbackTracksStatus(context, metadata, isTv: isTv, tvScale: tvScale, maxWidth: maxWidth) ??
          const SizedBox.shrink(),
    );
  }

  Widget? _playbackTracksStatus(
    BuildContext context,
    MediaItem metadata, {
    required bool isTv,
    required double tvScale,
    required double maxWidth,
  }) {
    final target = _playbackTargetItem(metadata);
    if (target == null) return null;
    if (_playbackStatusTarget != target.globalKey) {
      _playbackStatusTarget = target.globalKey;
      final cached = _playbackSources[target.globalKey]?.source;
      if (!widget.isOffline && cached != null && !mediaSourceHasTrackRows(cached)) {
        _playbackSources.remove(target.globalKey);
      }
    }

    // Profile-scoped in the app; nullable so a bare detail screen (widget
    // tests) still previews with the ladder's non-profile tiers.
    final probed = _playbackSources[target.globalKey];
    final source = probed?.source;
    final preview = source == null
        ? null
        : previewPlaybackTracks(
            probed!.item,
            source,
            profile: context.watch<AccountPreferencesController?>()?.activePreferences,
          );
    final videoLabels = probed?.mediaIndex == null
        ? const <String>[]
        : buildMediaVideoLabels(probed!.item, versionIndex: probed.mediaIndex!, partIndex: source?.partIndex);
    if (probed == null) _scheduleTargetProbe(context, target);
    if (preview == null && videoLabels.isEmpty) return null;

    // Fork: the tracks picked on this page, else the player's own choice.
    final audioLabel = (_currentAudioRow(metadata) ?? preview?.audio)?.label;
    final subtitleLabel = _currentSubtitleRow(metadata, preview)?.label;
    final parts = <MetadataLinePart>[
      // Shed order on a tight row: the long codec details first (subtitle's,
      // then audio's — the details sheet has them in full), then the short
      // picture labels, then the audio track; the subtitle decision always
      // stays.
      for (final label in videoLabels) MetadataLineText(label, dropPriority: 2),
      if (audioLabel != null)
        MetadataLineIconText(
          Symbols.volume_up_rounded,
          audioLabel.primary,
          detail: audioLabel.secondary,
          dropPriority: 1,
          detailDropPriority: 3,
        ),
      if (preview != null)
        MetadataLineIconText(
          Symbols.subtitles_rounded,
          subtitleLabel?.primary ?? t.common.off,
          detail: subtitleLabel?.secondary,
          dropPriority: 0,
          detailDropPriority: 3,
        ),
    ];
    final semanticsLabel =
        '${t.videoControls.tracksButton}: ${[for (final part in parts) switch (part) {
            MetadataLineText(:final text) => text,
            MetadataLineIconText(:final text, :final detail) => detail == null ? text : '$text${MetadataLineIconText.detailSeparator}$detail',
            MetadataLineRatings() => '',
          }].join(', ')}';

    // Same ink as the hero's metadata line, one step lighter in weight and
    // size so it reads as a footnote to the buttons rather than a sixth one.
    final textStyle = TextStyle(
      color: isTv ? _tvDetailForegroundColor(context) : Theme.of(context).colorScheme.onSurface,
      fontSize: isTv ? 15 * tvScale : 12.5,
      fontWeight: .w600,
      letterSpacing: 0.1,
      height: 1.2,
    );

    return Semantics(
      key: const ValueKey('detail_playback_tracks'),
      label: semanticsLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: isTv
            // Fork: on a dark pill, so it stays readable over a bright backdrop.
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14 * tvScale, vertical: 6 * tvScale),
                  child: FittedMetadataLine(textStyle: textStyle, parts: parts, ratingIconSize: textStyle.fontSize! * 1.15),
                ),
              )
            : FittedMetadataLine(textStyle: textStyle, parts: parts, ratingIconSize: textStyle.fontSize! * 1.15),
      ),
    );
  }
}

/// Fork: audio and subtitle pickers under the hero. Built from the same
/// probed source as the status line; the picks are handed to the player when
/// Play starts this target.
extension _MediaDetailTrackPickers on _MediaDetailScreenState {
  ({String key, MediaItem item, MediaSourceInfo source})? _pickerSource(MediaItem metadata) {
    final target = _playbackTargetItem(metadata);
    if (target == null) return null;
    final probed = _playbackSources[target.globalKey];
    final source = probed?.source;
    if (probed == null || source == null) return null;
    return (key: target.globalKey, item: probed.item, source: source);
  }

  PlaybackTrackPreview? _pickerPreview(({String key, MediaItem item, MediaSourceInfo source}) entry) =>
      previewPlaybackTracks(
        entry.item,
        entry.source,
        profile: context.read<AccountPreferencesController?>()?.activePreferences,
      );

  /// [picked] in this source: the same row, else the one with the same
  /// language and title (another episode's file).
  static T? _matchRow<T>(
    List<T> rows,
    T picked, {
    required int Function(T) id,
    required String? Function(T) language,
    required String? Function(T) title,
  }) {
    final same = rows.where((r) => id(r) == id(picked)).firstOrNull;
    if (same != null) return same;
    final lang = language(picked);
    final byBoth = rows.where((r) => language(r) == lang && title(r) == title(picked)).firstOrNull;
    return byBoth ?? rows.where((r) => language(r) == lang).firstOrNull;
  }

  MediaAudioTrack? _matchAudio(MediaSourceInfo source, MediaAudioTrack picked) => _matchRow<MediaAudioTrack>(
    source.audioTracks,
    picked,
    id: (r) => r.id,
    language: (r) => r.languageCode ?? r.language,
    title: (r) => r.title,
  );

  MediaSubtitleTrack? _matchSubtitle(MediaSourceInfo source, MediaSubtitleTrack picked) =>
      _matchRow<MediaSubtitleTrack>(
        source.subtitleTracks,
        picked,
        id: (r) => r.id,
        language: (r) => r.languageCode ?? r.language,
        title: (r) => r.title,
      );

  /// The audio row Play will use: the picked one, else the ladder's choice.
  MediaAudioTrack? _currentAudioRow(MediaItem metadata) {
    final entry = _pickerSource(metadata);
    if (entry == null) return null;
    final picked = _pickedAudioRows[metadata.globalKey];
    if (picked != null) return _matchAudio(entry.source, picked) ?? picked;
    return _pickerPreview(entry)?.audio;
  }

  /// The subtitle row Play will use; null is off.
  MediaSubtitleTrack? _currentSubtitleRow(MediaItem metadata, PlaybackTrackPreview? preview) {
    final entry = _pickerSource(metadata);
    if (entry == null) return null;
    if (!_pickedSubtitleRows.containsKey(metadata.globalKey)) return preview?.subtitle;
    final picked = _pickedSubtitleRows[metadata.globalKey];
    return picked == null ? null : _matchSubtitle(entry.source, picked) ?? picked;
  }

  AudioTrack? _pickedAudioTrack(MediaItem metadata) {
    final picked = _pickedAudioRows[metadata.globalKey];
    if (picked == null) return null;
    final entry = _pickerSource(metadata);
    final row = entry == null ? picked : _matchAudio(entry.source, picked) ?? picked;
    // Matched by language and title in the player, so it fits any episode.
    return itemAgnosticAudioCarry(PlaybackSubtitleResolver.audioTrackForSource(row));
  }

  SubtitleTrack? _pickedSubtitleTrack(MediaItem metadata) {
    if (!_pickedSubtitleRows.containsKey(metadata.globalKey)) return null;
    final picked = _pickedSubtitleRows[metadata.globalKey];
    if (picked == null) return SubtitleTrack.off;
    final entry = _pickerSource(metadata);
    final row = entry == null ? null : _matchSubtitle(entry.source, picked);
    if (row != null) return PlaybackSubtitleResolver.subtitleTrackForSource(row);
    // Not in the file Play starts: hand over language and title only.
    return PlaybackSubtitleResolver.subtitleTrackForSource(picked).copyWith(id: 'carried', uri: null);
  }

  void _pickAudioRow(MediaItem metadata, MediaAudioTrack row) {
    _setDetailState(() {
      _pickedAudioRows[metadata.globalKey] = row;
      _tvDetailActorItemsCache = null;
    });
    _playbackStatusRevision.value++;
  }

  void _pickSubtitleRow(MediaItem metadata, MediaSubtitleTrack? row) {
    _setDetailState(() => _pickedSubtitleRows[metadata.globalKey] = row);
    _playbackStatusRevision.value++;
  }

  /// TV: the same choices as dialogs from the action row.
  Future<void> _showAudioPickerDialog(BuildContext context, MediaItem metadata) async {
    final entry = _pickerSource(metadata);
    if (entry == null || entry.source.audioTracks.isEmpty) return;
    final current = _currentAudioRow(metadata);
    final picked = await showOptionPickerDialog<int>(
      context,
      title: RetroStrings.audioTrack,
      options: [
        for (final track in entry.source.audioTracks)
          (
            icon: track.id == current?.id ? Symbols.check_rounded : null,
            label: track.label.joined,
            value: track.id,
          ),
      ],
    );
    if (picked == null || !_canUseDetail) return;
    final row = entry.source.audioTracks.where((track) => track.id == picked).firstOrNull;
    if (row != null) _pickAudioRow(metadata, row);
  }

  Future<void> _showSubtitlePickerDialog(BuildContext context, MediaItem metadata) async {
    final entry = _pickerSource(metadata);
    if (entry == null) return;
    final current = _currentSubtitleRow(metadata, _pickerPreview(entry));
    final picked = await showOptionPickerDialog<int>(
      context,
      title: RetroStrings.subtitleTrack,
      options: [
        (icon: current == null ? Symbols.check_rounded : null, label: t.common.off, value: -1),
        for (final track in entry.source.subtitleTracks)
          (
            icon: track.id == current?.id ? Symbols.check_rounded : null,
            label: track.label.joined,
            value: track.id,
          ),
      ],
    );
    if (picked == null || !_canUseDetail) return;
    _pickSubtitleRow(metadata, picked < 0 ? null : entry.source.subtitleTracks.where((track) => track.id == picked).firstOrNull);
  }

  Widget _buildTrackPickers(BuildContext context, MediaItem metadata) {
    return ValueListenableBuilder<int>(
      valueListenable: _playbackStatusRevision,
      builder: (context, _, _) {
        final target = _playbackTargetItem(metadata);
        if (target != null && !_playbackSources.containsKey(target.globalKey)) {
          _scheduleTargetProbe(context, target);
        }
        final entry = _pickerSource(metadata);
        if (entry == null) return const SizedBox.shrink();
        final source = entry.source;
        if (source.audioTracks.isEmpty && source.subtitleTracks.isEmpty) return const SizedBox.shrink();
        final preview = _pickerPreview(entry);
        final audio = _currentAudioRow(metadata);
        final subtitle = _currentSubtitleRow(metadata, preview);

        void pickAudio(int id) {
          final row = source.audioTracks.where((track) => track.id == id).firstOrNull;
          if (row != null) _pickAudioRow(metadata, row);
        }

        void pickSubtitle(int id) =>
            _pickSubtitleRow(metadata, id < 0 ? null : source.subtitleTracks.where((track) => track.id == id).firstOrNull);

        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (source.audioTracks.isNotEmpty)
                _TrackPickerButton<int>(
                  icon: Symbols.volume_up_rounded,
                  tooltip: RetroStrings.audioTrack,
                  label: audio?.label.joined ?? RetroStrings.audioTrack,
                  selected: audio?.id,
                  options: [
                    for (final track in source.audioTracks)
                      (value: track.id, label: track.label.primary, detail: track.label.secondary),
                  ],
                  onSelected: pickAudio,
                ),
              if (source.subtitleTracks.isNotEmpty)
                _TrackPickerButton<int>(
                  icon: Symbols.subtitles_rounded,
                  tooltip: RetroStrings.subtitleTrack,
                  label: subtitle?.label.joined ?? t.common.off,
                  selected: subtitle?.id ?? -1,
                  options: [
                    (value: -1, label: t.common.off, detail: null),
                    for (final track in source.subtitleTracks)
                      (value: track.id, label: track.label.primary, detail: track.label.secondary),
                  ],
                  onSelected: pickSubtitle,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A pill showing the current track; opens a menu of every track with its
/// details.
class _TrackPickerButton<T> extends StatelessWidget {
  const _TrackPickerButton({
    required this.icon,
    required this.tooltip,
    required this.label,
    required this.selected,
    required this.options,
    required this.onSelected,
  });

  final IconData icon;
  final String tooltip;
  final String label;
  final T? selected;
  final List<({T value, String label, String? detail})> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<T>(
      tooltip: tooltip,
      initialValue: selected,
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 520),
      itemBuilder: (context) => [
        for (final o in options)
          CheckedPopupMenuItem<T>(
            value: o.value,
            checked: o.value == selected,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(o.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (o.detail != null)
                  Text(o.detail!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, fill: 1, size: 18, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 4),
            AppIcon(Symbols.arrow_drop_down_rounded, size: 20, color: scheme.onSecondaryContainer),
          ],
        ),
      ),
    );
  }
}
