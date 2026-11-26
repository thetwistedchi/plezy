import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/retro_strings.dart';
import '../../mpv/mpv.dart';
import '../../widgets/app_icon.dart';

/// Fork: plays a video found on a web page in the app's own player (mpv),
/// with the same decoding, HDR handling and audio output as everything else.
class WebVideoPlayerScreen extends StatefulWidget {
  const WebVideoPlayerScreen({super.key, required this.url, required this.title, this.referer});

  final String url;
  final String title;
  final String? referer;

  static Future<void> open(BuildContext context, {required String url, required String title, String? referer}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => WebVideoPlayerScreen(url: url, title: title, referer: referer)),
      );

  @override
  State<WebVideoPlayerScreen> createState() => _WebVideoPlayerScreenState();
}

class _WebVideoPlayerScreenState extends State<WebVideoPlayerScreen> {
  late final Player _player = Player();
  final _subs = <StreamSubscription<Object?>>[];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_player.streams.position.listen((p) => setState(() => _position = p)))
      ..add(_player.streams.duration.listen((d) => setState(() => _duration = d)))
      ..add(_player.streams.playing.listen((p) => setState(() => _playing = p)));
    unawaited(
      _player.open(Media(widget.url, headers: {if (widget.referer != null) 'Referer': widget.referer!})),
    );
    _poke();
  }

  @override
  void dispose() {
    _hide?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_player.dispose());
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
    unawaited(_playing ? _player.pause() : _player.play());
    _poke();
  }

  void _seekBy(int seconds) {
    final target = _position + Duration(seconds: seconds);
    unawaited(_player.seek(target < Duration.zero ? Duration.zero : target));
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
      Navigator.of(context).maybePop();
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
      backgroundColor: Colors.black,
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
                Video(player: _player),
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
                                  icon: const AppIcon(Symbols.arrow_back_rounded, color: Colors.white),
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
                                icon: const AppIcon(Symbols.replay_10_rounded, color: Colors.white),
                                onPressed: () => _seekBy(-10),
                              ),
                              IconButton(
                                icon: AppIcon(
                                  _playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                                  color: Colors.white,
                                ),
                                onPressed: _toggle,
                              ),
                              IconButton(
                                tooltip: RetroStrings.forward10,
                                icon: const AppIcon(Symbols.forward_10_rounded, color: Colors.white),
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
                                          unawaited(_player.seek(Duration(milliseconds: v.round())));
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
