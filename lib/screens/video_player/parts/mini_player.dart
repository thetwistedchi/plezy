part of '../../video_player_screen.dart';

/// Minimizing into the bottom bar: the route stays where it is and keeps
/// playing; it only stops covering the pages ([MinimizableRoute]) and the
/// native video moves into the bar.
extension _VideoPlayerMiniMethods on VideoPlayerScreenState {
  /// Not on macOS yet: its video layer is untested with the bar.
  bool get _canMinimize =>
      PlatformDetector.isDesktopOS() &&
      !Platform.isMacOS &&
      !PlatformDetector.isTV() &&
      ModalRoute.of(context) is MinimizableRoute;

  void _minimizePlayer() {
    final route = ModalRoute.of(context);
    if (route is! MinimizableRoute || _minimized || player == null || !_isPlayerInitialized) return;
    if (FullscreenStateManager().isFullscreen) unawaited(FullscreenStateManager().exitFullscreen());
    final session = _miniSession ??= _PlexMiniSession(this);
    FocusManager.instance.primaryFocus?.unfocus();
    _setPlayerState(() => _minimized = true);
    route.minimized = true;
    VideoMiniPlayer.instance.show(session);
  }

  /// Header title links: minimizes into the bar and opens the series (for an
  /// episode, landing on its season and episode) or the playing item itself.
  Future<void> _openDetailsFromPlayer({required bool series}) async {
    if (!_canMinimize) return;
    final item = _currentMetadata;
    final serverId = serverIdOrNull(item.serverId);
    final client = serverId == null ? null : context.tryGetMediaClientForServer(serverId);
    if (client == null) return;
    _minimizePlayer();
    try {
      final seriesId = item.isEpisode ? item.grandparentId : (item.isSeason ? item.parentId : null);
      if (series && seriesId != null) {
        final show = await client.fetchItem(seriesId);
        if (show == null || !mounted) return;
        final target = mediaDetailNavigationTargetFor(item, metadataOverride: show);
        await Navigator.of(context).push(
          mediaDetailRoute(
            metadata: target.metadata,
            initialSeasonIndex: target.initialSeasonIndex,
            initialSeasonId: target.initialSeasonId,
            initialEpisodeId: target.initialEpisodeId,
          ),
        );
      } else {
        if (!mounted) return;
        await navigateToMediaItemDetails(context, item);
      }
    } catch (e, st) {
      appLogger.w('Could not open details from the player', error: e, stackTrace: st);
    }
  }

  void _expandPlayer() {
    if (!mounted || !_minimized) return;
    final route = ModalRoute.of(context);
    if (route is MinimizableRoute) {
      // Pages opened while minimized sit above the player: close them.
      if (!route.isTopRoute) Navigator.of(context).popUntil((r) => r == route);
      route.minimized = false;
    }
    _setPlayerState(() => _minimized = false);
    final session = _miniSession;
    if (session != null) VideoMiniPlayer.instance.clear(session);
    _screenFocusNode.requestFocus();
  }

  /// Back from the viewer (Back key, Escape, the back arrow): minimizes when
  /// [SettingsService.backMinimizesPlayer] is on, otherwise closes.
  Future<void> _handleUserBack() async {
    final minimize = SettingsService.instanceOrNull?.read(SettingsService.backMinimizesPlayer) ?? true;
    if (minimize &&
        !_minimized &&
        _canMinimize &&
        _isPlayerInitialized &&
        player != null &&
        _playbackFailureMessage == null) {
      _minimizePlayer();
      return;
    }
    await _handleBackButton();
  }

  void _stopMinimized() {
    if (!mounted) return;
    unawaited(_exitPlayerRoute(navigateHome: false, stop: true, allowCovered: true));
  }

  /// Called from dispose: the bar goes with the player.
  void _releaseMiniPlayer() {
    final session = _miniSession;
    if (session != null) VideoMiniPlayer.instance.clear(session);
  }
}

class _PlexMiniSession implements VideoMiniSession {
  _PlexMiniSession(this._screen);

  final VideoPlayerScreenState _screen;

  @override
  String get kind => 'plex';

  @override
  bool get hasSystemMediaControls => true;

  @override
  String get title {
    if (_screen.widget.isLive) return _screen._live.channelName ?? _screen._currentMetadata.displayTitle;
    return _screen._currentMetadata.displayTitle;
  }

  @override
  String? get subtitle => _screen.widget.isLive ? _screen._currentMetadata.title : _screen._currentMetadata.displaySubtitle;

  @override
  bool get isPlaying => _screen.player?.state.playing ?? false;

  @override
  Duration get position => _screen.player?.state.position ?? Duration.zero;

  @override
  Duration get duration => _screen.widget.isLive ? Duration.zero : (_screen.player?.state.duration ?? Duration.zero);

  @override
  bool get canNext => _screen.mounted && _screen._hasNextItem && !_screen._episode.isLoadingNext;

  @override
  double get volume => ((_screen._volumeController?.value ?? 100) / 100).clamp(0.0, 1.0);

  @override
  void togglePlay() {
    if (!_screen.mounted) return;
    unawaited(_screen._handleControlsTransport(TransportCommand.toggle));
  }

  @override
  void seekBy(Duration delta) {
    if (!_screen.mounted || _screen.widget.isLive) return;
    final p = _screen.player;
    if (p == null) return;
    var target = p.state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    final total = p.state.duration;
    if (total > Duration.zero && target > total) target = total;
    unawaited(_screen._seekPlayback(target));
  }

  @override
  void next() {
    if (!canNext) return;
    unawaited(_screen._navigateToNextItem());
  }

  @override
  void setVolume(double volume) => _screen._volumeController?.commit(volume.clamp(0.0, 1.0) * 100);

  @override
  void placeVideo({required int left, required int top, required int right, required int bottom, required double dpr}) {
    final p = _screen.player;
    if (p is! VideoRectSupport) return;
    unawaited(
      (p as VideoRectSupport)
          .setVideoRect(left: left, top: top, right: right, bottom: bottom, devicePixelRatio: dpr)
          .catchError((Object e) => appLogger.d('Mini player video rect failed: $e')),
    );
  }

  @override
  void expand() => _screen._expandPlayer();

  @override
  void stop() => _screen._stopMinimized();
}
