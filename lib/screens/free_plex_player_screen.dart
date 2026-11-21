import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/catalog_sources_provider.dart';
import '../services/fullscreen_state_manager.dart';
import '../utils/app_logger.dart';

/// Fork, Android: a Free on plex.tv title playing in Plex Web, full screen
/// and without the browser around it (android/.../browser/BrowserPlugin,
/// `plezy/plex_player`). Playback starts by itself; Back closes the page.
/// Plex Web is signed in with the app's Plex account (its active profile),
/// so watch history and progress are kept there too.
class FreePlexPlayerScreen extends StatefulWidget {
  const FreePlexPlayerScreen({super.key, required this.url, this.plexToken});

  final String url;
  final String? plexToken;

  static Future<void> open(BuildContext context, String url) async {
    String? token;
    try {
      final session = await context.read<CatalogSourcesProvider>().resolvePlexSession();
      if (session != null && session.accessToken.isNotEmpty) token = session.accessToken;
    } catch (e) {
      appLogger.d('Free on plex.tv: no Plex sign-in for Plex Web: $e');
    }
    if (!context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => FreePlexPlayerScreen(url: url, plexToken: token)));
  }

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
          creationParams: {'url': widget.url, 'plexToken': widget.plexToken ?? ''},
          creationParamsCodec: const StandardMessageCodec(),
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
          },
        ),
      ),
    );
  }
}
