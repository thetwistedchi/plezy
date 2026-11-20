import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/retro_strings.dart';
import '../../services/browser/browser_bookmarks.dart';
import '../../services/browser/browser_controller.dart';
import '../../services/browser/browser_history.dart';
import '../../services/browser/browser_settings.dart';
import '../../theme/mono_tokens.dart';
import '../../theme/page_backdrop.dart';
import '../../widgets/app_icon.dart';
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
  final List<StreamSubscription<Object>> _subs = [];
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
    _subs.add(_controller.prompts.listen(_onPrompt));
    _subs.add(_controller.shortcuts.listen(_onShortcut));
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
    unawaited(_controller.setShown(false));
    _address.dispose();
    _addressFocus.dispose();
    _keys.dispose();
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

  /// Flutter content over the page (a menu, the suggestions) hides the page
  /// while it shows: clicks there would otherwise reach the page.
  void _overlayActive(bool active) {
    _overlays += active ? 1 : -1;
    _syncVisibility();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
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
      _suggestPortal.show();
      if (!wasShown) _overlayActive(true);
    } else {
      _suggestPortal.hide();
      if (wasShown) _overlayActive(false);
    }
    if (mounted) setState(() {});
  }

  KeyEventResult _onAddressKey(FocusNode node, KeyEvent event) {
    if (_suggestions.isEmpty || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
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
          child: SizedBox(
            width: box?.width ?? 600,
            child: Material(
              color: t.surface,
              elevation: 8,
              borderRadius: BorderRadius.circular(t.radiusMd),
              clipBehavior: Clip.antiAlias,
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
                            AppIcon.retro(
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
    );
  }

  void _setNotice(_Notice? notice) {
    if (mounted) setState(() => _notice = notice);
  }

  // ---- Prompts ----

  Future<void> _onPrompt(BrowserPrompt prompt) async {
    switch (prompt) {
      case PermissionPrompt(:final request, :final kind, :final url):
        final allow = await _overlay(() => _askPermission(kind, url)) ?? false;
        await _controller.answerPermission(request, allow);
      case DownloadPrompt(:final request, :final url, :final path, :final size):
        final allow = await _overlay(() => _askDownload(url, path, size)) ?? false;
        await _controller.answerDownload(request, allow);
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

  Future<bool?> _askPermission(int kind, String url) {
    final what = switch (kind) {
      1 => RetroStrings.permMicrophone,
      2 => RetroStrings.permCamera,
      3 => RetroStrings.permLocation,
      5 => RetroStrings.permSensors,
      6 => RetroStrings.permClipboard,
      _ => RetroStrings.permOther,
    };
    final host = Uri.tryParse(url)?.host ?? url;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(RetroStrings.permissionAsk(host, what)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(RetroStrings.block)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(RetroStrings.allow)),
        ],
      ),
    );
  }

  Future<bool?> _askDownload(String url, String path, int size) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final risky = _riskyExtensions.contains(ext);
    final host = Uri.tryParse(url)?.host ?? '';
    final t = tokens(context);
    return showDialog<bool>(
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
            const SizedBox(height: 4),
            Text(RetroStrings.downloadsFolder, style: TextStyle(color: t.textMuted)),
            if (risky) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppIcon.retro(Symbols.warning_amber_rounded, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(RetroStrings.downloadRisky)),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(RetroStrings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(RetroStrings.download)),
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

  void _newTab() {
    unawaited(_controller.newTab());
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

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BrowserSettingsScreen()));
  }

  Future<void> _editBookmark(Bookmark bookmark, {bool nested = false}) async {
    final name = TextEditingController(text: bookmark.title);
    Future<String?> ask() => showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(RetroStrings.renameBookmark),
          content: TextField(controller: name, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, '\u0000delete'), child: Text(RetroStrings.delete)),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(RetroStrings.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, name.text), child: Text(RetroStrings.save)),
          ],
        ),
      );
    final result = nested ? await ask() : await _overlay(ask);
    name.dispose();
    if (result == null) return;
    if (result == '\u0000delete') {
      await _bookmarks.remove(bookmark.url);
    } else {
      await _bookmarks.rename(bookmark.url, result);
    }
  }

  Future<void> _showBookmarks() async {
    final url = await _overlay(
      () => showDialog<String>(
        context: context,
        builder: (context) => ListenableBuilder(
          listenable: _bookmarks,
          builder: (context, _) {
            final t = tokens(context);
            final items = _bookmarks.items;
            return AlertDialog(
              title: Text(RetroStrings.bookmarks),
              contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              content: SizedBox(
                width: 520,
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(RetroStrings.noBookmarks, style: TextStyle(color: t.textMuted)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final b = items[i];
                          return ListTile(
                            leading: const AppIcon.retro(Symbols.bookmark_rounded, size: 20),
                            title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(b.host, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => Navigator.pop(context, b.url),
                            trailing: IconButton(
                              icon: const AppIcon.retro(Symbols.edit_rounded, size: 18),
                              tooltip: RetroStrings.renameBookmark,
                              onPressed: () => unawaited(_editBookmark(b, nested: true)),
                            ),
                          );
                        },
                      ),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(RetroStrings.close))],
            );
          },
        ),
      ),
    );
    if (url != null) await _submit(url);
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current != _routeCurrent) {
      _routeCurrent = current;
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncVisibility());
    }
    final tab = _controller.active;
    final fullscreen = tab?.fullscreen ?? false;
    final t = tokens(context);
    final chrome = BoxDecoration(color: Theme.of(context).pageColor);

    return Scaffold(
      // Transparent: the native page shows through the page area.
      backgroundColor: Colors.transparent,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyT, control: true): _newTab,
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
    );
  }

  Widget _buildPage(BuildContext context, BrowserTabState? tab) {
    if (tab == null || tab.url == null) {
      return DecoratedBox(
        decoration: pageDecoration(Theme.of(context)),
        child: _NewTabPage(onOpen: (url) => unawaited(_submit(url))),
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
    if (_overlays > 0) {
      return DecoratedBox(decoration: pageDecoration(Theme.of(context)), child: const _PageSlot());
    }
    return const _PageSlot();
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback? onPressed, {double size = 20}) {
    return IconButton(
      icon: AppIcon.retro(icon, size: size, retroOpacity: onPressed == null ? 0.35 : 1),
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
          _iconButton(Symbols.arrow_back_rounded, RetroStrings.leaveBrowser, () => Navigator.of(context).maybePop()),
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
                    );
                  },
                );
              },
            ),
          ),
          _iconButton(Symbols.settings_rounded, RetroStrings.browserSettings, () => unawaited(_openSettings())),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, MonoTokens t, BrowserTabState? tab) {
    final hasPage = tab?.url != null;
    final loading = tab?.loading ?? false;
    final bookmarked = _bookmarks.contains(tab?.url);
    final secure = tab?.isSecure ?? true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
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
              child: TextField(
                controller: _address,
                focusNode: _addressFocus,
                onSubmitted: (v) => unawaited(_submit(_highlighted >= 0 && _highlighted < _suggestions.length ? _suggestions[_highlighted].url : v)),
                onTap: _onAddressTap,
                contextMenuBuilder: (context, editable) => _OverlayGuard(
                  onChange: _overlayActive,
                  child: AdaptiveTextSelectionToolbar.editableText(editableTextState: editable),
                ),
                onTapOutside: (_) => _addressFocus.unfocus(),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                autocorrect: false,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
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
                  prefixIcon: hasPage
                      ? Tooltip(
                          message: secure ? RetroStrings.secureConnection : RetroStrings.insecureConnection,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: secure
                                ? const AppIcon.retro(Symbols.lock_rounded, size: 16)
                                : AppIcon(Symbols.lock_open_rounded, size: 16, color: Theme.of(context).colorScheme.error),
                          ),
                        )
                      : const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: AppIcon.retro(Symbols.search_rounded, size: 16),
                        ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  suffixIcon: hasPage
                      ? IconButton(
                          icon: AppIcon.retro(
                            bookmarked ? Symbols.bookmark_rounded : Symbols.bookmark_add_rounded,
                            size: 18,
                          ),
                          tooltip: bookmarked ? RetroStrings.removeBookmark : RetroStrings.addBookmark,
                          onPressed: () => unawaited(_toggleBookmark()),
                          visualDensity: VisualDensity.compact,
                        )
                      : null,
                ),
              ),
            ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 4),
          _iconButton(Symbols.bookmarks_rounded, RetroStrings.bookmarks, () => unawaited(_showBookmarks())),
        ],
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
          AppIcon.retro(notice.warning ? Symbols.warning_amber_rounded : Symbols.public_rounded, size: 18),
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

/// Reports while its child (a context menu) is on screen.
class _OverlayGuard extends StatefulWidget {
  const _OverlayGuard({required this.onChange, required this.child});

  final ValueChanged<bool> onChange;
  final Widget child;

  @override
  State<_OverlayGuard> createState() => _OverlayGuardState();
}

class _OverlayGuardState extends State<_OverlayGuard> {
  @override
  void initState() {
    super.initState();
    widget.onChange(true);
  }

  @override
  void dispose() {
    widget.onChange(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.width,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final BrowserTabState tab;
  final double width;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final title = tab.url == null ? RetroStrings.newTab : (tab.title.isNotEmpty ? tab.title : tab.host);
    return Listener(
      // Middle click closes, like in other browsers.
      onPointerDown: (e) {
        if (e.buttons == kMiddleMouseButton) onClose();
      },
      child: Tooltip(
        message: tab.url ?? title,
        waitDuration: const Duration(milliseconds: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
          child: Material(
            color: active ? t.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(t.radiusSm),
            child: InkWell(
              borderRadius: BorderRadius.circular(t.radiusSm),
              onTap: onTap,
              child: SizedBox(
                width: width,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    if (tab.loading)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.6, color: t.accent),
                      )
                    else
                      AppIcon.retro(Symbols.public_rounded, size: 15, retroOpacity: active ? 1 : 0.6),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: active ? t.text : t.textMuted),
                      ),
                    ),
                    if (tab.audio) AppIcon(Symbols.volume_up_rounded, size: 14, color: t.textMuted),
                    IconButton(
                      icon: AppIcon.retro(Symbols.close_rounded, size: 14, retroOpacity: active ? 1 : 0.6),
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

/// The recently visited pages, or an empty page, by the new tab setting.
class _NewTabPage extends StatelessWidget {
  const _NewTabPage({required this.onOpen});

  final ValueChanged<String> onOpen;

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
    if (settings.newTabPage == BrowserNewTabPage.blank) return const SizedBox.expand();
    final pages = BrowserHistory.instance.recent(settings.recentCount);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(32),
          children: [
            const Center(child: AppIcon.retro(Symbols.public_rounded, size: 56)),
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
    MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _report());
        return const SizedBox.expand();
      },
    );
  }
}
