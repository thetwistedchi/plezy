import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../i18n/retro_strings.dart';
import '../providers/catalog_sources_provider.dart';
import '../services/browser/browser_controller.dart';
import '../services/browser/browser_native.dart';
import '../services/fullscreen_state_manager.dart';
import '../utils/app_logger.dart';
import '../utils/external_url.dart';

/// Fork, Android and Windows: a Free on plex.tv title playing in Plex Web, full screen
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
    ).push(
      MaterialPageRoute<void>(
        builder: (_) => Platform.isWindows
            ? _FreePlexWindowsPage(url: url, plexToken: token)
            : FreePlexPlayerScreen(url: url, plexToken: token),
      ),
    );
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

/// Windows: Plex Web in a WebView2 page of the in-app browser's engine,
/// below a slim bar with Close and "Open in browser" (the fallback when a
/// title does not play here).
class _FreePlexWindowsPage extends StatefulWidget {
  const _FreePlexWindowsPage({required this.url, this.plexToken});

  final String url;
  final String? plexToken;

  @override
  State<_FreePlexWindowsPage> createState() => _FreePlexWindowsState();
}

class _FreePlexWindowsState extends State<_FreePlexWindowsPage> {
  static const _tabId = 900001;
  static const _barHeight = 40.0;

  final _pageKey = GlobalKey();
  StreamSubscription<BrowserEvent>? _events;
  final _approved = <String>{};
  List<int>? _sentRect;
  Timer? _rectTimer;
  bool _enteredFullscreen = false;
  bool _failed = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final manager = FullscreenStateManager();
    if (!manager.isFullscreen) {
      _enteredFullscreen = true;
      unawaited(manager.enterFullscreen());
    }
    _events = BrowserNative.instance.events.where((e) => e.tab == _tabId).listen(_onEvent);
    // The page's place is measured again while it is open: the route's
    // transition and the switch to full screen move it without a rebuild.
    _rectTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _syncRect());
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await BrowserController.instance.showStandalone(_tabId, widget.url);
      _sentRect = null;
      _syncRect();
      appLogger.i('Free on plex.tv: page opened in the app (${_sentRect ?? 'no place yet'})');
    } catch (e) {
      appLogger.w('Free on plex.tv: WebView2 could not start', error: e);
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onEvent(BrowserEvent e) {
    switch (e.type) {
      case 'loaded':
        appLogger.d('Free on plex.tv: page loaded (ok ${e.flag('ok')}, error ${e.integer('error')})');
      case 'loading' || 'state':
        final url = e.str('url');
        if (e.type == 'loading') appLogger.d('Free on plex.tv: loading ${Uri.tryParse(url ?? '')?.host ?? ''}');
        if (url != null) unawaited(_maybeApproveSignIn(url));
      case 'shortcut':
        final key = e.str('key');
        if (key == 'closeTab' || key == 'back') unawaited(_close());
      case 'crashed':
        appLogger.w('Free on plex.tv: page process failed (kind ${e.integer('kind')})');
        unawaited(BrowserController.instance.closeStandalone(_tabId));
        if (mounted) setState(() => _failed = true);
    }
  }

  /// Plex's sign-in page asks to approve a code for this device; with the
  /// app's Plex sign-in it is approved here and Plex Web continues signed in.
  Future<void> _maybeApproveSignIn(String url) async {
    final token = widget.plexToken;
    if (token == null || token.isEmpty || !url.startsWith('https://app.plex.tv/auth')) return;
    final hash = url.contains('#') ? url.substring(url.indexOf('#') + 1) : '';
    final query = hash.contains('?') ? hash.substring(hash.indexOf('?') + 1) : hash;
    final params = <String, String>{};
    for (final part in query.split('&')) {
      final i = part.indexOf('=');
      if (i > 0) params[part.substring(0, i)] = Uri.decodeComponent(part.substring(i + 1));
    }
    final code = params['code'];
    if (code == null || _approved.contains(code) || _approved.length >= 3) return;
    _approved.add(code);
    try {
      final response = await http
          .put(
            Uri.parse('https://plex.tv/api/v2/pins/link'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/x-www-form-urlencoded',
              'X-Plex-Client-Identifier': 'plezy-retrowave-link',
              'X-Plex-Token': token,
              'X-Plex-Product': 'Plex Web',
              'X-Plex-Platform': 'Chrome',
              'X-Plex-Device': 'Windows',
              'X-Plex-Device-Name': 'Plezy Retrowave (Plex Web)',
            },
            body: 'code=${Uri.encodeQueryComponent(code)}',
          )
          .timeout(const Duration(seconds: 6));
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      appLogger.i('Free on plex.tv: Plex sign-in code approved: $ok');
      if (!ok) return;
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      final forward = params['forwardUrl'];
      if (!mounted || _closing || forward == null || forward.isEmpty) return;
      await BrowserController.instance.navigateStandalone(_tabId, forward);
    } catch (e) {
      appLogger.w('Free on plex.tv: Plex sign-in code not approved', error: e);
    }
  }

  void _syncRect() {
    if (!mounted || _closing) return;
    final box = _pageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return;
    final position = box.localToGlobal(Offset.zero);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final rect = [
      (position.dx * dpr).floor(),
      (position.dy * dpr).floor(),
      ((position.dx + box.size.width) * dpr).ceil(),
      ((position.dy + box.size.height) * dpr).ceil(),
    ];
    final sent = _sentRect;
    if (sent != null && sent[0] == rect[0] && sent[1] == rect[1] && sent[2] == rect[2] && sent[3] == rect[3]) return;
    _sentRect = rect;
    unawaited(
      BrowserController.instance.setPageRect(left: rect[0], top: rect[1], right: rect[2], bottom: rect[3]),
    );
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.url);
    if (uri != null) await openExternalUrl(uri);
    await _close();
  }

  @override
  void dispose() {
    _closing = true;
    _rectTimer?.cancel();
    unawaited(_events?.cancel());
    unawaited(BrowserController.instance.closeStandalone(_tabId));
    if (_enteredFullscreen) unawaited(FullscreenStateManager().exitFullscreen());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRect());
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => unawaited(_close())},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Column(
            children: [
              SizedBox(
                height: _barHeight,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: RetroStrings.close,
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                      onPressed: () => unawaited(_close()),
                    ),
                    Expanded(
                      child: Text(
                        RetroStrings.freeOnPlex,
                        style: theme.textTheme.titleSmall?.copyWith(color: Colors.white70),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => unawaited(_openExternal()),
                      icon: const Icon(Icons.open_in_new, size: 18, color: Colors.white70),
                      label: Text(RetroStrings.freeOnPlexOpenInBrowser, style: const TextStyle(color: Colors.white70)),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              Expanded(
                child: _failed
                    ? Center(
                        child: Text(
                          RetroStrings.freeOnPlexPageFailed,
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : SizedBox.expand(key: _pageKey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
