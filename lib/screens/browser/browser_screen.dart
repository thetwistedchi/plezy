import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../focus/dpad_navigator.dart';
import '../../focus/focusable_text_field.dart';
import '../../focus/key_event_utils.dart';
import '../../i18n/retro_strings.dart';
import '../../services/browser/adblock_lists.dart';
import '../../services/file_picker_service.dart';
import '../../services/browser/browser_bookmarks.dart';
import '../../services/browser/browser_controller.dart';
import '../../services/browser/browser_history.dart';
import '../../services/browser/browser_native.dart';
import '../../services/browser/browser_settings.dart';
import '../../theme/mono_tokens.dart';
import '../../theme/page_backdrop.dart';
import '../../theme/retrowave_colors.dart';
import '../../utils/app_logger.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/mini_player/video_mini_player.dart' show MinimizableRoute;
import 'browser_icon.dart';
import 'adblock_lists_screen.dart';
import 'browser_history_page.dart';
import 'browser_settings_screen.dart';

/// The in-app browser: tabs, address bar, bookmarks. Each tab's page is a
/// native WebView2 placed beneath the transparent [_PageSlot].
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  static Future<void> open(BuildContext context, {String? url}) async {
    final controller = BrowserController.instance;
    await controller.load();
    if (url != null) await controller.newTab(url: url);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      NoPageBackdropRoute<void>(settings: const RouteSettings(name: 'browser'), builder: (_) => const BrowserScreen()),
    );
  }

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _Notice {
  const _Notice(this.text, {this.action, this.onAction, this.action2, this.onAction2, this.warning = false});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final String? action2;
  final VoidCallback? onAction2;
  final bool warning;
}

const _riskyExtensions = {
  'exe', 'msi', 'msix', 'appx', 'bat', 'cmd', 'com', 'ps1', 'psm1', 'vbs', 'vbe', 'js', 'jse', 'wsf', 'scr', 'pif',
  'hta', 'cpl', 'reg', 'lnk', 'jar', 'apk', 'dll', 'iso', 'img', 'vhd', 'vhdx',
};

class _BrowserScreenState extends State<BrowserScreen> {
  final _controller = BrowserController.instance;
  final _settings = BrowserSettings.instance;
  final _bookmarks = BrowserBookmarks.instance;
  final _address = TextEditingController();
  final _addressFocus = FocusNode(debugLabel: 'browser-address');
  final _keys = FocusNode(debugLabel: 'browser');
  final _toolbarFocus = FocusNode(debugLabel: 'browser-toolbar', canRequestFocus: false, skipTraversal: true);
  final List<StreamSubscription<Object?>> _subs = [];
  _Notice? _notice;
  int _overlays = 0;
  final _addressLink = LayerLink();
  final _suggestPortal = OverlayPortalController();
  List<_Suggestion> _suggestions = const [];
  int _highlighted = -1;
  bool? _routeCurrent;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _bookmarks.addListener(_onChanged);
    _settings.addListener(_onChanged);
    BrowserHistory.instance.addListener(_onChanged);
    AdblockManager.instance.addListener(_onChanged);
    MinimizableRoute.minimizedRevision.addListener(_onChanged);
    _subs.add(_controller.prompts.listen(_onPrompt));
    _subs.add(_controller.shortcuts.listen(_onShortcut));
    _subs.add(
      _controller.pageFocused.listen((_) {
        // A click into the page: close what lies over it.
        final popup = _popupContext;
        if (popup != null && popup.mounted) Navigator.pop(popup);
        if (_addressFocus.hasFocus) _addressFocus.unfocus();
      }),
    );
    // Android TV: Up at the top of the page returns to the toolbar.
    _subs.add(
      _controller.pageLeft.listen((_) {
        final first = _toolbarFocus.traversalDescendants.where((n) => n.canRequestFocus).firstOrNull;
        appLogger.d('Browser: back to the toolbar (${first?.debugLabel ?? 'no button'})');
        (first ?? _keys).requestFocus();
      }),
    );
    _addressFocus.addListener(_onAddressFocus);
    _address.addListener(_onAddressText);
    unawaited(_bookmarks.load());
    _syncAddress();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.active?.url == null) _addressFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _controller.removeListener(_onChanged);
    _bookmarks.removeListener(_onChanged);
    _settings.removeListener(_onChanged);
    BrowserHistory.instance.removeListener(_onChanged);
    AdblockManager.instance.removeListener(_onChanged);
    MinimizableRoute.minimizedRevision.removeListener(_onChanged);
    unawaited(_controller.setShown(false));
    if (_remoteStarted) unawaited(_controller.stopPhoneRemote());
    _address.dispose();
    _addressFocus.dispose();
    _keys.dispose();
    _toolbarFocus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    _syncAddress();
    setState(() {});
  }

  void _syncAddress() {
    if (_addressFocus.hasFocus) return;
    final url = _controller.active?.url ?? '';
    if (_address.text != url) _address.text = url;
  }

  /// The first click into the address bar selects the whole address, like
  /// in other browsers; a further click places the cursor.
  bool _selectOnTap = false;

  void _selectAddress() {
    _address.selection = TextSelection(baseOffset: 0, extentOffset: _address.text.length);
  }

  void _onAddressTap() {
    if (!_selectOnTap) return;
    _selectOnTap = false;
    // After the text field has placed the cursor for this click.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_addressFocus.hasFocus) _selectAddress();
    });
  }

  void _onAddressFocus() {
    if (_addressFocus.hasFocus) {
      _selectOnTap = true;
      _selectAddress();
    } else {
      _selectOnTap = false;
      if (_suggestions.isNotEmpty) _setSuggestions(const []);
      _syncAddress();
    }
  }

  /// Shows the active page only while nothing of Flutter's covers it: the
  /// native view would sit on top of dialogs' input.
  void _syncVisibility() {
    if (!mounted) return;
    unawaited(_controller.setShown((_routeCurrent ?? true) && _overlays == 0));
  }

  Future<T?> _overlay<T>(Future<T?> Function() show) async {
    _overlays++;
    _syncVisibility();
    try {
      return await show();
    } finally {
      _overlays--;
      _syncVisibility();
    }
  }

  // ---- Suggestions ----

  void _onAddressText() {
    if (!_addressFocus.hasFocus) return _setSuggestions(const []);
    final query = _address.text.trim().toLowerCase();
    if (query.length < 3 || query == (_controller.active?.url ?? '').toLowerCase()) {
      return _setSuggestions(const []);
    }
    final seen = <String>{};
    final starts = <_Suggestion>[];
    final contains = <_Suggestion>[];
    void consider(String url, String title, bool bookmark) {
      final key = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
      if (!seen.add(key)) return;
      final bare = key.toLowerCase().replaceFirst(RegExp(r'^https?://(www\.)?'), '');
      final t = title.toLowerCase();
      final s = _Suggestion(url: url, title: title, bookmark: bookmark);
      if (bare.startsWith(query)) {
        starts.add(s);
      } else if (bare.contains(query) || t.contains(query)) {
        contains.add(s);
      }
    }

    for (final b in _bookmarks.items) {
      consider(b.url, b.title, true);
    }
    for (final p in BrowserHistory.instance.recent(BrowserHistory.maxEntries)) {
      consider(p.url, p.title, false);
    }
    _setSuggestions([...starts, ...contains].take(6).toList());
  }

  void _setSuggestions(List<_Suggestion> list) {
    if (list.isEmpty && _suggestions.isEmpty) return;
    final wasShown = _suggestions.isNotEmpty;
    _suggestions = list;
    _highlighted = -1;
    if (list.isNotEmpty) {
      if (!wasShown) _suggestPortal.show();
    } else {
      _suggestPortal.hide();
    }
    if (mounted) setState(() {});
  }

  KeyEventResult _onAddressKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // TV: the on-screen keyboard moves the caret, so Left and Right always
    // leave the field.
    if (PlatformDetector.isTV() && (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight)) {
      _addressFocus.focusInDirection(
        key == LogicalKeyboardKey.arrowLeft ? TraversalDirection.left : TraversalDirection.right,
      );
      return KeyEventResult.handled;
    }
    if (_suggestions.isEmpty) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      final n = _suggestions.length;
      setState(() {
        _highlighted = key == LogicalKeyboardKey.arrowDown
            ? (_highlighted + 1) % n
            : (_highlighted <= 0 ? n - 1 : _highlighted - 1);
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _setSuggestions(const []);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildSuggestions(BuildContext context) {
    final t = tokens(context);
    final box = _addressLink.leaderSize;
    return CompositedTransformFollower(
      link: _addressLink,
      targetAnchor: Alignment.bottomLeft,
      offset: const Offset(0, 4),
      showWhenUnlinked: false,
      child: Align(
        alignment: Alignment.topLeft,
        child: TextFieldTapRegion(
          child: _Cutout(
            radius: t.radiusMd,
            child: SizedBox(
            width: box?.width ?? 600,
            child: _NeonPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _suggestions.length; i++)
                    InkWell(
                      onTap: () {
                        final url = _suggestions[i].url;
                        _setSuggestions(const []);
                        unawaited(_submit(url));
                      },
                      child: Container(
                        color: i == _highlighted ? t.accent.withValues(alpha: 0.16) : null,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        child: Row(
                          children: [
                            BrowserIcon(
                              _suggestions[i].bookmark ? Symbols.bookmark_rounded : Symbols.history_rounded,
                              size: 16,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    if (_suggestions[i].title.isNotEmpty)
                                      TextSpan(text: '${_suggestions[i].title}  ', style: TextStyle(color: t.text)),
                                    TextSpan(
                                      text: _suggestions[i].url,
                                      style: TextStyle(color: t.textMuted, fontSize: 12),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
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
        ),
      ),
    );
  }

  void _setNotice(_Notice? notice) {
    if (mounted) setState(() => _notice = notice);
  }

  // ---- Prompts ----

  Future<void> _onPrompt(BrowserPrompt prompt) async {
    switch (prompt) {
      case PermissionPrompt(:final request, :final kind, :final url, :final site, :final tab):
        final private = _controller.tabs.where((t) => t.id == tab).firstOrNull?.isPrivate ?? false;
        final answer = await _overlay(() => _askPermission(kind, url, canRemember: !private));
        final allow = answer?.$1 ?? false;
        if (answer != null && answer.$2) await _settings.setPermission(site, kind, allow);
        await _controller.answerPermission(request, allow);
      case DownloadPrompt(:final request, :final url, :final path, :final size):
        final target = await _overlay(() => _askDownload(url, path, size));
        await _controller.answerDownload(request, target != null, path: target == null || target.isEmpty ? null : target);
      case PopupBlockedNotice(:final url, :final site, :final redirect):
        final target = Uri.tryParse(url)?.host ?? url;
        _setNotice(
          _Notice(
            redirect
                ? '${RetroStrings.redirectBlocked(site)}: $target'
                : (site.isEmpty ? '${RetroStrings.popupBlocked}: $target' : '${RetroStrings.popupBlockedFrom(site)}: $target'),
            action: RetroStrings.openAnyway,
            onAction: () => unawaited(_controller.newTab(url: url)),
            action2: site.isEmpty ? null : RetroStrings.alwaysAllow,
            onAction2: site.isEmpty ? null : () => unawaited(_controller.setPopupAllowed(site, true)),
          ),
        );
      case HttpFallbackNotice(:final tab, :final httpUrl):
        _setNotice(
          _Notice(
            RetroStrings.httpsFailed,
            action: RetroStrings.loadOverHttp,
            warning: true,
            onAction: () {
              final target = _controller.tabs.where((t) => t.id == tab).firstOrNull;
              unawaited(_controller.go(httpUrl, tab: target, allowHttp: true));
            },
          ),
        );
      case BlockedSchemeNotice():
        _setNotice(_Notice(RetroStrings.schemeBlocked, warning: true));
      case UnresponsiveNotice(:final tab):
        if (tab == _controller.active?.id) {
          _setNotice(
            _Notice(
              RetroStrings.tabUnresponsive,
              action: RetroStrings.reload,
              warning: true,
              onAction: () => unawaited(_controller.reload()),
              action2: RetroStrings.wait,
              onAction2: () {},
            ),
          );
        }
      case CrashedNotice(:final tab):
        if (tab == _controller.active?.id) {
          _setNotice(
            _Notice(
              RetroStrings.tabCrashed,
              action: RetroStrings.reload,
              warning: true,
              onAction: () => unawaited(_controller.reload()),
            ),
          );
        }
    }
  }

  /// The answer and whether to remember it for the site.
  Future<(bool, bool)?> _askPermission(int kind, String url, {required bool canRemember}) {
    final host = Uri.tryParse(url)?.host ?? url;
    var remember = false;
    return showDialog<(bool, bool)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(RetroStrings.permissionAsk(host, RetroStrings.permissionKind(kind))),
              if (canRemember) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: remember,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(RetroStrings.rememberForSite),
                  onChanged: (v) => setDialog(() => remember = v ?? false),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, (false, remember)), child: Text(RetroStrings.block)),
            FilledButton(onPressed: () => Navigator.pop(context, (true, remember)), child: Text(RetroStrings.allow)),
          ],
        ),
      ),
    );
  }

  /// A free file name in [dir]: "name.ext", else "name (1).ext" and so on.
  static String _uniquePath(String dir, String name) {
    final sep = Platform.pathSeparator;
    var path = '$dir$sep$name';
    if (!File(path).existsSync()) return path;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 1; i < 1000; i++) {
      path = '$dir$sep$base ($i)$ext';
      if (!File(path).existsSync()) break;
    }
    return path;
  }

  /// Asks before a download. Returns where to save it ('' = the browser's
  /// own choice in the Windows Downloads folder), or null to cancel.
  Future<String?> _askDownload(String url, String path, int size) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final risky = _riskyExtensions.contains(ext);
    final host = Uri.tryParse(url)?.host ?? '';
    final t = tokens(context);
    final folder = _settings.downloadFolder;
    final defaultFolder = path.contains(Platform.pathSeparator)
        ? path.substring(0, path.lastIndexOf(Platform.pathSeparator))
        : '';
    final shownFolder = Platform.isAndroid ? RetroStrings.downloads : (folder.isNotEmpty ? folder : defaultFolder);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(RetroStrings.downloadTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name.isEmpty ? url : name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              [if (host.isNotEmpty) RetroStrings.downloadFrom(host), if (size > 0) _formatSize(size)].join(' · '),
              style: TextStyle(color: t.textMuted),
            ),
            if (!_settings.askWhereToSave && shownFolder.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(RetroStrings.saveTo(shownFolder), style: TextStyle(color: t.textMuted)),
            ],
            if (risky) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrowserIcon(Symbols.warning_amber_rounded, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(RetroStrings.downloadRisky)),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(RetroStrings.cancel)),
          if (!Platform.isAndroid)
          TextButton(
            onPressed: () async {
              final picked = await FilePickerService.instance.saveFile(
                dialogTitle: RetroStrings.saveAs,
                fileName: name.isEmpty ? null : name,
              );
              if (picked != null && context.mounted) Navigator.pop(context, picked);
            },
            child: Text(RetroStrings.saveAs),
          ),
          if (!_settings.askWhereToSave || Platform.isAndroid)
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                !Platform.isAndroid && folder.isNotEmpty && name.isNotEmpty ? _uniquePath(folder, name) : '',
              ),
              child: Text(RetroStrings.download),
            ),
        ],
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // ---- Actions ----

  void _onShortcut(String key) {
    switch (key) {
      case 'newTab':
        _newTab();
      case 'newPrivateTab':
        _newTab(private: true);
      case 'reopenTab':
        unawaited(_controller.reopenClosed());
      case 'closeTab':
        _closeActive();
      case 'address':
        _addressFocus.requestFocus();
      case 'nextTab':
        unawaited(_controller.selectRelative(1));
      case 'prevTab':
        unawaited(_controller.selectRelative(-1));
      case 'back':
        unawaited(_controller.back());
      case 'forward':
        unawaited(_controller.forward());
    }
  }

  void _newTab({bool private = false}) {
    if (private && !_controller.privateTabsSupported) {
      _setNotice(_Notice(RetroStrings.privateTabsUnsupported, warning: true));
      return;
    }
    unawaited(_controller.newTab(private: private));
    if (_settings.newTabPage != BrowserNewTabPage.custom) _addressFocus.requestFocus();
  }

  void _closeActive() {
    final id = _controller.active?.id;
    if (id != null) unawaited(_controller.close(id));
  }

  Future<void> _submit(String text) async {
    _setNotice(null);
    if (_suggestions.isNotEmpty) _setSuggestions(const []);
    await _controller.go(text);
    _addressFocus.unfocus();
    _keys.requestFocus();
    await _controller.focusPage();
  }

  Future<void> _toggleBookmark() async {
    final tab = _controller.active;
    final url = tab?.url;
    if (tab == null || url == null) return;
    if (_bookmarks.contains(url)) {
      await _bookmarks.remove(url);
    } else {
      await _bookmarks.add(Bookmark(title: tab.title.isEmpty ? tab.host : tab.title, url: url));
    }
  }

  bool _remoteStarted = false;

  /// Android TV: a QR code for the phone remote (PhoneRemoteServer).
  Future<void> _showPhoneRemote() async {
    final url = await _controller.startPhoneRemote();
    if (!mounted) return;
    if (url == null) {
      _setNotice(_Notice(RetroStrings.phoneRemoteNoNetwork, warning: true));
      return;
    }
    _remoteStarted = true;
    BuildContext? dialog;
    final sub = _controller.remoteConnected.listen((_) {
      final d = dialog;
      if (d != null && d.mounted) Navigator.pop(d);
      if (mounted) _setNotice(_Notice(RetroStrings.phoneRemoteConnected));
    });
    try {
      await _overlay(
        () => showDialog<void>(
          context: context,
          builder: (dialogContext) {
            dialog = dialogContext;
            return AlertDialog(
              title: Text(RetroStrings.phoneRemote),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      child: QrImageView(data: url, size: 220, backgroundColor: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(url, style: TextStyle(color: tokens(context).textMuted, fontSize: 12)),
                    const SizedBox(height: 12),
                    Text(RetroStrings.phoneRemoteHint),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _remoteStarted = false;
                    unawaited(_controller.stopPhoneRemote());
                    Navigator.pop(dialogContext);
                  },
                  child: Text(RetroStrings.stopRemote),
                ),
                FilledButton(
                  autofocus: true,
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(RetroStrings.close),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      dialog = null;
      await sub.cancel();
    }
  }

  Future<void> _openSettings() => _controller.openInternal(BrowserController.settingsPage);

  Rect? _rectOf(BuildContext anchor) {
    final box = anchor.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _showBookmarks(Rect anchor) async {
    String? editing;
    final name = TextEditingController();
    final url = await _popup<String>(
      anchor,
      width: 380,
      (context) => StatefulBuilder(
        builder: (context, setPanel) => ListenableBuilder(
          listenable: _bookmarks,
          builder: (context, _) {
            final t = tokens(context);
            final items = _bookmarks.items;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _popupHeader(Symbols.bookmarks_rounded, RetroStrings.bookmarks),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Text(RetroStrings.noBookmarks, style: TextStyle(color: t.textMuted)),
                  ),
                for (final b in items)
                  if (editing == b.url)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: name,
                              autofocus: true,
                              decoration: const InputDecoration(isDense: true),
                              onSubmitted: (v) {
                                unawaited(_bookmarks.rename(b.url, v));
                                setPanel(() => editing = null);
                              },
                            ),
                          ),
                          IconButton(
                            icon: const BrowserIcon(Symbols.check_rounded, size: 18),
                            tooltip: RetroStrings.save,
                            onPressed: () {
                              unawaited(_bookmarks.rename(b.url, name.text));
                              setPanel(() => editing = null);
                            },
                          ),
                          IconButton(
                            icon: const BrowserIcon(Symbols.delete_rounded, size: 18),
                            tooltip: RetroStrings.delete,
                            onPressed: () {
                              unawaited(_bookmarks.remove(b.url));
                              setPanel(() => editing = null);
                            },
                          ),
                        ],
                      ),
                    )
                  else
                    ListTile(
                      dense: true,
                      leading: const BrowserIcon(Symbols.bookmark_rounded, size: 18, fill: 1),
                      title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(b.host, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, b.url),
                      trailing: IconButton(
                        icon: const BrowserIcon(Symbols.edit_rounded, size: 16),
                        tooltip: RetroStrings.renameBookmark,
                        onPressed: () => setPanel(() {
                          editing = b.url;
                          name.text = b.title;
                        }),
                      ),
                    ),
                const SizedBox(height: 6),
              ],
            );
          },
        ),
      ),
    );
    name.dispose();
    if (url != null) await _submit(url);
  }

  Future<String?> _menu(Rect anchor, List<_MenuEntry> items, {bool alignLeft = false}) => _popup<String>(
    anchor,
    width: 280,
    alignLeft: alignLeft,
    (context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            if (item.value == null)
              const Divider(height: 9)
            else
              InkWell(
                onTap: item.enabled ? () => Navigator.pop(context, item.value) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      BrowserIcon(item.icon, size: 18, opacity: item.enabled ? 1 : 0.4),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.label,
                          style: TextStyle(color: item.enabled ? null : tokens(context).textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    ),
  );

  _MenuEntry _menuItem(String value, IconData icon, String label, {bool enabled = true}) =>
      _MenuEntry(value, icon, label, enabled: enabled);

  /// The recently closed tabs to pick from, plus "reopen all".
  Future<void> _closedMenu(Rect anchor, {bool alignLeft = false}) async {
    final closed = _controller.closedTabs.take(10).toList();
    if (closed.isEmpty) return;
    String label(({String url, String title}) e) {
      if (e.url == BrowserController.settingsPage) return RetroStrings.browserSettings;
      if (e.url == BrowserController.filtersPage) return RetroStrings.filterLists;
      if (e.url == BrowserController.historyPage) return RetroStrings.history;
      if (e.title.isNotEmpty) return e.title;
      return Uri.tryParse(e.url)?.host ?? e.url;
    }

    final picked = await _menu(anchor, alignLeft: alignLeft, [
      for (var i = 0; i < closed.length; i++) _menuItem('$i', Symbols.history_rounded, label(closed[i])),
      if (closed.length > 1) ...[
        _MenuEntry.divider,
        _menuItem('all', Symbols.add_rounded, RetroStrings.reopenAllClosed(_controller.closedTabs.length)),
      ],
    ]);
    if (picked == null) return;
    if (picked == 'all') {
      await _controller.reopenAllClosed();
    } else {
      await _controller.reopenClosed(int.parse(picked));
    }
  }

  Future<void> _tabMenu(BrowserTabState tab, Offset position) async {
    final picked = await _menu(position & const Size(1, 1), alignLeft: true, [
      _menuItem('reload', Symbols.refresh_rounded, RetroStrings.reload, enabled: tab.url != null),
      _menuItem('duplicate', Symbols.add_rounded, RetroStrings.duplicateTab),
      _menuItem(
        'mute',
        tab.muted ? Symbols.volume_up_rounded : Symbols.volume_off_rounded,
        tab.muted ? RetroStrings.unmuteTab : RetroStrings.muteTab,
      ),
      _MenuEntry.divider,
      _menuItem('reopen', Symbols.history_rounded, RetroStrings.recentlyClosed, enabled: _controller.canReopen),
      _menuItem('others', Symbols.close_rounded, RetroStrings.closeOtherTabs, enabled: _controller.tabs.length > 1),
      _menuItem('close', Symbols.close_rounded, RetroStrings.closeTab),
    ]);
    switch (picked) {
      case 'reload':
        await _controller.select(tab.id);
        await _controller.reload();
      case 'duplicate':
        await _controller.duplicate(tab.id);
      case 'mute':
        await _controller.setMuted(tab.id, !tab.muted);
      case 'reopen':
        await _closedMenu(position & const Size(1, 1), alignLeft: true);
      case 'others':
        await _controller.closeOthers(tab.id);
      case 'close':
        await _controller.close(tab.id);
    }
  }

  Future<void> _moreMenu(Rect anchor) async {
    final url = _controller.active?.url;
    final internal = _controller.active?.isInternal ?? false;
    final picked = await _menu(anchor, [
      _menuItem('new', Symbols.add_rounded, RetroStrings.newTab),
      _menuItem(
        'private',
        Symbols.visibility_off_rounded,
        RetroStrings.newPrivateTab,
        enabled: _controller.privateTabsSupported,
      ),
      _menuItem('reopen', Symbols.history_rounded, RetroStrings.recentlyClosed, enabled: _controller.canReopen),
      _MenuEntry.divider,
      _menuItem('history', Symbols.history_rounded, RetroStrings.history),
      _menuItem('downloads', Symbols.download_rounded, RetroStrings.downloads),
      if (Platform.isAndroid && PlatformDetector.isTV()) ...[
        _menuItem(
          'pointer',
          _settings.tvPointer ? Symbols.toggle_on_rounded : Symbols.toggle_off_rounded,
          RetroStrings.tvPointer,
        ),
        _menuItem('remote', Symbols.phone_android_rounded, RetroStrings.phoneRemote),
      ],
      _menuItem(
        'external',
        Symbols.open_in_new_rounded,
        RetroStrings.openInDefaultBrowser,
        enabled: url != null && !internal,
      ),
      _MenuEntry.divider,
      _menuItem('settings', Symbols.settings_rounded, RetroStrings.browserSettings),
    ]);
    switch (picked) {
      case 'new':
        _newTab();
      case 'private':
        _newTab(private: true);
      case 'reopen':
        await _closedMenu(anchor);
      case 'history':
        await _controller.openInternal(BrowserController.historyPage);
      case 'downloads':
        await _showDownloads(anchor);
      case 'remote':
        await _showPhoneRemote();
      case 'pointer':
        await _controller.setTvPointer(!_settings.tvPointer);
      case 'external':
        final uri = Uri.tryParse(url ?? '');
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      case 'settings':
        await _openSettings();
    }
  }

  String _siteOf(BrowserTabState? tab) {
    final host = (tab?.host ?? '').toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final labels = host.split('.');
    if (labels.length <= 2) return host;
    final keep = labels.last.length == 2 && labels[labels.length - 2].length <= 3 ? 3 : 2;
    return labels.length <= keep ? host : labels.sublist(labels.length - keep).join('.');
  }

  Widget _buildShieldButton(MonoTokens t, BrowserTabState? tab) {
    final adblock = AdblockManager.instance;
    final site = _siteOf(tab);
    final active = adblock.enabled && (site.isEmpty || !adblock.isOffFor(site));
    final count = tab?.blockedCount ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Builder(
          builder: (anchor) => IconButton(
            icon: BrowserIcon(Symbols.shield_rounded, size: 20, opacity: active ? 1 : 0.35),
            tooltip: RetroStrings.adblock,
            onPressed: () {
              final rect = _rectOf(anchor);
              if (rect != null) unawaited(_showShield(rect));
            },
            visualDensity: VisualDensity.compact,
          ),
        ),
        if (active && count > 0)
          Positioned(
            right: 2,
            bottom: 4,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  count > 999 ? '999+' : '$count',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    // Readable on light and dark accents of every theme.
                    color: t.accent.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The open popup's context, to close it when the user clicks the page.
  BuildContext? _popupContext;

  /// A small panel under [anchor] (a toolbar button, global coordinates),
  /// like a browser's extension popup. It lies over the live page: the page
  /// gets a hole under it ([_Cutout]), so the panel takes the clicks.
  Future<T?> _popup<T>(Rect anchor, WidgetBuilder builder, {double width = 340, bool alignLeft = false}) async {
    if (_popupContext != null) Navigator.pop(_popupContext!);
    final result = await showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: RetroStrings.close,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (context, _, _) {
        _popupContext = context;
        final screen = MediaQuery.sizeOf(context);
        final t = tokens(context);
        final left = (alignLeft ? anchor.left : anchor.right - width).clamp(8.0, screen.width - width - 8);
        return _PopupFocus(
          child: Stack(
          children: [
            Positioned(
              left: left,
              top: anchor.bottom + 4,
              width: width,
              child: _Cutout(
                radius: t.radiusMd,
                child: _NeonPanel(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: screen.height - anchor.bottom - 24),
                    child: SingleChildScrollView(child: builder(context)),
                  ),
                ),
              ),
            ),
          ],
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
    );
    _popupContext = null;
    return result;
  }

  Widget _popupHeader(IconData icon, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Row(
      children: [
        BrowserIcon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      ],
    ),
  );

  Widget _popupLink(BuildContext context, String label, String page) => Align(
    alignment: Alignment.centerRight,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: TextButton(
        onPressed: () {
          Navigator.pop(context);
          unawaited(_controller.openInternal(page));
        },
        child: Text(label),
      ),
    ),
  );

  Future<void> _showShield(Rect anchor) async {
    final adblock = AdblockManager.instance;
    await _popup<void>(
      anchor,
      (context) => ListenableBuilder(
        listenable: Listenable.merge([adblock, _controller]),
        builder: (context, _) {
          final t = tokens(context);
          final tab = _controller.active;
          final site = _siteOf(tab);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _popupHeader(Symbols.shield_rounded, RetroStrings.adblock),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  adblock.enabled ? RetroStrings.adblockCount(tab?.blockedCount ?? 0) : RetroStrings.adblockOffEverywhere,
                  style: TextStyle(color: t.textMuted),
                ),
              ),
              if (adblock.enabled && site.isNotEmpty && !(tab?.isInternal ?? false))
                SwitchListTile(
                  dense: true,
                  title: Text(RetroStrings.adblockOnSite(site)),
                  value: !adblock.isOffFor(site),
                  onChanged: (v) async {
                    await adblock.setOffForSite(site, !v);
                    await _controller.reload();
                  },
                ),
              _popupLink(context, RetroStrings.filterLists, BrowserController.filtersPage),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showDark(Rect anchor) async {
    await _popup<void>(
      anchor,
      (context) => ListenableBuilder(
        listenable: Listenable.merge([_settings, _controller]),
        builder: (context, _) {
          final site = _siteOf(_controller.active);
          final internal = _controller.active?.isInternal ?? false;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _popupHeader(Symbols.dark_mode_rounded, 'Dark Reader'),
              SwitchListTile(
                dense: true,
                title: Text(RetroStrings.darkMode),
                value: _settings.darkMode,
                onChanged: (v) => unawaited(_controller.setDarkMode(enabled: v)),
              ),
              if (_settings.darkMode && site.isNotEmpty && !internal)
                SwitchListTile(
                  dense: true,
                  title: Text(RetroStrings.darkOnSite(site)),
                  value: !_settings.isDarkExcluded(site),
                  onChanged: (v) => unawaited(_controller.setDarkExcluded(site, !v)),
                ),
              if (_settings.darkMode) ...[
                BrowserSliderTile(
                  label: RetroStrings.darkBrightness,
                  value: _settings.darkBrightness,
                  onChanged: (v) => unawaited(_controller.setDarkMode(brightness: v)),
                ),
                BrowserSliderTile(
                  label: RetroStrings.darkContrast,
                  value: _settings.darkContrast,
                  onChanged: (v) => unawaited(_controller.setDarkMode(contrast: v)),
                ),
              ],
              _popupLink(context, RetroStrings.browserSettings, BrowserController.settingsPage),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDownloadsButton(MonoTokens t) {
    final active = _controller.downloads.where((d) => d.active).toList();
    final total = active.fold<int>(0, (sum, d) => sum + d.total);
    final received = active.fold<int>(0, (sum, d) => sum + d.received);
    return Stack(
      alignment: Alignment.center,
      children: [
        Builder(
          builder: (anchor) => _iconButton(Symbols.download_rounded, RetroStrings.downloads, () {
            final rect = _rectOf(anchor);
            if (rect != null) unawaited(_showDownloads(rect));
          }),
        ),
        if (active.isNotEmpty)
          IgnorePointer(
            child: SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: total > 0 ? (received / total).clamp(0.0, 1.0) : null,
                color: t.accent,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showDownloads(Rect anchor) async {
    await _popup<void>(
      anchor,
      width: 460,
      (context) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final t = tokens(context);
          final items = _controller.downloads;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _popupHeader(Symbols.download_rounded, RetroStrings.downloads),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(RetroStrings.noDownloads, style: TextStyle(color: t.textMuted)),
                )
              else
                for (final d in items) _DownloadRow(download: d),
              if (items.any((d) => !d.active))
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: TextButton(onPressed: _controller.clearFinishedDownloads, child: Text(RetroStrings.clearList)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    // A minimized player above the browser sits in its own bar below the
    // pages, so the browser stays shown (and usable) beside it.
    final route = ModalRoute.of(context);
    final current = route == null || MinimizableRoute.isCurrentOrUnderMinimized(route);
    if (current != _routeCurrent) {
      _routeCurrent = current;
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncVisibility());
    }
    final tab = _controller.active;
    final fullscreen = tab?.fullscreen ?? false;
    final t = tokens(context);
    final chrome = BoxDecoration(color: Theme.of(context).pageColor);
    // A clear mark on the focused button, for the TV remote and the keyboard.
    final focusRing = ButtonStyle(
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused) ? BorderSide(color: t.accent, width: 2.5) : null,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused) ? t.accent.withValues(alpha: 0.3) : null,
      ),
    );
    final theme = Theme.of(context);
    final browserTheme = theme.copyWith(
      iconButtonTheme: IconButtonThemeData(style: focusRing.merge(theme.iconButtonTheme.style)),
      textButtonTheme: TextButtonThemeData(style: focusRing.merge(theme.textButtonTheme.style)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: focusRing.merge(theme.outlinedButtonTheme.style)),
      filledButtonTheme: FilledButtonThemeData(style: focusRing.merge(theme.filledButtonTheme.style)),
    );

    // Android's Back key: leaves a page's video fullscreen, then goes back in
    // the tab, and only then closes the browser.
    return PopScope(
      canPop: !Platform.isAndroid,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final popup = _popupContext;
        if (popup != null && popup.mounted) {
          Navigator.pop(popup);
          return;
        }
        if (await _controller.exitPageFullscreen()) return;
        if (_controller.active?.canGoBack ?? false) {
          await _controller.back();
          return;
        }
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Theme(
      data: browserTheme,
      child: Scaffold(
      // Transparent: the native page shows through the page area.
      backgroundColor: Colors.transparent,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyT, control: true): _newTab,
          const SingleActivator(LogicalKeyboardKey.keyT, control: true, shift: true): () =>
              unawaited(_controller.reopenClosed()),
          const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true): () => _newTab(private: true),
          const SingleActivator(LogicalKeyboardKey.keyW, control: true): _closeActive,
          const SingleActivator(LogicalKeyboardKey.keyL, control: true): _addressFocus.requestFocus,
          const SingleActivator(LogicalKeyboardKey.tab, control: true): () => unawaited(_controller.selectRelative(1)),
          const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): () =>
              unawaited(_controller.selectRelative(-1)),
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => unawaited(_controller.back()),
          const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => unawaited(_controller.forward()),
          const SingleActivator(LogicalKeyboardKey.f5): () => unawaited(_controller.reload()),
        },
        child: Focus(
          focusNode: _keys,
          autofocus: true,
          // Remote or keyboard arrows while nothing in the browser has the
          // focus (e.g. after the page let go of it): start at the toolbar.
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent || !_keys.hasPrimaryFocus) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key != LogicalKeyboardKey.arrowUp &&
                key != LogicalKeyboardKey.arrowDown &&
                key != LogicalKeyboardKey.arrowLeft &&
                key != LogicalKeyboardKey.arrowRight) {
              return KeyEventResult.ignored;
            }
            final first = _toolbarFocus.traversalDescendants.where((n) => n.canRequestFocus).firstOrNull;
            if (first == null) return KeyEventResult.ignored;
            first.requestFocus();
            return KeyEventResult.handled;
          },
          child: Column(
            children: [
              if (!fullscreen)
                DecoratedBox(
                  decoration: chrome,
                  child: Column(
                    children: [
                      _buildTabStrip(context, t),
                      _buildToolbar(context, t, tab),
                      SizedBox(
                        height: 2,
                        child: (tab?.loading ?? false)
                            ? LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent, color: t.accent)
                            : null,
                      ),
                      if (_notice case final notice?) _buildNotice(context, t, notice),
                    ],
                  ),
                ),
              Expanded(child: _buildPage(context, tab)),
            ],
          ),
        ),
      ),
      ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, BrowserTabState? tab) {
    if (tab == null || tab.url == null) {
      return DecoratedBox(
        decoration: pageDecoration(Theme.of(context)),
        child: _NewTabPage(onOpen: (url) => unawaited(_submit(url)), isPrivate: tab?.isPrivate ?? false),
      );
    }
    if (tab.isInternal) {
      return DecoratedBox(
        decoration: pageDecoration(Theme.of(context)),
        child: switch (tab.url) {
          BrowserController.filtersPage => const AdblockListsScreen(),
          BrowserController.historyPage => const BrowserHistoryPage(),
          _ => const BrowserSettingsScreen(),
        },
      );
    }
    if (tab.blockedPage case final blocked?) {
      final t = tokens(context);
      return DecoratedBox(
        decoration: pageDecoration(Theme.of(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrowserIcon(Symbols.shield_rounded, size: 64),
                  const SizedBox(height: 20),
                  Text(RetroStrings.pageBlockedTitle, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(
                    RetroStrings.pageBlockedText(Uri.tryParse(blocked)?.host ?? blocked),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.textMuted),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    blocked,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton(
                        onPressed: () => unawaited(_controller.leaveBlocked(tab)),
                        child: Text(RetroStrings.goBack),
                      ),
                      OutlinedButton(
                        onPressed: () => unawaited(_controller.proceedBlocked(tab)),
                        child: Text(RetroStrings.proceedOnce),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (tab.crashed) {
      return DecoratedBox(
        decoration: pageDecoration(Theme.of(context)),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(RetroStrings.tabCrashed),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => unawaited(_controller.reload()), child: Text(RetroStrings.reload)),
            ],
          ),
        ),
      );
    }
    // While Flutter content covers the page, the page is hidden.
    // (Android keeps its platform view in place, so it isn't rebuilt.)
    if (_overlays > 0 && !Platform.isAndroid) {
      return DecoratedBox(decoration: pageDecoration(Theme.of(context)), child: const _PageSlot());
    }
    return const _PageSlot();
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback? onPressed, {double size = 20}) {
    return IconButton(
      icon: BrowserIcon(icon, size: size, opacity: onPressed == null ? 0.35 : 1),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildTabStrip(BuildContext context, MonoTokens t) {
    final tabs = _controller.tabs;
    final activeId = _controller.active?.id;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const SizedBox(width: 4),
          Tooltip(
            message: RetroStrings.leaveBrowser,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const BrowserIcon(Symbols.home_rounded, size: 20),
              label: Text(RetroStrings.home, style: TextStyle(color: t.text)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth / tabs.length).clamp(96.0, 220.0);
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: tabs.length + 1,
                  itemBuilder: (context, i) {
                    if (i == tabs.length) {
                      return _iconButton(Symbols.add_rounded, RetroStrings.newTab, _newTab);
                    }
                    final tab = tabs[i];
                    return _TabChip(
                      tab: tab,
                      width: width,
                      active: tab.id == activeId,
                      onTap: () => unawaited(_controller.select(tab.id)),
                      onClose: () => unawaited(_controller.close(tab.id)),
                      onMute: () => unawaited(_controller.setMuted(tab.id, !tab.muted)),
                      onMenu: (position) => unawaited(_tabMenu(tab, position)),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, MonoTokens t, BrowserTabState? tab) {
    final internal = tab?.isInternal ?? false;
    final hasPage = tab?.url != null && !internal;
    final loading = tab?.loading ?? false;
    final bookmarked = _bookmarks.contains(tab?.url);
    final secure = tab?.isSecure ?? true;
    final addressDecoration = InputDecoration(
      isDense: true,
      hintText: RetroStrings.addressHint(_settings.searchLabel),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      filled: true,
      fillColor: t.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: t.accent.withValues(alpha: 0.6)),
      ),
      prefixIcon: internal
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: BrowserIcon(Symbols.settings_rounded, size: 16),
            )
          : hasPage
          ? Tooltip(
              message: secure ? RetroStrings.secureConnection : RetroStrings.insecureConnection,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: secure
                    ? const BrowserIcon(Symbols.lock_rounded, size: 16)
                    : AppIcon(Symbols.lock_open_rounded, size: 16, color: Theme.of(context).colorScheme.error),
              ),
            )
          : const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: BrowserIcon(Symbols.search_rounded, size: 16),
            ),
      prefixIconConstraints: const BoxConstraints(minWidth: 36),
      suffixIcon: hasPage
          ? IconButton(
              icon: BrowserIcon(
                bookmarked ? Symbols.bookmark_rounded : Symbols.bookmark_add_rounded,
                size: 18,
                fill: bookmarked ? 1 : null,
              ),
              tooltip: bookmarked ? RetroStrings.removeBookmark : RetroStrings.addBookmark,
              onPressed: () => unawaited(_toggleBookmark()),
              visualDensity: VisualDensity.compact,
            )
          : null,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
      child: Focus(
        focusNode: _toolbarFocus,
        // Down from the toolbar: into the page (Android TV).
        onKeyEvent: (node, event) {
          if (!Platform.isAndroid || event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.arrowDown) {
            return KeyEventResult.ignored;
          }
          if (_suggestions.isNotEmpty || _browserPageFocus.context == null) return KeyEventResult.ignored;
          _browserPageFocus.requestFocus();
          return KeyEventResult.handled;
        },
        child: Row(
        children: [
          _iconButton(
            Symbols.arrow_back_rounded,
            RetroStrings.goBack,
            (tab?.canGoBack ?? false) ? () => unawaited(_controller.back()) : null,
          ),
          _iconButton(
            Symbols.arrow_forward_rounded,
            RetroStrings.forward,
            (tab?.canGoForward ?? false) ? () => unawaited(_controller.forward()) : null,
          ),
          loading
              ? _iconButton(Symbols.close_rounded, RetroStrings.stopLoading, () => unawaited(_controller.stop()))
              : _iconButton(
                  Symbols.refresh_rounded,
                  RetroStrings.reload,
                  hasPage ? () => unawaited(_controller.reload()) : null,
                ),
          const SizedBox(width: 6),
          Expanded(
            child: CompositedTransformTarget(
              link: _addressLink,
              child: OverlayPortal(
                controller: _suggestPortal,
                overlayChildBuilder: _buildSuggestions,
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _onAddressKey,
                  child: SizedBox(
              height: 36,
              child: PlatformDetector.isTV()
                  // TV: the remote's arrows leave the field, OK opens the keyboard.
                  ? FocusableTextField(
                      controller: _address,
                      focusNode: _addressFocus,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      autocorrect: false,
                      style: const TextStyle(fontSize: 14),
                      decoration: addressDecoration,
                      onSubmitted: (v) => unawaited(_submit(v)),
                      onNavigateUp: () => _addressFocus.focusInDirection(TraversalDirection.up),
                      onNavigateDown: () => _browserPageFocus.context != null
                          ? _browserPageFocus.requestFocus()
                          : _addressFocus.focusInDirection(TraversalDirection.down),
                      onNavigateLeft: () => _addressFocus.focusInDirection(TraversalDirection.left),
                      onNavigateRight: () => _addressFocus.focusInDirection(TraversalDirection.right),
                    )
                  : TextField(
                controller: _address,
                focusNode: _addressFocus,
                onSubmitted: (v) => unawaited(_submit(_highlighted >= 0 && _highlighted < _suggestions.length ? _suggestions[_highlighted].url : v)),
                onTap: _onAddressTap,
                // The menu's own buttons sit in a cutout, so it lies over the
                // live page and takes the clicks.
                contextMenuBuilder: (context, editable) => DesktopTextSelectionToolbar(
                  anchor: editable.contextMenuAnchors.primaryAnchor,
                  children: [
                    _Cutout(
                      // The toolbar's own frame: 8 above and below, rounded.
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      radius: 7,
                      child: IntrinsicWidth(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: AdaptiveTextSelectionToolbar.getAdaptiveButtons(
                            context,
                            editable.contextMenuButtonItems,
                          ).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
                onTapOutside: (_) => _addressFocus.unfocus(),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                autocorrect: false,
                style: const TextStyle(fontSize: 14),
                decoration: addressDecoration,
              ),
            ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 4),
          if (Platform.isAndroid && PlatformDetector.isTV())
            _iconButton(Symbols.phone_android_rounded, RetroStrings.phoneRemote, () => unawaited(_showPhoneRemote())),
          _buildDownloadsButton(t),
          _buildShieldButton(t, tab),
          Builder(
            builder: (anchor) => IconButton(
              icon: BrowserIcon(Symbols.dark_mode_rounded, size: 20, opacity: _settings.darkMode ? 1 : 0.45),
              tooltip: RetroStrings.darkMode,
              onPressed: () {
                final rect = _rectOf(anchor);
                if (rect != null) unawaited(_showDark(rect));
              },
              visualDensity: VisualDensity.compact,
            ),
          ),
          Builder(
            builder: (anchor) => _iconButton(Symbols.bookmarks_rounded, RetroStrings.bookmarks, () {
              final rect = _rectOf(anchor);
              if (rect != null) unawaited(_showBookmarks(rect));
            }),
          ),
          Builder(
            builder: (anchor) => _iconButton(Symbols.more_vert_rounded, RetroStrings.moreActions, () {
              final rect = _rectOf(anchor);
              if (rect != null) unawaited(_moreMenu(rect));
            }),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildNotice(BuildContext context, MonoTokens t, _Notice notice) {
    final error = Theme.of(context).colorScheme.error;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: notice.warning ? error.withValues(alpha: 0.12) : t.surface,
      child: Row(
        children: [
          BrowserIcon(notice.warning ? Symbols.warning_amber_rounded : Symbols.public_rounded, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(notice.text, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (notice.action case final action?)
            TextButton(
              onPressed: () {
                _setNotice(null);
                notice.onAction?.call();
              },
              child: Text(action),
            ),
          if (notice.action2 case final action2?)
            TextButton(
              onPressed: () {
                _setNotice(null);
                notice.onAction2?.call();
              },
              child: Text(action2),
            ),
          _iconButton(Symbols.close_rounded, RetroStrings.close, () => _setNotice(null), size: 16),
        ],
      ),
    );
  }
}

class _Suggestion {
  const _Suggestion({required this.url, required this.title, required this.bookmark});
  final String url;
  final String title;
  final bool bookmark;
}

/// Flutter content lying over the native page (a popup, a menu, the
/// suggestions). Reports its area, so the page gets a hole there and this
/// content takes the clicks while the page stays visible around it.
class _Cutout extends StatefulWidget {
  const _Cutout({required this.child, this.margin = EdgeInsets.zero, this.radius = 0});

  final Widget child;

  /// Extra room around the child, for borders drawn outside it.
  final EdgeInsets margin;

  /// The child's corner radius: the hole is rounded the same way.
  final double radius;

  @override
  State<_Cutout> createState() => _CutoutState();
}

class _CutoutState extends State<_Cutout> {
  static int _next = 0;
  final int _id = _next++;

  void _report() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final rect = widget.margin.inflateRect(box.localToGlobal(Offset.zero) & box.size);
    BrowserController.instance.setCutout(
      _id,
      Rect.fromLTRB(rect.left * dpr, rect.top * dpr, rect.right * dpr, rect.bottom * dpr),
      radius: widget.radius * dpr,
    );
  }

  @override
  void dispose() {
    BrowserController.instance.setCutout(_id, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _report());
        return false;
      },
      child: SizeChangedLayoutNotifier(child: widget.child),
    );
  }
}

/// A popup's frame: a thin neon edge (the retrowave cyan to magenta fade,
/// the theme's accent elsewhere) inside its own bounds, so nothing is drawn
/// over the page around it. Static, so it costs nothing per frame.
class _NeonPanel extends StatelessWidget {
  const _NeonPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final radius = BorderRadius.circular(t.radiusMd);
    final retro = RetroColors.isActive(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: retro
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3FDDF0), Color(0xFFEC4FC4)],
              )
            : null,
        color: retro ? null : t.accent.withValues(alpha: 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Material(
          color: t.surface,
          borderRadius: BorderRadius.circular((t.radiusMd - 1.5).clamp(0, 999)),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

class _MenuEntry {
  const _MenuEntry(this.value, this.icon, this.label, {this.enabled = true});

  static const divider = _MenuEntry(null, Symbols.close_rounded, '');

  final String? value;
  final IconData icon;
  final String label;
  final bool enabled;
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.width,
    required this.active,
    required this.onTap,
    required this.onClose,
    required this.onMute,
    required this.onMenu,
  });

  final BrowserTabState tab;
  final double width;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onMute;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final title = tab.url == null
        ? (tab.isPrivate ? RetroStrings.privateTab : RetroStrings.newTab)
        : tab.url == BrowserController.settingsPage
        ? RetroStrings.browserSettings
        : tab.url == BrowserController.filtersPage
        ? RetroStrings.filterLists
        : tab.url == BrowserController.historyPage
        ? RetroStrings.history
        : (tab.title.isNotEmpty ? tab.title : tab.host);
    final favicon = tab.favicon;
    Widget icon;
    if (tab.loading) {
      icon = SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: t.accent));
    } else if (tab.isInternal) {
      icon = BrowserIcon(
        switch (tab.url) {
          BrowserController.filtersPage => Symbols.shield_rounded,
          BrowserController.historyPage => Symbols.history_rounded,
          _ => Symbols.settings_rounded,
        },
        size: 15,
        opacity: active ? 1 : 0.6,
      );
    } else if (favicon != null) {
      icon = Image.memory(favicon, width: 16, height: 16, gaplessPlayback: true, filterQuality: FilterQuality.medium);
    } else {
      icon = BrowserIcon(Symbols.public_rounded, size: 15, opacity: active ? 1 : 0.6);
    }
    return Listener(
      // Middle click closes, like in other browsers.
      onPointerDown: (e) {
        if (e.buttons == kMiddleMouseButton) onClose();
      },
      child: Tooltip(
        message: tab.suspended ? '${tab.url ?? title}\n${RetroStrings.tabSleeping}' : (tab.url ?? title),
        waitDuration: const Duration(milliseconds: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
          child: Material(
            color: active ? t.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(t.radiusSm),
            shape: tab.isPrivate
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(t.radiusSm),
                    side: BorderSide(color: t.accent.withValues(alpha: 0.55)),
                  )
                : null,
            child: InkWell(
              borderRadius: BorderRadius.circular(t.radiusSm),
              onTap: onTap,
              onSecondaryTapDown: (d) => onMenu(d.globalPosition),
              onLongPress: () {
                final box = context.findRenderObject() as RenderBox?;
                onMenu(box == null ? Offset.zero : box.localToGlobal(box.size.bottomLeft(Offset.zero)));
              },
              child: SizedBox(
                width: width,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    // A sleeping tab (paused in the background) looks faded,
                    // like Edge's sleeping tabs.
                    Opacity(opacity: tab.suspended ? 0.45 : 1, child: icon),
                    if (tab.isPrivate) ...[
                      const SizedBox(width: 4),
                      BrowserIcon(Symbols.visibility_off_rounded, size: 13, opacity: active ? 1 : 0.6),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: (active ? t.text : t.textMuted).withValues(alpha: tab.suspended ? 0.5 : 1),
                        ),
                      ),
                    ),
                    if (tab.audio || tab.muted)
                      IconButton(
                        icon: BrowserIcon(
                          tab.muted ? Symbols.volume_off_rounded : Symbols.volume_up_rounded,
                          size: 14,
                          opacity: active ? 1 : 0.6,
                        ),
                        tooltip: tab.muted ? RetroStrings.unmuteTab : RetroStrings.muteTab,
                        onPressed: onMute,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 28),
                      ),
                    IconButton(
                      icon: BrowserIcon(Symbols.close_rounded, size: 14, opacity: active ? 1 : 0.6),
                      tooltip: RetroStrings.closeTab,
                      onPressed: onClose,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                    const SizedBox(width: 2),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.download});

  final BrowserDownload download;

  static String _size(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final d = download;
    final controller = BrowserController.instance;
    final status = switch (d.state) {
      BrowserDownloadState.completed => '${RetroStrings.downloadDone} · ${_size(d.total > 0 ? d.total : d.received)}',
      BrowserDownloadState.failed => RetroStrings.downloadFailed,
      BrowserDownloadState.paused => '${RetroStrings.downloadPaused} · ${_size(d.received)}',
      BrowserDownloadState.running => d.total > 0 ? '${_size(d.received)} / ${_size(d.total)}' : _size(d.received),
    };
    final done = d.state == BrowserDownloadState.completed;
    return ListTile(
      leading: BrowserIcon(done ? Symbols.check_circle_rounded : Symbols.download_rounded, size: 22),
      title: Text(d.fileName.isEmpty ? d.url : d.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (d.active) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: d.progress, minHeight: 3, color: t.accent),
            const SizedBox(height: 4),
          ],
          Text(status, style: TextStyle(color: t.textMuted, fontSize: 12)),
        ],
      ),
      onTap: done
          ? () => unawaited(Platform.isAndroid ? controller.openDownload(d) : launchUrl(Uri.file(d.path)))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done)
            IconButton(
              icon: const BrowserIcon(Symbols.folder_rounded, size: 18),
              tooltip: Platform.isAndroid ? RetroStrings.openDownloads : RetroStrings.showInFolder,
              onPressed: () => unawaited(
                Platform.isAndroid
                    ? controller.showDownloadsFolder()
                    : Process.run('explorer.exe', ['/select,', d.path]),
              ),
            ),
          if (d.state == BrowserDownloadState.running && controller.canPauseDownloads)
            IconButton(
              icon: const BrowserIcon(Symbols.pause_rounded, size: 18),
              tooltip: RetroStrings.pause,
              onPressed: () => unawaited(controller.pauseDownload(d.id)),
            ),
          if (d.state == BrowserDownloadState.paused)
            IconButton(
              icon: const BrowserIcon(Symbols.play_arrow_rounded, size: 18),
              tooltip: RetroStrings.resume,
              onPressed: () => unawaited(controller.resumeDownload(d.id)),
            ),
          if (d.active)
            IconButton(
              icon: const BrowserIcon(Symbols.close_rounded, size: 18),
              tooltip: RetroStrings.cancel,
              onPressed: () => unawaited(controller.cancelDownload(d.id)),
            ),
        ],
      ),
    );
  }
}

/// The recently visited pages, or an empty page, by the new tab setting.
class _NewTabPage extends StatelessWidget {
  const _NewTabPage({required this.onOpen, required this.isPrivate});

  final ValueChanged<String> onOpen;
  final bool isPrivate;

  Future<void> _menu(BuildContext context, VisitedPage page, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(value: 'open', child: Text(RetroStrings.open)),
        PopupMenuItem(value: 'remove', child: Text(RetroStrings.removeFromList)),
      ],
    );
    if (picked == 'open') onOpen(page.url);
    if (picked == 'remove') await BrowserHistory.instance.remove(page.url);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final settings = BrowserSettings.instance;
    if (isPrivate) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrowserIcon(Symbols.visibility_off_rounded, size: 56),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(RetroStrings.privateTabHint, textAlign: TextAlign.center, style: TextStyle(color: t.textMuted)),
              ),
            ],
          ),
        ),
      );
    }
    if (settings.newTabPage == BrowserNewTabPage.blank) return const SizedBox.expand();
    final pages = BrowserHistory.instance.recent(settings.recentCount);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(32),
          children: [
            const Center(child: BrowserIcon(Symbols.public_rounded, size: 56)),
            const SizedBox(height: 24),
            if (pages.isEmpty)
              Text(RetroStrings.recentEmpty, textAlign: TextAlign.center, style: TextStyle(color: t.textMuted))
            else
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final p in pages)
                    _PageTile(
                      title: p.title.isEmpty ? p.host : p.title,
                      host: p.host,
                      onOpen: () => onOpen(p.url),
                      onMenu: (position) => unawaited(_menu(context, p, position)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({required this.title, required this.host, required this.onOpen, required this.onMenu});

  final String title;
  final String host;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final letter = host.isEmpty ? '?' : host.characters.first.toUpperCase();
    return SizedBox(
      width: 132,
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radiusMd),
          onTap: onOpen,
          onSecondaryTapDown: (d) => onMenu(d.globalPosition),
          onLongPress: () {
            final box = context.findRenderObject() as RenderBox?;
            onMenu(box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero)));
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: t.accent.withValues(alpha: 0.18),
                  child: Text(letter, style: TextStyle(color: t.text, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 10),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: t.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The page's focus on Android (the remote's Down from the toolbar).
final FocusNode _browserPageFocus = FocusNode(debugLabel: 'browser-page');

/// Popups (menus, panels): the remote lands on their first entry, and Back
/// closes the popup rather than the browser.
class _PopupFocus extends StatefulWidget {
  const _PopupFocus({required this.child});

  final Widget child;

  @override
  State<_PopupFocus> createState() => _PopupFocusState();
}

class _PopupFocusState extends State<_PopupFocus> {
  final _node = FocusNode(debugLabel: 'browser-popup');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !PlatformDetector.isTV()) return;
      final first = _node.traversalDescendants.where((n) => n.canRequestFocus).firstOrNull;
      (first ?? _node).requestFocus();
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      onKeyEvent: (node, event) {
        final back = handleBackKeyAction(event, () => Navigator.of(context).maybePop());
        if (back != KeyEventResult.ignored) return back;
        if (event is KeyDownEvent && node.hasPrimaryFocus && event.logicalKey.isDpadDirection) {
          final first = node.traversalDescendants.where((n) => n.canRequestFocus).firstOrNull;
          if (first != null) {
            first.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }
}

/// Reports where the native page goes, in physical pixels.
class _PageSlot extends StatefulWidget {
  const _PageSlot();

  @override
  State<_PageSlot> createState() => _PageSlotState();
}

class _PageSlotState extends State<_PageSlot> {
  List<int>? _sent;

  void _report() {
    if (!mounted) return;
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
      BrowserController.instance.setPageRect(left: rect[0], top: rect[1], right: rect[2], bottom: rect[3]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      // The page is a platform view; focusing it (the remote's Down from the
      // toolbar) hands the keys to the page and its pointer.
      return Focus(
        focusNode: _browserPageFocus,
        onFocusChange: (focused) {
          if (focused) unawaited(BrowserController.instance.focusPage());
        },
        // Flutter sees every key first; keys it leaves unhandled go on to the
        // native page. While the page is focused, the arrows and OK must go
        // there (its pointer), not to Flutter's focus traversal.
        onKeyEvent: (node, event) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter ||
              key == LogicalKeyboardKey.gameButtonA) {
            if (event is KeyDownEvent && event is! KeyRepeatEvent) {
              unawaited(BrowserController.instance.focusPage());
            }
            return KeyEventResult.skipRemainingHandlers;
          }
          return KeyEventResult.ignored;
        },
        child: const AndroidView(
          viewType: BrowserNative.androidViewType,
          creationParamsCodec: StandardMessageCodec(),
        ),
      );
    }
    MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _report());
        return const SizedBox.expand();
      },
    );
  }
}
