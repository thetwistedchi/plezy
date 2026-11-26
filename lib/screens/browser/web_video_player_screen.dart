import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/retro_strings.dart';
import '../../mpv/mpv.dart';
import '../../services/playback_coordinator.dart';
import '../../services/youtube/youtube_webview.dart';
import '../../widgets/app_icon.dart';

/// Fork: plays a video found on a web page in the app's own player (mpv),
/// with the same decoding, HDR handling and audio output as everything else.
class WebVideoPlayerScreen extends StatefulWidget {
  const WebVideoPlayerScreen({super.key, required this.url, required this.title, this.referer});

  final String url;
  final String title;
  final String? referer;

  static Future<void> open(BuildContext context, {required String url, required String title, String? referer}) =>
      // Like the main player: no transition, and nothing painted over the
      // native video plane beneath Flutter.
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => WebVideoPlayerScreen(url: url, title: title, referer: referer),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );

  @override
  State<WebVideoPlayerScreen> createState() => _WebVideoPlayerScreenState();
}

class _WebVideoPlayerScreenState extends State<WebVideoPlayerScreen> {
  Player? _player;
  final _subs = <StreamSubscription<Object?>>[];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _controls = true;
  bool _disposed = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    // The video plane sits beneath Flutter, where YouTube's hidden history
    // view would show through.
    YouTubeWebView.hiddenVisitBlockers.value++;
    unawaited(_start());
    _poke();
  }

  Future<void> _start() async {
    // Like the main player: a playing music session goes first.
    await PlaybackCoordinator.instance.claimVideo();
    if (_disposed) return;
    final player = Player();
    _player = player;
    _subs
      ..add(player.streams.position.listen((p) => _update(() => _position = p)))
      ..add(player.streams.duration.listen((d) => _update(() => _duration = d)))
      ..add(player.streams.playing.listen((p) => _update(() => _playing = p)))
      ..add(player.streams.fileLoadFailed.listen((_) => _failed()));
    setState(() {});
    final referer = widget.referer;
    final refererUri = referer == null ? null : Uri.tryParse(referer);
    final origin = refererUri != null && (refererUri.isScheme('http') || refererUri.isScheme('https'))
        ? refererUri.origin
        : null;
    await player.open(
      Media(widget.url, headers: {'Referer': ?referer, 'Origin': ?origin}),
    );
  }

  /// The address was no playable stream (protected or not a video).
  void _failed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(RetroStrings.videoNotPlayable)));
    unawaited(Navigator.of(context).maybePop());
  }

  void _update(VoidCallback change) {
    if (mounted) setState(change);
  }

  @override
  void dispose() {
    _disposed = true;
    YouTubeWebView.hiddenVisitBlockers.value--;
    _hide?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    final player = _player;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  void _poke() {
    _hide?.cancel();
    if (!_controls) setState(() => _controls = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing) setState(() => _controls = false);
    });
  }

  void _toggle() {
    final player = _player;
    if (player == null) return;
    unawaited(_playing ? player.pause() : player.play());
    _poke();
  }

  void _seekBy(int seconds) {
    final target = _position + Duration(seconds: seconds);
    unawaited(_player?.seek(target < Duration.zero ? Duration.zero : target));
    _poke();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _toggle();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-10);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(10);
    } else if (key == LogicalKeyboardKey.escape) {
      unawaited(Navigator.of(context).maybePop());
    } else {
      _poke();
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  static String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          onHover: (_) => _poke(),
          child: GestureDetector(
            onTap: _toggle,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_player case final player?)
                  Video(player: player)
                else
                  const ColoredBox(color: Colors.black, child: Center(child: CircularProgressIndicator())),
                AnimatedOpacity(
                  opacity: _controls ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_controls,
                    child: Column(
                      children: [
                        Container(
                          color: Colors.black54,
                          child: SafeArea(
                            bottom: false,
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const AppIcon.retro(Symbols.arrow_back_rounded, color: Colors.white, retroSoft: true),
                                  onPressed: () => Navigator.of(context).maybePop(),
                                ),
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          color: Colors.black54,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: RetroStrings.back10,
                                icon: const AppIcon.retro(Symbols.replay_10_rounded, color: Colors.white, retroSoft: true),
                                onPressed: () => _seekBy(-10),
                              ),
                              IconButton(
                                icon: AppIcon.retro(
                                  _playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                                  color: Colors.white,
                                  retroSoft: true,
                                ),
                                onPressed: _toggle,
                              ),
                              IconButton(
                                tooltip: RetroStrings.forward10,
                                icon: const AppIcon.retro(Symbols.forward_10_rounded, color: Colors.white, retroSoft: true),
                                onPressed: () => _seekBy(10),
                              ),
                              Text(_fmt(_position), style: const TextStyle(color: Colors.white)),
                              Expanded(
                                child: Slider(
                                  value: total <= 0 ? 0 : _position.inMilliseconds.clamp(0, total).toDouble(),
                                  max: total <= 0 ? 1 : total.toDouble(),
                                  onChanged: total <= 0
                                      ? null
                                      : (v) {
                                          unawaited(_player?.seek(Duration(milliseconds: v.round())));
                                          _poke();
                                        },
                                ),
                              ),
                              Text(_fmt(_duration), style: const TextStyle(color: Colors.white)),
                            ],
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
      ),
    );
  }
}
