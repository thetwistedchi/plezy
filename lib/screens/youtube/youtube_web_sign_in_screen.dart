import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/youtube/youtube_webview.dart';
import '../../utils/app_logger.dart';
import 'youtube_strings.dart';
import 'youtube_routes.dart';

/// Signs in to youtube.com inside the player's browser profile, so embedded
/// playback uses the account's YouTube Premium. The page is a native WebView2
/// (windows/runner/youtube) placed beneath the transparent body.
class YouTubeWebSignInScreen extends StatefulWidget {
  const YouTubeWebSignInScreen({super.key});

  static final Uri _signInUrl = Uri.https('accounts.google.com', '/ServiceLogin', {
    'service': 'youtube',
    'continue': 'https://www.youtube.com/',
  });

  /// Removes the player's YouTube cookies.
  static Future<void> signOut() async {
    try {
      await YouTubeWebView.clearCookies();
    } catch (e) {
      appLogger.w('YouTube player sign-out failed', error: e);
    }
  }

  @override
  State<YouTubeWebSignInScreen> createState() => _YouTubeWebSignInScreenState();
}

class _YouTubeWebSignInScreenState extends State<YouTubeWebSignInScreen> {
  bool _ready = false;
  String? _error;
  List<int>? _sent;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      if (await YouTubeWebView.runtimeVersion() == null) {
        if (mounted) setState(() => _error = YtStrings.webviewMissing);
        return;
      }
      await YouTubeWebView.openSignIn(YouTubeWebSignInScreen._signInUrl);
      if (!mounted) {
        unawaited(YouTubeWebView.closeSignIn());
        return;
      }
      _sent = null;
      setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    unawaited(YouTubeWebView.closeSignIn().catchError((_) {}));
    super.dispose();
  }

  void _report(BuildContext context) {
    if (!mounted || !_ready) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return;
    final position = box.localToGlobal(Offset.zero);
    final size = box.size;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final rect = [
      (position.dx * dpr).floor(),
      (position.dy * dpr).floor(),
      ((position.dx + size.width) * dpr).ceil(),
      ((position.dy + size.height) * dpr).ceil(),
    ];
    final sent = _sent;
    if (sent != null && sent[0] == rect[0] && sent[1] == rect[1] && sent[2] == rect[2] && sent[3] == rect[3]) return;
    _sent = rect;
    unawaited(
      YouTubeWebView.setSignInRect(
        left: rect[0],
        top: rect[1],
        right: rect[2],
        bottom: rect[3],
      ).catchError((_) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ready ? Colors.transparent : null,
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
          : LayoutBuilder(
              builder: (context, constraints) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _report(context));
                return const SizedBox.expand();
              },
            ),
    );
  }
}
