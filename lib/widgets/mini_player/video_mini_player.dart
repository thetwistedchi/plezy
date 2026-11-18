import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../mpv/video.dart' show videoSurfaceDetached;
import '../../screens/youtube/youtube_strings.dart';
import '../../theme/gapped_track_shape.dart';
import '../../theme/player_style.dart';
import '../../theme/retrowave_colors.dart';
import '../app_icon.dart';

/// A playing video the bottom bar can show and control: the Plex player or
/// the YouTube player, minimized.
abstract class VideoMiniSession {
  /// `plex` or `youtube`. Opening a player of the other kind stops this one.
  String get kind;
  String get title;
  String? get subtitle;
  bool get isPlaying;
  Duration get position;
  Duration get duration;
  bool get canNext;

  /// 0 to 1.
  double get volume;

  void togglePlay();
  void seekBy(Duration delta);
  void next();
  void setVolume(double volume);

  /// Moves the native video into the bar, in physical pixels of the view.
  void placeVideo({required int left, required int top, required int right, required int bottom, required double dpr});

  /// Back to the full player.
  void expand();

  /// Ends playback and closes the player.
  void stop();
}

/// The minimized video, if any. The profile shell shows [VideoMiniPlayerBar]
/// while [session] is set.
class VideoMiniPlayer extends ChangeNotifier {
  VideoMiniPlayer._();
  static final instance = VideoMiniPlayer._();

  static const double barHeight = 96;

  VideoMiniSession? _session;
  VideoMiniSession? get session => _session;
  bool get active => _session != null;

  void show(VideoMiniSession session) {
    _session = session;
    videoSurfaceDetached.value = true;
    notifyListeners();
  }

  /// Removes [session] if it is the one shown. The full player's video
  /// surfaces report their own rect again from here on.
  void clear(VideoMiniSession session) {
    if (!identical(_session, session)) return;
    _session = null;
    videoSurfaceDetached.value = false;
    notifyListeners();
  }

  /// A new player of another kind is opening: the minimized one stops.
  void stopOtherThan(String kind) {
    final session = _session;
    if (session != null && session.kind != kind) session.stop();
  }
}

/// A page route that can step aside for the mini-player: while [minimized],
/// it covers nothing, takes no input, is not the current route (so the
/// player's keyboard handling and focus stand down) and a back gesture goes
/// to the page beneath it instead of closing the player.
mixin MinimizableRoute<T> on ModalRoute<T> {
  bool _minimized = false;
  Route<dynamic>? _below;

  bool get minimized => _minimized;

  set minimized(bool value) {
    if (_minimized == value) return;
    _minimized = value;
    final entries = overlayEntries;
    if (entries.isNotEmpty) entries.first.opaque = opaque;
    changedInternalState();
  }

  @override
  bool get opaque => !_minimized && super.opaque;

  @override
  bool get isCurrent => !_minimized && super.isCurrent;

  /// True while this route is the top of its navigator, minimized or not.
  bool get isTopRoute => super.isCurrent;

  @override
  Widget buildModalBarrier() => _minimized ? const IgnorePointer(child: SizedBox.expand()) : super.buildModalBarrier();

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    _below = previousRoute;
    super.didChangePrevious(previousRoute);
  }

  @override
  RoutePopDisposition get popDisposition => _minimized ? RoutePopDisposition.doNotPop : super.popDisposition;

  @override
  void onPopInvokedWithResult(bool didPop, T? result) {
    if (!_minimized) {
      super.onPopInvokedWithResult(didPop, result);
      return;
    }
    // Back on the page under the minimized player: close that page.
    final below = _below;
    final nav = navigator;
    if (didPop || nav == null || below == null || below.isFirst || !below.isActive) return;
    nav.removeRouteBelow(this);
  }
}

/// The bar along the bottom of the app while a video is minimized.
class VideoMiniPlayerBar extends StatefulWidget {
  const VideoMiniPlayerBar({super.key, required this.session});

  final VideoMiniSession session;

  @override
  State<VideoMiniPlayerBar> createState() => _VideoMiniPlayerBarState();
}

class _VideoMiniPlayerBarState extends State<VideoMiniPlayerBar> {
  static const _videoWidth = 142.0;
  static const _videoHeight = 80.0;
  static const _videoLeft = 20.0;

  final _videoKey = GlobalKey();
  Timer? _tick;
  List<int>? _sent;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant VideoMiniPlayerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      _sent = null;
      _stopping = false;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _placeVideo() {
    if (!mounted) return;
    final box = _videoKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final origin = box.localToGlobal(Offset.zero);
    final rect = [
      (origin.dx * dpr).floor(),
      (origin.dy * dpr).floor(),
      ((origin.dx + box.size.width) * dpr).ceil(),
      ((origin.dy + box.size.height) * dpr).ceil(),
    ];
    final sent = _sent;
    if (sent != null && listEquals(sent, rect)) return;
    _sent = rect;
    widget.session.placeVideo(left: rect[0], top: rect[1], right: rect[2], bottom: rect[3], dpr: dpr);
  }

  static String _time(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _placeVideo());
    final session = widget.session;
    final style = PlayerStyle.of(context);
    final gradient = style.progressGradient ?? const [RetroColors.cyan, RetroColors.magenta];
    final position = session.position;
    final duration = session.duration;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final theme = Theme.of(context);
    const muted = Color(0xB3F2EEFF);

    return SizedBox(
      height: VideoMiniPlayer.barHeight,
      child: Material(
        type: MaterialType.transparency,
        child: CustomPaint(
        // Paints the bar around a hole: the native video shows through it.
        painter: _BarPainter(
          hole: const Rect.fromLTWH(_videoLeft, (VideoMiniPlayer.barHeight - _videoHeight) / 2, _videoWidth, _videoHeight),
          color: RetroColors.rock,
          border: RetroColors.outline,
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 3,
              child: Stack(
                children: [
                  const ColoredBox(color: RetroColors.outline, child: SizedBox.expand()),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: LinearGradient(colors: gradient)),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(left: _videoLeft, right: 20),
                child: Row(
                  children: [
                    Tooltip(
                      message: YtStrings.openPlayer,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: session.expand,
                          child: SizedBox(key: _videoKey, width: _videoWidth, height: _videoHeight),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 260,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: session.expand,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: RetroColors.moon,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (session.subtitle case final subtitle? when subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _BarButton(
                            icon: Symbols.replay_10_rounded,
                            tooltip: YtStrings.back10s,
                            onPressed: () => session.seekBy(const Duration(seconds: -10)),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: session.isPlaying ? YtStrings.pause : YtStrings.play,
                            child: Material(
                              color: style.playButtonFill ?? RetroColors.violet,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  session.togglePlay();
                                  setState(() {});
                                },
                                child: SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: Center(
                                    child: AppIcon(
                                      session.isPlaying ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                                      fill: 1,
                                      size: 20,
                                      color: style.playButtonIcon ?? RetroColors.night,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _BarButton(
                            icon: Symbols.forward_30_rounded,
                            tooltip: YtStrings.forward30s,
                            onPressed: () => session.seekBy(const Duration(seconds: 30)),
                          ),
                          if (session.canNext) ...[
                            const SizedBox(width: 4),
                            _BarButton(icon: Symbols.skip_next_rounded, tooltip: YtStrings.nextItem, onPressed: session.next),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      duration > Duration.zero ? '${_time(position)} / ${_time(duration)}' : _time(position),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 12),
                    AppIcon(
                      session.volume <= 0 ? Symbols.volume_off_rounded : Symbols.volume_up_rounded,
                      size: 20,
                      color: RetroColors.moon,
                    ),
                    SizedBox(
                      width: 96,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          trackGap: 0,
                          trackShape: GappedTrackShape(activeGradient: gradient),
                          activeTrackColor: gradient.last,
                          inactiveTrackColor: RetroColors.outline,
                          thumbColor: RetroColors.moon,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          tickMarkShape: SliderTickMarkShape.noTickMark,
                        ),
                        child: Slider(
                          value: session.volume.clamp(0.0, 1.0),
                          onChanged: (v) {
                            session.setVolume(v);
                            setState(() {});
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _BarButton(icon: Symbols.open_in_full_rounded, tooltip: YtStrings.openPlayer, onPressed: session.expand),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: YtStrings.stopAndClose,
                      child: OutlinedButton.icon(
                        onPressed: _stopping
                            ? null
                            : () {
                                setState(() => _stopping = true);
                                session.stop();
                              },
                        icon: const AppIcon(Symbols.stop_rounded, fill: 1, size: 16, color: RetroColors.moon),
                        label: Text(YtStrings.stop),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: RetroColors.moon,
                          backgroundColor: RetroColors.magenta.withValues(alpha: 0.14),
                          side: const BorderSide(color: RetroColors.magenta),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: AppIcon(icon, size: 22, color: RetroColors.moon),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({required this.hole, required this.color, required this.border});

  final Rect hole;
  final Color color;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final holeRRect = RRect.fromRectAndRadius(hole, const Radius.circular(8));
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(holeRRect);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawRRect(
      holeRRect,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawLine(Offset.zero, Offset(size.width, 0), Paint()..color = border);
  }

  @override
  bool shouldRepaint(covariant _BarPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.color != color || oldDelegate.border != border;
}
