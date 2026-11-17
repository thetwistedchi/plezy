import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../services/youtube/youtube_webview.dart';
import '../../utils/app_logger.dart';
import 'youtube_strings.dart';
import 'youtube_routes.dart';

/// Signs in to youtube.com inside the player's browser profile, so embedded
/// playback uses the account's YouTube Premium.
class YouTubeWebSignInScreen extends StatefulWidget {
  const YouTubeWebSignInScreen({super.key});

  static final Uri _signInUrl = Uri.https('accounts.google.com', '/ServiceLogin', {
    'service': 'youtube',
    'continue': 'https://www.youtube.com/',
  });

  /// Removes the player's YouTube cookies.
  static Future<void> signOut() async {
    final controller = WebviewController();
    try {
      await YouTubeWebView.ensureReady();
      await controller.initialize();
      await controller.clearCookies();
    } catch (e) {
      appLogger.w('YouTube player sign-out failed', error: e);
    } finally {
      unawaited(controller.dispose());
    }
  }

  @override
  State<YouTubeWebSignInScreen> createState() => _YouTubeWebSignInScreenState();
}

class _YouTubeWebSignInScreenState extends State<YouTubeWebSignInScreen> {
  final _controller = WebviewController();
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await YouTubeWebView.ensureReady();
      if (await WebviewController.getWebViewVersion() == null) {
        if (mounted) setState(() => _error = YtStrings.webviewMissing);
        return;
      }
      await _controller.initialize();
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
      await _controller.loadUrl(YouTubeWebSignInScreen._signInUrl.toString());
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(YtStrings.signInPlayer),
        actions: [
          const YouTubeHomeButton(),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(YtStrings.done)),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, textAlign: TextAlign.center))
          : !_ready
          ? const Center(child: CircularProgressIndicator())
          : Webview(_controller),
    );
  }
}
