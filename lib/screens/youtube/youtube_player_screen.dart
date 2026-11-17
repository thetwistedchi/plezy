import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../services/fullscreen_state_manager.dart';
import '../../services/youtube/sponsorblock.dart';
import '../../services/youtube/youtube_service.dart';
import '../../services/youtube/youtube_settings.dart';
import '../../services/youtube/youtube_watchlist.dart';
import '../../services/youtube/youtube_webview.dart';
import '../../theme/player_style.dart';
import '../../utils/app_logger.dart';
import '../../widgets/app_icon.dart';
import 'youtube_channel_panel.dart';
import 'youtube_channel_screen.dart';
import 'youtube_comments_panel.dart';
import 'youtube_strings.dart';

/// Plays YouTube videos inside the app: the embedded YouTube player in a
/// WebView2 with YouTube's own controls hidden, and the retrowave player
/// controls drawn over it. Plays [queue] in order from [startIndex].
class YouTubePlayerScreen extends StatefulWidget {
  const YouTubePlayerScreen({super.key, required this.queue, this.startIndex = 0, this.fromWatchlist = false});

  final List<YouTubeVideo> queue;
  final int startIndex;

  /// Finished videos are taken off the watchlist.
  final bool fromWatchlist;

  /// Opens the player, or the browser where the in-app player isn't available.
  static Future<void> open(
    BuildContext context,
    List<YouTubeVideo> queue, {
    int startIndex = 0,
    bool fromWatchlist = false,
  }) async {
    if (queue.isEmpty) return;
    final video = queue[startIndex];
    unawaited(YouTubeSettings.instance.markOpened(video.id, video.channelId));
    if (!YouTubeWebView.isSupported) {
      await launchUrl(video.watchUrl, mode: LaunchMode.externalApplication);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => YouTubePlayerScreen(queue: queue, startIndex: startIndex, fromWatchlist: fromWatchlist),
      ),
    );
  }

  @override
  State<YouTubePlayerScreen> createState() => _YouTubePlayerScreenState();
}

enum _SidePanel { none, comments, channel }

class _YouTubePlayerScreenState extends State<YouTubePlayerScreen> {
  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.1, 1.2, 1.25, 1.5, 1.75, 2.0];
  static const _apiSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  static const _hideDelay = Duration(seconds: 3);

  final _controller = WebviewController();
  final _settings = YouTubeSettings.instance;
  final _focusNode = FocusNode(debugLabel: 'youtube_player');
  StreamSubscription<dynamic>? _messages;

  late final List<YouTubeVideo> _queue = List.of(widget.queue);
  late int _index = widget.startIndex.clamp(0, widget.queue.length - 1);
  YouTubeVideo get _video => _queue[_index];

  bool _webReady = false;
  String? _initError;
  int? _errorCode;

  double _position = 0;
  double _duration = 0;
  double _buffered = 0;
  int _state = -1; // YT.PlayerState: -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued
  int _volume = 100;
  bool _muted = false;
  double _rate = 1;
  bool _captions = false;
  List<String> _qualities = const [];
  String _quality = 'auto';

  /// YouTube's own names per level, e.g. hd1080 → 1080p60, without the
  /// Premium-bitrate variants.
  Map<String, String> _qualityNames = const {};
  String _currentQualityLabel = '';

  /// The quality the user picked in this session, or the saved preference.
  late String _wantedQuality = _settings.preferredQuality;
  bool _qualityApplied = false;

  YtVideoInfo? _info;
  List<YtChapter> _chapters = const [];
  List<SponsorSegment> _segments = const [];
  List<YouTubeVideo> _channelVideos = const [];
  String _rating = 'none';
  String _initialRating = 'none';

  final Set<SponsorSegment> _handled = {};
  SponsorSegment? _buttonSegment;
  SponsorSegment? _toastSegment;
  Timer? _toastTimer;

  bool _controlsVisible = true;
  bool _pointerOnControls = false;
  Timer? _hideTimer;
  _SidePanel _panel = _SidePanel.none;
  bool _fullscreen = false;
  bool _enteredFullscreen = false;
  int _metaGeneration = 0;
  DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _playing => _state == 1 || _state == 3;

  @override
  void initState() {
    super.initState();
    _volume = _settings.playerVolume;
    _fullscreen = FullscreenStateManager().isFullscreen;
    unawaited(_init());
    unawaited(_loadMeta());
  }

  @override
  void dispose() {
    _saveProgress();
    _hideTimer?.cancel();
    _toastTimer?.cancel();
    unawaited(_messages?.cancel());
    unawaited(_controller.dispose());
    _focusNode.dispose();
    if (_enteredFullscreen) unawaited(FullscreenStateManager().exitFullscreen());
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final folder = await YouTubeWebView.ensureReady();
      if (await WebviewController.getWebViewVersion() == null) {
        if (mounted) setState(() => _initError = YtStrings.webviewMissing);
        return;
      }
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.black);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await _controller.addVirtualHostNameMapping(YouTubeWebView.host, folder, WebviewHostResourceAccessKind.allow);
      await _controller.addScriptToExecuteOnDocumentCreated(YouTubeWebView.frameScript);
      _messages = _controller.webMessage.listen(_onMessage);
      await _controller.loadUrl(
        YouTubeWebView.playerUrl(_video.id, start: _settings.resumePosition(_video.id) ?? 0).toString(),
      );
      if (mounted) setState(() => _webReady = true);
      _scheduleHide();
    } catch (e, st) {
      appLogger.w('YouTube player failed to start', error: e, stackTrace: st);
      if (mounted) setState(() => _initError = '${YtStrings.playerFailed}\n$e');
    }
  }

  /// Description, chapters, SponsorBlock segments and the user's rating of
  /// the current video.
  Future<void> _loadMeta() async {
    final generation = ++_metaGeneration;
    final videoId = _video.id;
    setState(() {
      _info = null;
      _chapters = const [];
      _segments = const [];
      _channelVideos = const [];
      _rating = 'none';
      _initialRating = 'none';
      _handled.clear();
      _buttonSegment = null;
    });
    final service = YouTubeService.instance;
    final channelId = _video.channelId;
    unawaited(
      service
          .channelFeed(channelId)
          .then((videos) {
            if (!mounted || generation != _metaGeneration) return;
            final s = _settings;
            setState(
              () => _channelVideos = videos
                  .where(
                    (v) =>
                        v.id != videoId &&
                        (s.showShorts || !v.isShort) &&
                        (s.showPremieres || !(v.isUpcoming || v.isLive)),
                  )
                  .toList(),
            );
          })
          .catchError((Object _) {}),
    );
    unawaited(
      SponsorBlock.segments(videoId).then((segments) {
        if (mounted && generation == _metaGeneration) setState(() => _segments = segments);
      }),
    );
    try {
      final info = await service.videoInfo(videoId);
      if (!mounted || generation != _metaGeneration) return;
      setState(() {
        _info = info;
        _chapters = info == null ? const [] : parseChapters(info.description);
      });
    } catch (e) {
      appLogger.d('YouTube video info failed: $e');
    }
    if (_settings.canWrite) {
      try {
        final rating = await service.myRating(videoId);
        if (mounted && generation == _metaGeneration) {
          setState(() => _rating = _initialRating = rating);
        }
      } catch (e) {
        appLogger.d('YouTube rating lookup failed: $e');
      }
    }
  }

  void _send(Map<String, Object?> command) {
    if (!_webReady) return;
    unawaited(_controller.postWebMessage(jsonEncode(command)));
  }

  void _onMessage(dynamic message) {
    if (message is! Map || !mounted) return;
    switch (message['t']) {
      case 'ready':
        _send({'cmd': 'volume', 'v': _volume});
        setState(() => _errorCode = null);
      case 'time':
        setState(() {
          _position = (message['cur'] as num?)?.toDouble() ?? _position;
          _duration = (message['dur'] as num?)?.toDouble() ?? _duration;
          _buffered = (message['buf'] as num?)?.toDouble() ?? _buffered;
          _volume = (message['vol'] as num?)?.round() ?? _volume;
          _muted = message['muted'] as bool? ?? _muted;
        });
        _checkSegments();
        if (_playing && DateTime.now().difference(_lastProgressSave) > const Duration(seconds: 5)) {
          _saveProgress();
        }
      case 'state':
        final state = (message['s'] as num?)?.toInt() ?? -1;
        setState(() => _state = state);
        if (state == 0) {
          _onEnded();
        } else if (state == 1) {
          if (_rate != 1) _send({'cmd': 'frame', 'msg': {'plezy': 'rate', 'r': _rate}});
          _scheduleHide();
        } else {
          _showControls(autoHide: false);
        }
      case 'error':
        setState(() => _errorCode = (message['code'] as num?)?.toInt());
      case 'rate':
        // Our own speed is the source of truth; the frame script keeps it.
        break;
      case 'quality':
        final levels = [
          for (final l in (message['levels'] as List? ?? const []))
            if (l is String && l != 'auto') l,
        ];
        final current = message['current'] as String? ?? 'auto';
        final currentLabel = message['currentLabel'] as String? ?? '';
        final names = <String, String>{};
        for (final d in (message['data'] as List? ?? const [])) {
          if (d is! Map) continue;
          final q = d['q'] as String?;
          final label = (d['label'] as String? ?? '').trim();
          if (q == null || label.isEmpty || label.toLowerCase().contains('premium')) continue;
          names.putIfAbsent(q, () => label);
        }
        if (!_listEquals(levels, _qualities) ||
            current != _quality ||
            currentLabel != _currentQualityLabel ||
            names.length != _qualityNames.length) {
          setState(() {
            _qualities = levels;
            _quality = current;
            _currentQualityLabel = currentLabel;
            _qualityNames = names;
          });
        }
        if (!_qualityApplied && levels.isNotEmpty) {
          _qualityApplied = true;
          if (_wantedQuality != 'auto') _applyQuality(_pickQuality(levels, _wantedQuality));
        }
      case 'key':
        _handleKey(message['k'] as String? ?? '', shift: message['shift'] as bool? ?? false);
    }
  }

  // ---- Playback ----

  void _togglePlay() => _send({'cmd': _playing ? 'pause' : 'play'});

  void _seek(double seconds) {
    final target = _duration > 0 ? seconds.clamp(0, _duration).toDouble() : math.max(0.0, seconds);
    _send({'cmd': 'seek', 't': target});
    setState(() => _position = target);
    _showControls();
  }

  void _seekBy(double delta) => _seek(_position + delta);

  void _setVolume(int volume) {
    final v = volume.clamp(0, 100);
    _send({'cmd': 'volume', 'v': v});
    if (_muted && v > 0) _send({'cmd': 'mute', 'on': false});
    setState(() {
      _volume = v;
      if (v > 0) _muted = false;
    });
    unawaited(_settings.setPlayerVolume(v));
  }

  void _toggleMute() {
    _send({'cmd': 'mute', 'on': !_muted});
    setState(() => _muted = !_muted);
  }

  void _setRate(double rate) {
    if (_apiSpeeds.contains(rate)) _send({'cmd': 'rate', 'r': rate});
    _send({
      'cmd': 'frame',
      'msg': {'plezy': 'rate', 'r': rate},
    });
    setState(() => _rate = rate);
  }

  void _applyQuality(String quality) {
    _send({
      'cmd': 'frame',
      'msg': {'plezy': 'quality', 'q': quality},
    });
    setState(() => _quality = quality);
  }

  void _selectQuality(String quality) {
    _wantedQuality = quality;
    unawaited(_settings.setPreferredQuality(quality));
    _applyQuality(quality);
  }

  /// [wanted] if offered, else the best level below it, else the lowest.
  static String _pickQuality(List<String> levels, String wanted) {
    if (levels.contains(wanted)) return wanted;
    const order = ['highres', 'hd2880', 'hd2160', 'hd1440', 'hd1080', 'hd720', 'large', 'medium', 'small', 'tiny'];
    final wantedRank = order.indexOf(wanted);
    for (final q in order.skip(wantedRank < 0 ? 0 : wantedRank)) {
      if (levels.contains(q)) return q;
    }
    return levels.last;
  }

  /// Badge text: YouTube's label of what is playing (1080p60, 2160p60 HDR,
  /// 1080p Premium), else the plain resolution.
  String _badgeLabel() {
    final label = _currentQualityLabel.trim();
    if (label.isNotEmpty) return label;
    final name = _qualityNames[_quality];
    if (name != null) return name;
    final short = YtStrings.qualityShort(_quality);
    return short.isEmpty ? YtStrings.qualityAuto : short;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _toggleCaptions() {
    _send({'cmd': 'cc', 'on': !_captions});
    setState(() => _captions = !_captions);
  }

  Future<void> _toggleFullscreen() async {
    // Changing the window style briefly hides the WebView, and YouTube
    // pauses on that; resume when it was playing.
    final wasPlaying = _playing;
    final manager = FullscreenStateManager();
    final next = !manager.isFullscreen;
    if (next) {
      await manager.enterFullscreen();
    } else {
      await manager.exitFullscreen();
    }
    if (!mounted) return;
    setState(() {
      _fullscreen = next;
      _enteredFullscreen = next;
    });
    if (wasPlaying) {
      for (final delay in const [Duration(milliseconds: 350), Duration(milliseconds: 1200)]) {
        unawaited(
          Future<void>.delayed(delay, () {
            if (mounted && !_playing) _send({'cmd': 'play'});
          }),
        );
      }
    }
  }

  void _togglePanel(_SidePanel panel) => setState(() => _panel = _panel == panel ? _SidePanel.none : panel);

  /// Plays [video] right after the current one in the queue.
  void _playNow(YouTubeVideo video) {
    final existing = _queue.indexWhere((v) => v.id == video.id);
    if (existing == _index) return;
    if (existing >= 0) {
      _playIndex(existing);
      return;
    }
    _queue.insert(_index + 1, video);
    _playIndex(_index + 1);
  }

  Future<void> _openChannel() async {
    _send({'cmd': 'pause'});
    final picked = await Navigator.of(context).push<YouTubeVideo>(
      MaterialPageRoute(
        builder: (_) => YouTubeChannelScreen(
          channelId: _video.channelId,
          channelTitle: _video.channelTitle,
          returnPickedVideo: true,
        ),
      ),
    );
    if (!mounted) return;
    _focusNode.requestFocus();
    if (picked != null) {
      _playNow(picked);
    } else {
      _send({'cmd': 'play'});
    }
  }

  /// Remembers where the current video is, so it resumes there next time.
  void _saveProgress() {
    if (_duration <= 0 || _position <= 0) return;
    _lastProgressSave = DateTime.now();
    unawaited(_settings.saveProgress(_video.id, _position, _duration));
  }

  void _playIndex(int index) {
    if (index < 0 || index >= _queue.length) return;
    _saveProgress();
    setState(() {
      _index = index;
      _position = 0;
      _duration = 0;
      _buffered = 0;
      _errorCode = null;
      _toastSegment = null;
      _qualities = const [];
      _qualityNames = const {};
      _currentQualityLabel = '';
      _qualityApplied = false;
    });
    unawaited(YouTubeSettings.instance.markOpened(_video.id, _video.channelId));
    _send({'cmd': 'load', 'id': _video.id, 't': _settings.resumePosition(_video.id) ?? 0});
    unawaited(_loadMeta());
    _showControls();
  }

  void _onEnded() {
    if (_duration > 0) unawaited(_settings.saveProgress(_video.id, _duration, _duration));
    if (widget.fromWatchlist) unawaited(YouTubeWatchlist.instance.remove(_video.id));
    if (_index < _queue.length - 1) {
      _playIndex(_index + 1);
    } else {
      _showControls(autoHide: false);
    }
  }

  // ---- SponsorBlock ----

  void _checkSegments() {
    if (!_settings.sponsorBlockEnabled || _segments.isEmpty) return;
    SponsorSegment? inside;
    for (final segment in _segments) {
      if (!segment.isHighlight && segment.contains(_position)) {
        inside = segment;
        break;
      }
    }
    if (inside == null) {
      if (_buttonSegment != null) setState(() => _buttonSegment = null);
      return;
    }
    final mode = _settings.segmentMode(inside.category);
    if (mode == SegmentMode.auto && !_handled.contains(inside)) {
      _handled.add(inside);
      _seek(inside.end);
      _showToast(inside);
    } else if (mode == SegmentMode.button && !_handled.contains(inside)) {
      if (_buttonSegment != inside) setState(() => _buttonSegment = inside);
    } else if (_buttonSegment != null) {
      setState(() => _buttonSegment = null);
    }
  }

  void _skipButtonSegment() {
    final segment = _buttonSegment;
    if (segment == null) return;
    _handled.add(segment);
    setState(() => _buttonSegment = null);
    _seek(segment.end);
  }

  void _showToast(SponsorSegment segment) {
    _toastTimer?.cancel();
    setState(() => _toastSegment = segment);
    _toastTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _toastSegment = null);
    });
  }

  void _undoSkip() {
    final segment = _toastSegment;
    if (segment == null) return;
    _toastTimer?.cancel();
    setState(() => _toastSegment = null);
    _seek(segment.start);
  }

  SponsorSegment? get _highlight {
    for (final s in _segments) {
      if (s.isHighlight) return s;
    }
    return null;
  }

  // ---- Rating ----

  Future<void> _rateVideo(String rating) async {
    if (!_settings.canWrite) {
      _snack(YtStrings.needWriteAccess);
      return;
    }
    final previous = _rating;
    final next = previous == rating ? 'none' : rating;
    setState(() => _rating = next);
    try {
      await YouTubeService.instance.rate(_video.id, next);
    } catch (e) {
      appLogger.w('YouTube rating failed', error: e);
      if (mounted) setState(() => _rating = previous);
      _snack(YtStrings.ratingFailed);
    }
  }

  int? get _likeCount {
    final base = _info?.likeCount;
    if (base == null) return null;
    final was = _initialRating == 'like' ? 1 : 0;
    final now = _rating == 'like' ? 1 : 0;
    return base - was + now;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---- Controls visibility ----

  void _showControls({bool autoHide = true}) {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    if (autoHide) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (!mounted || !_playing || _pointerOnControls) return;
      setState(() => _controlsVisible = false);
    });
  }

  // ---- Keyboard ----

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final handled = _handleKey(
      event.logicalKey.keyLabel.length == 1 ? event.logicalKey.keyLabel.toLowerCase() : _keyName(event.logicalKey),
      shift: HardwareKeyboard.instance.isShiftPressed,
    );
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  static String _keyName(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.space) return ' ';
    if (key == LogicalKeyboardKey.arrowLeft) return 'ArrowLeft';
    if (key == LogicalKeyboardKey.arrowRight) return 'ArrowRight';
    if (key == LogicalKeyboardKey.arrowUp) return 'ArrowUp';
    if (key == LogicalKeyboardKey.arrowDown) return 'ArrowDown';
    if (key == LogicalKeyboardKey.escape) return 'Escape';
    return key.keyLabel;
  }

  bool _handleKey(String key, {bool shift = false}) {
    switch (key.length == 1 ? key.toLowerCase() : key) {
      case ' ' || 'k':
        _togglePlay();
      case 'ArrowLeft' || 'j':
        _seekBy(-10);
      case 'ArrowRight' || 'l':
        _seekBy(10);
      case 'ArrowUp':
        _setVolume(_volume + 5);
      case 'ArrowDown':
        _setVolume(_volume - 5);
      case 'm':
        _toggleMute();
      case 'f':
        unawaited(_toggleFullscreen());
      case 'c':
        _togglePanel(_SidePanel.comments);
      case 'n':
        if (shift) {
          _playIndex(_index - 1);
        } else {
          _playIndex(_index + 1);
        }
      case 'Escape':
        if (_fullscreen) {
          unawaited(_toggleFullscreen());
        } else {
          Navigator.of(context).maybePop();
        }
      default:
        return false;
    }
    _showControls();
    return true;
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Row(
          children: [
            Expanded(child: _buildVideoArea(context)),
            if (_panel == _SidePanel.comments)
              SizedBox(
                width: 440,
                child: YouTubeCommentsPanel(
                  key: ValueKey('comments-${_video.id}'),
                  videoId: _video.id,
                  commentCount: _info?.commentCount,
                  onClose: () => setState(() => _panel = _SidePanel.none),
                ),
              ),
            if (_panel == _SidePanel.channel)
              SizedBox(
                width: 440,
                child: YouTubeChannelPanel(
                  key: ValueKey('channel-${_video.channelId}'),
                  channelId: _video.channelId,
                  channelTitle: _video.channelTitle,
                  currentVideoId: _video.id,
                  onPlay: _playNow,
                  onOpenChannel: () => unawaited(_openChannel()),
                  onClose: () => setState(() => _panel = _SidePanel.none),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea(BuildContext context) {
    final style = PlayerStyle.of(context);
    final accent = playerActiveColor(context);
    return MouseRegion(
      cursor: _controlsVisible ? SystemMouseCursors.basic : SystemMouseCursors.none,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: (_) => _showControls(),
        onPointerMove: (_) => _showControls(),
        onPointerDown: (_) {
          _focusNode.requestFocus();
          _showControls();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_initError != null)
              _CenterMessage(text: _initError!, onOpen: _openOnYouTube)
            else if (!_webReady)
              Center(child: CircularProgressIndicator(color: accent))
            else ...[
              Webview(_controller),
              // Takes clicks and hovers away from the embed, so YouTube's own
              // hover UI never shows: click plays/pauses, double-click
              // toggles fullscreen.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePlay,
                onDoubleTap: () => unawaited(_toggleFullscreen()),
              ),
            ],
            if (_errorCode != null)
              _CenterMessage(
                text: _errorCode == 101 || _errorCode == 150 || _errorCode == 152 || _errorCode == 153
                    ? YtStrings.embedBlocked
                    : YtStrings.videoUnavailable,
                onOpen: _openOnYouTube,
              ),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.18, 0.62, 1],
                      colors: [Color(0xB3000000), Color(0x00000000), Color(0x00000000), Color(0xD9000000)],
                    ),
                  ),
                ),
              ),
            ),
            if (_toastSegment != null)
              Positioned(
                top: 92,
                left: 0,
                right: 0,
                child: Center(
                  child: _SkipToast(
                    text: YtStrings.skipped(_toastSegment!.category),
                    accent: accent,
                    onUndo: _undoSkip,
                  ),
                ),
              ),
            if ((_state == 2 || _state == 0) &&
                _controlsVisible &&
                _channelVideos.isNotEmpty &&
                _panel != _SidePanel.channel)
              Positioned(
                left: 28,
                right: 28,
                bottom: 150,
                child: _ChannelStrip(
                  title: YtStrings.moreFrom(_video.channelTitle),
                  videos: _channelVideos,
                  accent: accent,
                  onPlay: _playNow,
                  onOpenChannel: () => unawaited(_openChannel()),
                ),
              ),
            if (_buttonSegment != null)
              Positioned(
                right: 28,
                bottom: 150,
                child: _NeonSkipButton(
                  label: YtStrings.skipCategory(_buttonSegment!.category),
                  color: style.skipButtonBorder ?? accent,
                  onPressed: _skipButtonSegment,
                ),
              ),
            _fade(
              Align(alignment: Alignment.topCenter, child: _buildTopBar(context)),
            ),
            _fade(
              Align(alignment: Alignment.bottomCenter, child: _buildBottomBar(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fade(Widget child) {
    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: MouseRegion(
          opaque: false,
          onEnter: (_) => _pointerOnControls = true,
          onExit: (_) => _pointerOnControls = false,
          child: child,
        ),
      ),
    );
  }

  Future<void> _openOnYouTube() async {
    final url = Uri.https('www.youtube.com', '/watch', {
      'v': _video.id,
      if (_position > 1) 't': '${_position.floor()}s',
    });
    _send({'cmd': 'pause'});
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          _PlayerButton(
            icon: Symbols.arrow_back_rounded,
            tooltip: YtStrings.back,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _info?.title ?? _video.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                Text(
                  _queue.length > 1
                      ? '${_video.channelTitle} · ${YtStrings.queuePosition(_index + 1, _queue.length)}'
                      : _video.channelTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _PlayerButton(
            icon: Symbols.comment_rounded,
            tooltip: YtStrings.comments,
            active: _panel == _SidePanel.comments,
            onPressed: () => _togglePanel(_SidePanel.comments),
          ),
          _PlayerButton(
            icon: Symbols.video_library_rounded,
            tooltip: YtStrings.moreFromChannel,
            active: _panel == _SidePanel.channel,
            onPressed: () => _togglePanel(_SidePanel.channel),
          ),
          _PlayerButton(
            icon: Symbols.account_box_rounded,
            tooltip: YtStrings.openChannel,
            onPressed: () => unawaited(_openChannel()),
          ),
          _PlayerButton(
            icon: Symbols.open_in_new_rounded,
            tooltip: YtStrings.openOnYouTube,
            onPressed: () => unawaited(_openOnYouTube()),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final style = PlayerStyle.of(context);
    final accent = playerActiveColor(context);
    final highlight = _highlight;
    final chapter = _chapterAt(_position);
    final visibleSegments = _settings.showSegmentsOnTimeline ? _segments : const <SponsorSegment>[];
    final hasNext = _index < _queue.length - 1;
    final hasPrevious = _index > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: _RatingPill(
              likes: _likeCount,
              rating: _rating,
              accent: accent,
              onLike: () => unawaited(_rateVideo('like')),
              onDislike: () => unawaited(_rateVideo('dislike')),
            ),
          ),
          _Timeline(
            position: _position,
            duration: _duration,
            buffered: _buffered,
            chapters: _chapters,
            segments: visibleSegments,
            gradient: style.progressGradient ?? [accent, accent],
            thumbGlow: style.progressGlow ?? accent,
            onSeek: _seek,
            onHoverChanged: (hovering) => _pointerOnControls = hovering,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _PlayerButton(icon: Symbols.replay_10_rounded, tooltip: YtStrings.back10, onPressed: () => _seekBy(-10)),
              const SizedBox(width: 4),
              _PlayButton(
                playing: _playing,
                fill: style.playButtonFill ?? accent,
                iconColor: style.playButtonIcon ?? Colors.black,
                tooltip: _playing ? YtStrings.pause : YtStrings.play,
                onPressed: _togglePlay,
              ),
              const SizedBox(width: 4),
              _PlayerButton(
                icon: Symbols.forward_10_rounded,
                tooltip: YtStrings.forward10,
                onPressed: () => _seekBy(10),
              ),
              if (_queue.length > 1) ...[
                _PlayerButton(
                  icon: Symbols.skip_previous_rounded,
                  tooltip: YtStrings.previous,
                  onPressed: hasPrevious ? () => _playIndex(_index - 1) : null,
                ),
                _PlayerButton(
                  icon: Symbols.skip_next_rounded,
                  tooltip: hasNext ? YtStrings.upNext(_queue[_index + 1].title) : YtStrings.next,
                  onPressed: hasNext ? () => _playIndex(_index + 1) : null,
                ),
              ],
              if (highlight != null && _settings.showSegmentsOnTimeline)
                _PlayerButton(
                  icon: Symbols.star_rounded,
                  tooltip: YtStrings.jumpToHighlight,
                  onPressed: () => _seek(highlight.start),
                ),
              const SizedBox(width: 10),
              Text(
                '${_formatTime(_position)} / ${_formatTime(_duration)}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
              ),
              if (chapter != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '· ${chapter.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ] else
                const Spacer(),
              if (chapter != null) const SizedBox(width: 12),
              _PlayerButton(
                icon: _muted || _volume == 0 ? Symbols.volume_off_rounded : Symbols.volume_up_rounded,
                tooltip: _muted ? YtStrings.unmute : YtStrings.mute,
                onPressed: _toggleMute,
              ),
              SizedBox(
                width: 110,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: accent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: (_muted ? 0 : _volume).toDouble(),
                    max: 100,
                    onChanged: (v) => _setVolume(v.round()),
                  ),
                ),
              ),
              if (_qualities.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: YtStrings.quality,
                  onSelected: _selectQuality,
                  itemBuilder: (_) => [
                    for (final q in ['auto', ..._qualities])
                      CheckedPopupMenuItem(
                        value: q,
                        checked: q == _wantedQuality,
                        child: Text(q == 'auto' ? YtStrings.qualityAuto : _qualityNames[q] ?? YtStrings.qualityLabel(q)),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: style.badge ?? accent, width: 1.5),
                      ),
                      child: Text(
                        _badgeLabel(),
                        style: TextStyle(color: style.badge ?? accent, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              _PlayerButton(
                icon: Symbols.closed_caption_rounded,
                tooltip: YtStrings.captions,
                active: _captions,
                onPressed: _toggleCaptions,
              ),
              PopupMenuButton<double>(
                tooltip: YtStrings.speed,
                initialValue: _rate,
                onSelected: _setRate,
                itemBuilder: (_) => [
                  for (final s in _speeds)
                    PopupMenuItem(value: s, child: Text(s == 1 ? YtStrings.normalSpeed : '${_trim(s)}×')),
                ],
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Text(
                      '${_trim(_rate)}×',
                      style: TextStyle(
                        color: _rate == 1 ? Colors.white : accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
              if (_chapters.isNotEmpty)
                PopupMenuButton<int>(
                  tooltip: YtStrings.chapters,
                  onSelected: (i) => _seek(_chapters[i].start),
                  itemBuilder: (_) => [
                    for (var i = 0; i < _chapters.length; i++)
                      PopupMenuItem(
                        value: i,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 64,
                              child: Text(
                                _formatTime(_chapters[i].start),
                                style: TextStyle(color: _chapters[i] == chapter ? accent : null),
                              ),
                            ),
                            Flexible(child: Text(_chapters[i].title, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                  ],
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(child: AppIcon(Symbols.list_rounded, color: Colors.white)),
                  ),
                ),
              _PlayerButton(
                icon: _fullscreen ? Symbols.fullscreen_exit_rounded : Symbols.fullscreen_rounded,
                tooltip: _fullscreen ? YtStrings.exitFullscreen : YtStrings.fullscreen,
                onPressed: () => unawaited(_toggleFullscreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  YtChapter? _chapterAt(double t) {
    YtChapter? current;
    for (final c in _chapters) {
      if (c.start <= t) current = c;
    }
    return current;
  }

  static String _trim(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

String _formatTime(double seconds) {
  if (seconds.isNaN || seconds < 0) seconds = 0;
  final total = seconds.floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

class _PlayerButton extends StatelessWidget {
  const _PlayerButton({required this.icon, required this.tooltip, required this.onPressed, this.active = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final accent = playerActiveColor(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 24,
      style: IconButton.styleFrom(
        fixedSize: const Size(48, 48),
        backgroundColor: active ? accent.withValues(alpha: 0.16) : Colors.transparent,
      ),
      icon: AppIcon(
        icon,
        fill: 1,
        color: onPressed == null ? Colors.white30 : (active ? accent : Colors.white),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.fill,
    required this.iconColor,
    required this.tooltip,
    required this.onPressed,
  });

  final bool playing;
  final Color fill;
  final Color iconColor;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: RepaintBoundary(
        child: Material(
          color: fill,
          shape: const CircleBorder(),
          shadowColor: fill,
          elevation: 8,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Center(
                child: AppIcon(
                  playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                  fill: 1,
                  size: 30,
                  color: iconColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({
    required this.likes,
    required this.rating,
    required this.accent,
    required this.onLike,
    required this.onDislike,
  });

  final int? likes;
  final String rating;
  final Color accent;
  final VoidCallback onLike;
  final VoidCallback onDislike;

  @override
  Widget build(BuildContext context) {
    final liked = rating == 'like';
    final disliked = rating == 'dislike';
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: YtStrings.like,
            child: InkWell(
              onTap: onLike,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    AppIcon(Symbols.thumb_up_rounded, fill: liked ? 1 : 0, size: 20, color: liked ? accent : Colors.white),
                    if (likes != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        _compact(likes!),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: 22, color: Colors.white24),
          Tooltip(
            message: YtStrings.dislike,
            child: InkWell(
              onTap: onDislike,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: AppIcon(
                  Symbols.thumb_down_rounded,
                  fill: disliked ? 1 : 0,
                  size: 20,
                  color: disliked ? accent : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)} M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)} K';
    return '$n';
  }
}

class _NeonSkipButton extends StatelessWidget {
  const _NeonSkipButton({required this.label, required this.color, required this.onPressed});

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 20)],
      ),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          backgroundColor: const Color(0xC00B0618),
          foregroundColor: Colors.white,
          side: BorderSide(color: color, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.2),
        ),
        child: Text(label),
      ),
    );
  }
}

class _SkipToast extends StatelessWidget {
  const _SkipToast({required this.text, required this.accent, required this.onUndo});

  final String text;
  final Color accent;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xE60B0618),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 22)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: onUndo,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
              minimumSize: const Size(0, 40),
            ),
            child: Text(YtStrings.undo),
          ),
        ],
      ),
    );
  }
}

class _CenterMessage extends StatelessWidget {
  const _CenterMessage({required this.text, required this.onOpen});

  final String text;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onOpen,
                icon: const AppIcon(Symbols.open_in_new_rounded, size: 18),
                label: Text(YtStrings.openOnYouTube),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The seek bar: buffered range, the played part in the theme's gradient,
/// gaps at chapter starts, SponsorBlock segments and the highlight marker.
/// Hovering shows the time and chapter under the pointer.
class _Timeline extends StatefulWidget {
  const _Timeline({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.chapters,
    required this.segments,
    required this.gradient,
    required this.thumbGlow,
    required this.onSeek,
    required this.onHoverChanged,
  });

  final double position;
  final double duration;
  final double buffered;
  final List<YtChapter> chapters;
  final List<SponsorSegment> segments;
  final List<Color> gradient;
  final Color thumbGlow;
  final ValueChanged<double> onSeek;
  final ValueChanged<bool> onHoverChanged;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  double? _hoverX;
  double? _dragFraction;

  double _fractionAt(double x, double width) => width <= 0 ? 0 : (x / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final duration = widget.duration;
        final hoverFraction = _hoverX == null ? null : _fractionAt(_hoverX!, width);
        final hoverTime = hoverFraction == null ? null : hoverFraction * duration;
        String? hoverChapter;
        if (hoverTime != null) {
          for (final c in widget.chapters) {
            if (c.start <= hoverTime) hoverChapter = c.title;
          }
        }
        final shownFraction = _dragFraction ?? (duration > 0 ? (widget.position / duration).clamp(0.0, 1.0) : 0.0);

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => widget.onHoverChanged(true),
          onExit: (_) {
            widget.onHoverChanged(false);
            setState(() => _hoverX = null);
          },
          onHover: (e) => setState(() => _hoverX = e.localPosition.dx),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => widget.onSeek(_fractionAt(d.localPosition.dx, width) * duration),
            onHorizontalDragStart: (d) => setState(() => _dragFraction = _fractionAt(d.localPosition.dx, width)),
            onHorizontalDragUpdate: (d) => setState(() {
              _dragFraction = _fractionAt(d.localPosition.dx, width);
              _hoverX = d.localPosition.dx;
            }),
            onHorizontalDragEnd: (_) {
              final f = _dragFraction;
              setState(() => _dragFraction = null);
              if (f != null) widget.onSeek(f * duration);
            },
            child: SizedBox(
              height: 64,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TimelinePainter(
                        fraction: shownFraction,
                        buffered: widget.buffered.clamp(0.0, 1.0),
                        duration: duration,
                        chapters: widget.chapters,
                        segments: widget.segments,
                        gradient: widget.gradient,
                        thumbGlow: widget.thumbGlow,
                        hovering: _hoverX != null,
                      ),
                    ),
                  ),
                  if (hoverTime != null && duration > 0)
                    Positioned(
                      left: (_hoverX!.clamp(60.0, math.max(60.0, width - 60))) - 60,
                      bottom: 30,
                      width: 120,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xE60B0618),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hoverChapter != null)
                                Text(
                                  hoverChapter,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                              Text(
                                _formatTime(hoverTime),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.fraction,
    required this.buffered,
    required this.duration,
    required this.chapters,
    required this.segments,
    required this.gradient,
    required this.thumbGlow,
    required this.hovering,
  });

  final double fraction;
  final double buffered;
  final double duration;
  final List<YtChapter> chapters;
  final List<SponsorSegment> segments;
  final List<Color> gradient;
  final Color thumbGlow;
  final bool hovering;

  @override
  void paint(Canvas canvas, Size size) {
    final trackHeight = hovering ? 8.0 : 6.0;
    final y = size.height - 14;
    final track = Rect.fromLTWH(0, y - trackHeight / 2, size.width, trackHeight);
    final radius = Radius.circular(trackHeight / 2);

    // Chapter gaps: clip them out of every layer.
    canvas.save();
    if (duration > 0) {
      for (final c in chapters.skip(1)) {
        final x = c.start / duration * size.width;
        canvas.clipRect(Rect.fromLTWH(x - 1.5, 0, 3, size.height), clipOp: ui.ClipOp.difference);
      }
    }

    canvas.drawRRect(RRect.fromRectAndRadius(track, radius), Paint()..color = Colors.white.withValues(alpha: 0.18));
    if (buffered > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, track.top, size.width * buffered, trackHeight), radius),
        Paint()..color = Colors.white.withValues(alpha: 0.22),
      );
    }
    final played = Rect.fromLTWH(0, track.top, size.width * fraction, trackHeight);
    if (played.width > 0) {
      final colors = gradient.length >= 2 ? gradient : [gradient.first, gradient.first];
      canvas.drawRRect(
        RRect.fromRectAndRadius(played, radius),
        Paint()..shader = LinearGradient(colors: colors).createShader(played),
      );
    }

    if (duration > 0) {
      final segmentPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
      for (final s in segments) {
        if (s.isHighlight) continue;
        final left = s.start / duration * size.width;
        final right = s.end / duration * size.width;
        canvas.drawRect(Rect.fromLTRB(left, track.top, math.max(left + 2, right), track.bottom), segmentPaint);
      }
    }
    canvas.restore();

    if (duration > 0) {
      for (final s in segments) {
        if (!s.isHighlight) continue;
        final x = s.start / duration * size.width;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x - 2, track.top - 4, 4, trackHeight + 8), const Radius.circular(2)),
          Paint()
            ..color = const Color(0xFFF9E2FF)
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.solid, 3),
        );
      }
    }

    final thumbX = size.width * fraction;
    canvas.drawCircle(
      Offset(thumbX, y),
      hovering ? 9 : 8,
      Paint()
        ..color = thumbGlow.withValues(alpha: 0.6)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8),
    );
    canvas.drawCircle(Offset(thumbX, y), hovering ? 8 : 7, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.fraction != fraction ||
      old.buffered != buffered ||
      old.duration != duration ||
      old.chapters != chapters ||
      old.segments != segments ||
      old.hovering != hovering ||
      old.gradient != gradient;
}

/// YouTube-style "More videos" row, in the player's look, from the channel
/// feed. Shown while paused and at the end.
class _ChannelStrip extends StatelessWidget {
  const _ChannelStrip({
    required this.title,
    required this.videos,
    required this.accent,
    required this.onPlay,
    required this.onOpenChannel,
  });

  final String title;
  final List<YouTubeVideo> videos;
  final Color accent;
  final ValueChanged<YouTubeVideo> onPlay;
  final VoidCallback onOpenChannel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onOpenChannel,
              style: TextButton.styleFrom(foregroundColor: accent),
              child: Text(YtStrings.openChannel),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: videos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final video = videos[i];
              return SizedBox(
                width: 210,
                child: InkWell(
                  onTap: () => onPlay(video),
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 210,
                          height: 118,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const ColoredBox(color: Color(0xFF1B1240)),
                              if (video.thumbnailUrl != null)
                                CachedNetworkImage(
                                  imageUrl: video.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                                ),
                              if (video.duration > Duration.zero)
                                Positioned(
                                  right: 6,
                                  bottom: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.75),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      YtStrings.duration(video.duration),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
