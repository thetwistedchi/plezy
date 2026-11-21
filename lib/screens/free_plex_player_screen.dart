import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/fullscreen_state_manager.dart';

/// Fork, Android: a Free on plex.tv title playing in Plex Web, full screen
/// and without the browser around it (android/.../browser/BrowserPlugin,
/// `plezy/plex_player`). Playback starts by itself; Back closes the page.
class FreePlexPlayerScreen extends StatefulWidget {
  const FreePlexPlayerScreen({super.key, required this.url});

  final String url;

  static Future<void> open(BuildContext context, String url) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FreePlexPlayerScreen(url: url)));

  @override
  State<FreePlexPlayerScreen> createState() => _FreePlexPlayerScreenState();
}

class _FreePlexPlayerScreenState extends State<FreePlexPlayerScreen> {
  bool _enteredFullscreen = false;

  @override
  void initState() {
    super.initState();
    final manager = FullscreenStateManager();
    if (!manager.isFullscreen) {
      _enteredFullscreen = true;
      unawaited(manager.enterFullscreen());
    }
  }

  @override
  void dispose() {
    if (_enteredFullscreen) unawaited(FullscreenStateManager().exitFullscreen());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        // The remote's arrows and OK belong to the page (Plex's controls);
        // Back stays with the app and closes this page.
        onKeyEvent: (node, event) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.mediaPlayPause ||
              key == LogicalKeyboardKey.space) {
            return KeyEventResult.skipRemainingHandlers;
          }
          return KeyEventResult.ignored;
        },
        child: AndroidView(
          viewType: 'plezy/plex_player',
          creationParams: {'url': widget.url},
          creationParamsCodec: const StandardMessageCodec(),
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
          },
        ),
      ),
    );
  }
}
