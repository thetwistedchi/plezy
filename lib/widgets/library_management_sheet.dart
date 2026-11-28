import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../focus/dpad_reorder_mixin.dart';
import '../focus/focus_theme.dart';
import '../focus/input_mode_tracker.dart';
import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/media_backend.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../profiles/active_profile_provider.dart';
import '../utils/app_logger.dart';
import '../utils/content_utils.dart';
import '../utils/language_codes.dart';
import '../utils/dialogs.dart';
import '../utils/platform_detector.dart';
import '../utils/provider_extensions.dart';
import '../utils/snackbar_helper.dart';
import 'app_icon.dart';
import 'app_menu.dart';
import 'bottom_sheet_page_scaffold.dart';
import 'media_context_menu.dart' show isAdminActionAllowedForMediaItem;
import 'overlay_sheet.dart';
import '../services/retrowave/library_language_rules.dart';
import '../i18n/retro_strings.dart';
import '../services/retrowave/virtual_libraries.dart';
import '../services/retrowave/top_bar_pin.dart';
import '../services/settings_service.dart';
import '../services/retrowave/audio/audio_settings.dart';

class ContextMenuItem {
  final String value;
  final IconData icon;
  final String label;
  final bool requiresConfirmation;
  final String? confirmationTitle;
  final String? confirmationMessage;
  final bool isDestructive;

  const ContextMenuItem({
    required this.value,
    required this.icon,
    required this.label,
    this.requiresConfirmation = false,
    this.confirmationTitle,
    this.confirmationMessage,
    this.isDestructive = false,
  });
}

/// Shows the manage/reorder-libraries sheet (dialog on TV, overlay sheet
/// otherwise). Reorder and hide/unhide are provider-backed, so any screen can
/// open it.
///
/// [onOrderChanged] runs after the new order is written to
/// [LibrariesProvider] (the libraries screen uses it to poke MainScreen's
/// side nav). [onToggleVisibility] overrides the default plain hide/unhide
/// (the libraries screen adds "re-select first visible library" logic).
///
/// A library's admin actions (scan, refresh metadata, ...) are offered only
/// to an owner or administrator of its server; [canAdministerLibrary]
/// replaces that check in tests.
Future<void> showLibraryManagementSheet(
  BuildContext context, {
  VoidCallback? onOrderChanged,
  Future<void> Function(MediaLibrary library)? onToggleVisibility,
  @visibleForTesting bool Function(MediaLibrary library)? canAdministerLibrary,
}) {
  final librariesProvider = context.read<LibrariesProvider>();
  final hiddenLibrariesProvider = context.read<HiddenLibrariesProvider>();
  final serverManager = Provider.of<MultiServerProvider?>(context, listen: false)?.serverManager;
  final activeProfile = Provider.of<ActiveProfileProvider?>(context, listen: false)?.active;

  // Same gate as the media context menu's admin entries: the server's owner or
  // administrator flag, narrowed by a non-admin Plex Home profile.
  bool defaultCanAdministerLibrary(MediaLibrary library) {
    final serverId = serverIdOrNull(library.serverId);
    return serverId != null &&
        isAdminActionAllowedForMediaItem(
          isOwnerOrAdmin: serverManager?.isOwnerOrAdmin(serverId) ?? false,
          itemBackend: library.backend,
          activeProfile: activeProfile,
        );
  }

  final canAdminister = canAdministerLibrary ?? defaultCanAdministerLibrary;

  Future<void> defaultToggleVisibility(MediaLibrary library) async {
    final isHidden = hiddenLibrariesProvider.hiddenLibraryKeys.contains(library.globalKey);
    if (isHidden) {
      await hiddenLibrariesProvider.unhideLibrary(library.globalKey);
    } else {
      await hiddenLibrariesProvider.hideLibrary(library.globalKey);
    }
  }

  Widget buildSheet({required bool isDialog}) => _LibraryManagementSheet(
    isDialog: isDialog,
    librariesProvider: librariesProvider,
    hiddenLibraryKeys: hiddenLibrariesProvider.hiddenLibraryKeys,
    onReorder: (reorderedLibraries) async {
      // Fork: the app pages keep their places; the server libraries are
      // saved as before.
      final real = await VirtualLibraries.saveOrder(reorderedLibraries);
      await librariesProvider.updateLibraryOrder(reconcileLibraryOrder(real, librariesProvider.libraries));
      onOrderChanged?.call();
    },
    onToggleVisibility: onToggleVisibility ?? defaultToggleVisibility,
    // Fork: the language rule is the viewer's own, so every library has it;
    // the server actions stay with admins.
    getLibraryMenuItems: (library) => VirtualLibraries.isVirtual(library)
        ? const []
        : canAdminister(library)
        ? _getLibraryMenuItems(library)
        : [_languagesMenuItem(), _topBarMenuItem(), ?_audioModeMenuItem(library)],
    onLibraryMenuAction: (action, library) => _handleLibraryMenuAction(context, action, library),
  );

  if (PlatformDetector.isTV()) {
    return showScopedDialog<void>(context: context, builder: (context) => buildSheet(isDialog: true));
  }
  // Use the host supplied by the calling screen when available while keeping
  // this reusable entry point safe for routes without one. isScrollControlled
  // keeps that modal fallback from capping the sheet at ~9/16 of the screen.
  return OverlaySheetController.showAdaptive<void>(
    context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => buildSheet(isDialog: false),
  );
}

/// [sheetOrder] as the sheet shows it, applied to the provider's [current]
/// libraries: rows keep the sheet's order, libraries loaded since the sheet
/// last synced follow in their current order, and libraries that have gone
/// are dropped. A reorder therefore never saves a stale snapshot, which would
/// drop newly loaded libraries or bring back removed ones.
@visibleForTesting
List<MediaLibrary> reconcileLibraryOrder(List<MediaLibrary> sheetOrder, List<MediaLibrary> current) {
  final remaining = {for (final library in current) library.globalKey: library};
  return [for (final library in sheetOrder) ?remaining.remove(library.globalKey), ...remaining.values];
}

/// Fork: audio and subtitle languages for this library.
ContextMenuItem _languagesMenuItem() =>
    ContextMenuItem(value: 'languages', icon: Symbols.translate_rounded, label: RetroStrings.libraryLanguages);

/// Fork: whether this library's top bar stays while scrolling.
ContextMenuItem _topBarMenuItem() =>
    ContextMenuItem(value: 'top_bar', icon: Symbols.vertical_align_top_rounded, label: RetroStrings.topBarMenu);

/// Fork: music libraries can hold audiobooks, audio dramas or podcasts. The
/// type is the viewer's own setting, so every user gets it.
ContextMenuItem? _audioModeMenuItem(MediaLibrary library) => library.kind == MediaKind.artist
    ? ContextMenuItem(value: 'audio_mode', icon: Symbols.headphones_rounded, label: RetroStrings.audioLibraryType)
    : null;

List<ContextMenuItem> _getLibraryMenuItems(MediaLibrary library) {
  // Scan and refresh metadata are the admin actions every backend supports —
  // Plex hits `/library/sections/{id}/refresh` (with `force=1` to refresh);
  // MediaBrowser servers post to `/Items/{id}/Refresh` (the library view is
  // itself an item) with `Default` or `FullRefresh` modes.
  final scan = ContextMenuItem(
    value: 'scan',
    icon: Symbols.refresh_rounded,
    label: t.libraries.scanLibraryFiles,
    requiresConfirmation: true,
    confirmationTitle: t.libraries.scanLibrary,
    confirmationMessage: t.libraries.scanLibraryConfirm(title: library.title),
  );
  final refresh = ContextMenuItem(
    value: 'refresh',
    icon: Symbols.sync_rounded,
    label: t.libraries.refreshMetadata,
    requiresConfirmation: true,
    confirmationTitle: t.libraries.refreshMetadata,
    confirmationMessage: t.libraries.refreshMetadataConfirm(title: library.title),
    isDestructive: true,
  );
  // Analyze / empty trash hit Plex-only endpoints, so backend capability
  // gating keeps them out of MediaBrowser menus. The library-qualified
  // resolver independently requires the exact owning Plex server.
  final languages = _languagesMenuItem();
  final topBar = _topBarMenuItem();
  final audioMode = _audioModeMenuItem(library);
  if (library.backend != MediaBackend.plex) return [languages, topBar, ?audioMode, scan, refresh];
  return [
    languages,
    topBar,
    ?audioMode,
    scan,
    ContextMenuItem(
      value: 'analyze',
      icon: Symbols.analytics_rounded,
      label: t.libraries.analyze,
      requiresConfirmation: true,
      confirmationTitle: t.libraries.analyzeLibrary,
      confirmationMessage: t.libraries.analyzeLibraryConfirm(title: library.title),
    ),
    refresh,
    ContextMenuItem(
      value: 'empty_trash',
      icon: Symbols.delete_outline_rounded,
      label: t.libraries.emptyTrash,
      requiresConfirmation: true,
      confirmationTitle: t.libraries.emptyTrash,
      confirmationMessage: t.libraries.emptyTrashConfirm(title: library.title),
      isDestructive: true,
    ),
  ];
}

Future<void> _handleLibraryMenuAction(BuildContext context, String action, MediaLibrary library) async {
  // Find the menu item for confirmation details
  final menuItems = _getLibraryMenuItems(library);
  final item = menuItems.where((i) => i.value == action).firstOrNull;
  if (item == null) return;

  if (item.requiresConfirmation) {
    final confirmed = await showConfirmDialog(
      context,
      title: item.confirmationTitle ?? t.dialog.confirmAction,
      message: item.confirmationMessage ?? t.libraries.confirmActionMessage,
      confirmText: t.common.confirm,
      isDestructive: item.isDestructive,
    );
    if (!confirmed || !context.mounted) return;
  }

  switch (action) {
    case 'languages':
      unawaited(_editLibraryLanguages(context, library));
      break;
    case 'audio_mode':
      unawaited(_editAudioMode(context, library));
      break;
    case 'top_bar':
      unawaited(_editTopBar(context, library));
      break;
    case 'scan':
      unawaited(_scanLibrary(context, library));
      break;
    case 'analyze':
      unawaited(_analyzeLibrary(context, library));
      break;
    case 'refresh':
      unawaited(_refreshLibraryMetadata(context, library));
      break;
    case 'empty_trash':
      unawaited(_emptyLibraryTrash(context, library));
      break;
  }
}

/// Runs a library admin action, wrapping it in progress/success/failure
/// snackbars.
///
/// [resolveClient] picks the client flavour: `getPlexClientForLibrary` for the
/// Plex-only endpoints (analyze / empty trash), `getMediaClientForLibrary`
/// for ops on the backend-neutral [MediaServerClient] interface (scan and
/// refresh metadata). Both resolvers require the library's exact owning
/// server and throw the same error when it isn't available.
Future<void> _performLibraryAction<T extends MediaServerClient>(
  BuildContext context, {
  required T Function(BuildContext context) resolveClient,
  required Future<void> Function(T client) action,
  required String progressMessage,
  required String successMessage,
  required String Function(Object error) failureMessage,
}) async {
  try {
    final client = resolveClient(context);

    if (context.mounted) {
      showAppSnackBar(context, progressMessage, duration: const Duration(seconds: 2));
    }

    await action(client);

    if (context.mounted) {
      showSuccessSnackBar(context, successMessage);
    }
  } catch (e) {
    appLogger.e('Library action failed', error: e);
    if (context.mounted) {
      showErrorSnackBar(context, failureMessage(e));
    }
  }
}

Future<void> _scanLibrary(BuildContext context, MediaLibrary library) {
  return _performLibraryAction(
    context,
    resolveClient: (ctx) => ctx.getMediaClientForLibrary(library),
    action: (client) => client.scanLibrary(library.id),
    progressMessage: t.messages.libraryScanning(title: library.title),
    successMessage: t.messages.libraryScanStarted(title: library.title),
    failureMessage: (error) => t.messages.libraryScanFailed(error: error.toString()),
  );
}

Future<void> _refreshLibraryMetadata(BuildContext context, MediaLibrary library) {
  return _performLibraryAction(
    context,
    resolveClient: (ctx) => ctx.getMediaClientForLibrary(library),
    action: (client) => client.refreshLibraryMetadata(library.id),
    progressMessage: t.messages.metadataRefreshing(title: library.title),
    successMessage: t.messages.metadataRefreshStarted(title: library.title),
    failureMessage: (error) => t.messages.metadataRefreshFailed(error: error.toString()),
  );
}

Future<void> _emptyLibraryTrash(BuildContext context, MediaLibrary library) {
  return _performLibraryAction(
    context,
    resolveClient: (ctx) => ctx.getPlexClientForLibrary(library),
    action: (client) => client.emptyLibraryTrash(library.id),
    progressMessage: t.libraries.emptyingTrash(title: library.title),
    successMessage: t.libraries.trashEmptied(title: library.title),
    failureMessage: (error) => t.libraries.failedToEmptyTrash(error: error),
  );
}

Future<void> _analyzeLibrary(BuildContext context, MediaLibrary library) {
  return _performLibraryAction(
    context,
    resolveClient: (ctx) => ctx.getPlexClientForLibrary(library),
    action: (client) => client.analyzeLibrary(library.id),
    progressMessage: t.libraries.analyzing(title: library.title),
    successMessage: t.libraries.analysisStarted(title: library.title),
    failureMessage: (error) => t.libraries.failedToAnalyze(error: error),
  );
}

class _LibraryManagementSheet extends StatefulWidget {
  final bool isDialog;
  final LibrariesProvider librariesProvider;
  final Set<String> hiddenLibraryKeys;
  final Function(List<MediaLibrary>) onReorder;
  final Function(MediaLibrary) onToggleVisibility;
  final List<ContextMenuItem> Function(MediaLibrary) getLibraryMenuItems;
  final void Function(String action, MediaLibrary library) onLibraryMenuAction;

  const _LibraryManagementSheet({
    this.isDialog = false,
    required this.librariesProvider,
    required this.hiddenLibraryKeys,
    required this.onReorder,
    required this.onToggleVisibility,
    required this.getLibraryMenuItems,
    required this.onLibraryMenuAction,
  });

  @override
  State<_LibraryManagementSheet> createState() => _LibraryManagementSheetState();
}

class _LibraryManagementSheetState extends State<_LibraryManagementSheet>
    with DpadReorderListMixin<MediaLibrary, _LibraryManagementSheet> {
  late List<MediaLibrary> _tempLibraries;

  final FocusNode _listFocusNode = FocusNode();
  final ScrollController _dialogScrollController = ScrollController();
  final ScrollController _sheetScrollController = ScrollController();

  @override
  List<MediaLibrary> get reorderItems => _tempLibraries;

  @override
  set reorderItems(List<MediaLibrary> value) => _tempLibraries = value;

  /// Column 2 (the options button) exists only on rows with admin actions.
  @override
  int get lastReorderColumn =>
      focusedIndex < _tempLibraries.length &&
          (_hasLibraryMenu(_tempLibraries[focusedIndex]) || _hasHomeSwitch(_tempLibraries[focusedIndex]))
      ? 2
      : 1;

  bool _hasLibraryMenu(MediaLibrary library) => widget.getLibraryMenuItems(library).isNotEmpty;

  /// Fork: "Languages: audio Japanese · subtitles German" when the library
  /// has a language rule.
  /// Fork: the type of a music library that is not plain music.
  String? _audioModeLabel(MediaLibrary library) {
    if (library.kind != MediaKind.artist) return null;
    final mode = AudioSettings.modeForLibrary(library.serverId, library.id);
    return mode == AudioMode.music ? null : RetroStrings.audioMode(mode);
  }

  String? _languageRule(MediaLibrary library) {
    if (VirtualLibraries.isVirtual(library)) return null;
    final rule = LibraryLanguageRules.forLibrary(library.globalKey);
    if (rule == null) return null;
    String name(String? code) =>
        code == null ? RetroStrings.languageDefault : LanguageCodes.getLanguageName(code) ?? code;
    return RetroStrings.libraryLanguagesActive(name(rule.audio), name(rule.subtitle));
  }

  /// Fork: Upcoming episodes carries its "Show on Home" switch in the row.
  bool _hasHomeSwitch(MediaLibrary library) => library.id == VirtualLibraries.upcomingId;

  void _toggleHome() {
    final svc = SettingsService.instance;
    unawaited(svc.write(SettingsService.upcomingOnHome, !svc.read(SettingsService.upcomingOnHome)));
    setState(() {});
  }

  /// Both layouts scroll the focused row into view: the TV dialog is the D-pad
  /// surface, and the sheet still shows the same cursor to a keyboard user.
  @override
  ScrollController? get reorderScrollController => widget.isDialog ? _dialogScrollController : _sheetScrollController;

  @override
  void onReorderMoveConfirmed() => widget.onReorder(_tempLibraries);

  @override
  void onReorderColumnActivated(int column, int index) {
    final library = _tempLibraries[index];
    if (column == 1) {
      widget.onToggleVisibility(library);
    } else if (column == 2 && _hasHomeSwitch(library)) {
      _toggleHome();
    } else if (column == 2 && _hasLibraryMenu(library)) {
      _showLibraryMenuBottomSheet(context, library);
    }
  }

  @override
  void initState() {
    super.initState();
    _tempLibraries = VirtualLibraries.merge(widget.librariesProvider.libraries);
    widget.librariesProvider.addListener(_onLibrariesChanged);
    LibraryLanguageRules.revision.addListener(_onRulesChanged);
  }

  void _onRulesChanged() {
    if (mounted) setState(() {});
  }

  /// Follows library loads and changes made while the sheet is open, keeping
  /// the order shown. A move in progress keeps its rows; its confirm is
  /// reconciled against the provider when it is saved.
  void _onLibrariesChanged() {
    if (!mounted || movingIndex != null) return;
    setState(() {
      _tempLibraries = reconcileLibraryOrder(_tempLibraries, VirtualLibraries.merge(widget.librariesProvider.libraries));
      if (focusedIndex >= _tempLibraries.length) {
        focusedIndex = _tempLibraries.isEmpty ? 0 : _tempLibraries.length - 1;
        focusedColumn = 0;
      }
    });
  }

  @override
  void dispose() {
    widget.librariesProvider.removeListener(_onLibrariesChanged);
    LibraryLanguageRules.revision.removeListener(_onRulesChanged);
    _listFocusNode.dispose();
    _dialogScrollController.dispose();
    _sheetScrollController.dispose();
    super.dispose();
  }

  void _reorderLibraries(int oldIndex, int newIndex) {
    setState(() {
      final library = _tempLibraries.removeAt(oldIndex);
      _tempLibraries.insert(newIndex, library);
    });
    // Apply immediately
    widget.onReorder(_tempLibraries);
  }

  void _showLibraryMenuBottomSheet(BuildContext outerContext, MediaLibrary library) {
    final menuItems = widget.getLibraryMenuItems(library);
    OverlaySheetController.pushAdaptive<String>(
      outerContext,
      builder: (context) => AppMenuSheet<String>(
        title: library.title,
        entries: [
          for (final item in menuItems)
            AppMenuItem<String>(value: item.value, icon: item.icon, label: item.label, destructive: item.isDestructive),
        ],
        onSelected: (value) => widget.onLibraryMenuAction(value, library),
      ),
    );
  }

  /// Whether the libraries span more than one connected server.
  bool _hasMultipleServers() {
    final serverIds = _tempLibraries.where((lib) => lib.serverId != null).map((lib) => lib.serverId).toSet();
    return serverIds.length > 1;
  }

  @override
  Widget build(BuildContext context) {
    // Watch provider to rebuild when hidden libraries change
    final hiddenLibrariesProvider = context.watch<HiddenLibrariesProvider>();
    final hiddenLibraryKeys = hiddenLibrariesProvider.hiddenLibraryKeys;

    if (widget.isDialog) {
      return Dialog(
        child: PopScope(
          canPop: false, // Prevent system back from double-popping; handled by handleReorderKeyEvent
          // ignore: no-empty-block - required callback, blocks system back on Android TV
          onPopInvokedWithResult: (didPop, result) {},
          child: Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  const AppIcon(Symbols.edit_rounded, fill: 1),
                  const SizedBox(width: 12),
                  Text(t.libraries.manageLibraries),
                ],
              ),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const AppIcon(Symbols.close_rounded, fill: 1),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            body: Focus(
              focusNode: _listFocusNode,
              descendantsAreFocusable: false,
              autofocus: InputModeTracker.isKeyboardMode(context),
              onKeyEvent: handleReorderKeyEvent,
              child: _buildFlatLibraryList(_dialogScrollController, hiddenLibraryKeys, shrinkWrap: false),
            ),
          ),
        ),
      );
    }

    return BottomSheetPageScaffold(
      title: t.libraries.manageLibraries,
      icon: Symbols.edit_rounded,
      child: Focus(
        focusNode: _listFocusNode,
        descendantsAreFocusable: false,
        autofocus: InputModeTracker.isKeyboardMode(context),
        onKeyEvent: handleReorderKeyEvent,
        child: _buildFlatLibraryList(_sheetScrollController, hiddenLibraryKeys, shrinkWrap: true),
      ),
    );
  }

  /// Build flat library list with a server subtitle when multiple servers are
  /// connected. Each layout passes its own controller, which is also what
  /// [reorderScrollController] scrolls when the keyboard cursor moves.
  Widget _buildFlatLibraryList(
    ScrollController scrollController,
    Set<String> hiddenLibraryKeys, {
    required bool shrinkWrap,
  }) {
    final showServerNames = _hasMultipleServers();
    final isKeyboardMode = InputModeTracker.isKeyboardMode(context);

    return ReorderableListView.builder(
      scrollController: scrollController,
      shrinkWrap: shrinkWrap,
      onReorderItem: _reorderLibraries,
      itemCount: _tempLibraries.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        final library = _tempLibraries[index];
        final showServerName = showServerNames && library.serverName != null;
        final isFocused = isKeyboardMode && index == focusedIndex;
        final isMoving = index == movingIndex;
        return _buildLibraryTile(
          library,
          index,
          hiddenLibraryKeys,
          showServerName: showServerName,
          isFocused: isFocused,
          isMoving: isMoving,
          focusedColumn: isFocused ? focusedColumn : null,
        );
      },
    );
  }

  /// Build a single library tile
  Widget _buildLibraryTile(
    MediaLibrary library,
    int index,
    Set<String> hiddenLibraryKeys, {
    bool showServerName = false,
    bool isFocused = false,
    bool isMoving = false,
    int? focusedColumn,
  }) {
    final isHidden = hiddenLibraryKeys.contains(library.globalKey);
    final colorScheme = Theme.of(context).colorScheme;

    // The focused row is tinted and outlined in the accent colour (stronger
    // while the row itself, not one of its buttons, has focus), so it stays
    // visible on dark and OLED themes.
    Color? tileColor;
    ShapeBorder? tileShape;
    if (isMoving) {
      tileColor = colorScheme.primaryContainer;
      tileShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.primary, width: 2),
      );
    } else if (isFocused) {
      final rowFocused = focusedColumn == 0;
      tileColor = colorScheme.primary.withValues(alpha: rowFocused ? 0.22 : 0.10);
      tileShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: rowFocused ? 1 : 0.5), width: rowFocused ? 2 : 1),
      );
    }

    final isVisibilityButtonFocused = isFocused && focusedColumn == 1;
    final isOptionsButtonFocused = isFocused && focusedColumn == 2;

    return Opacity(
      key: ValueKey(library.globalKey),
      opacity: isHidden ? 0.5 : 1.0,
      child: ListTile(
        tileColor: tileColor,
        shape: tileShape,
        leading: Row(
          mainAxisSize: .min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: AppIcon(
                isMoving ? Symbols.swap_vert_rounded : Symbols.drag_indicator_rounded,
                fill: 1,
                color: isMoving ? colorScheme.primary : IconTheme.of(context).color?.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 8),
            AppIcon(
              VirtualLibraries.isVirtual(library)
                  ? VirtualLibraries.iconFor(library)
                  : ContentTypeHelper.getLibraryIcon(library.kind.id),
              fill: 1,
            ),
          ],
        ),
        title: Row(
          children: [
            Flexible(child: Text(library.title, overflow: TextOverflow.ellipsis)),
            // Fork: a language rule is set for this library.
            if (_languageRule(library) != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: _languageRule(library)!,
                child: AppIcon.retro(Symbols.translate_rounded, size: 18, color: colorScheme.primary),
              ),
            ],
          ],
        ),
        subtitle: showServerName || _languageRule(library) != null || _audioModeLabel(library) != null
            ? Text(
                [
                  if (showServerName) library.serverName!,
                  ?_audioModeLabel(library),
                  ?_languageRule(library),
                ].join(' · '),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: .min,
          children: [
            Container(
              decoration: FocusTheme.focusBackgroundDecoration(
                context,
                isFocused: isVisibilityButtonFocused,
                borderRadius: 20,
              ),
              child: IconButton(
                icon: AppIcon(isHidden ? Symbols.visibility_off_rounded : Symbols.visibility_rounded, fill: 1),
                tooltip: isHidden ? t.libraries.showLibrary : t.libraries.hideLibrary,
                onPressed: () => widget.onToggleVisibility(library),
              ),
            ),
            if (_hasHomeSwitch(library))
              Tooltip(
                message: RetroStrings.upcomingOnHome,
                child: Container(
                  decoration: FocusTheme.focusBackgroundDecoration(
                    context,
                    isFocused: isOptionsButtonFocused,
                    borderRadius: 20,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppIcon(Symbols.home_rounded, size: 18),
                      Switch(
                        value: SettingsService.instance.read(SettingsService.upcomingOnHome),
                        onChanged: (_) => _toggleHome(),
                      ),
                    ],
                  ),
                ),
              ),
            if (_hasLibraryMenu(library))
              Container(
                decoration: FocusTheme.focusBackgroundDecoration(
                  context,
                  isFocused: isOptionsButtonFocused,
                  borderRadius: 20,
                ),
                child: IconButton(
                  icon: const AppIcon(Symbols.more_vert_rounded, fill: 1),
                  tooltip: t.libraries.libraryOptions,
                  onPressed: () => _showLibraryMenuBottomSheet(context, library),
                ),
              ),
          ],
        ),
      ),
    );
  }
}


/// Fork: what a music library holds (music, audiobooks, audio dramas,
/// podcasts).
Future<void> _editAudioMode(BuildContext context, MediaLibrary library) async {
  final serverId = library.serverId;
  if (serverId == null) return;
  final current = AudioSettings.modeForLibrary(serverId, library.id);
  final picked = await showScopedDialog<AudioMode>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text('${RetroStrings.audioLibraryType}: ${library.title}'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(RetroStrings.audioLibraryTypeHint, style: const TextStyle(fontSize: 12)),
        ),
        for (final mode in AudioMode.values)
          ListTile(
            leading: AppIcon(
              mode == current ? Symbols.radio_button_checked_rounded : Symbols.radio_button_unchecked_rounded,
              fill: 1,
            ),
            title: Text(RetroStrings.audioMode(mode)),
            onTap: () => Navigator.of(dialogContext).pop(mode),
          ),
      ],
    ),
  );
  if (picked != null && picked != current) {
    await AudioSettings.setMode(serverId, library.id, picked);
    LibraryLanguageRules.revision.value++;
  }
}

/// Fork: the library's top bar: like the app setting, always visible, or
/// hidden when scrolling.
Future<void> _editTopBar(BuildContext context, MediaLibrary library) async {
  final current = TopBarPin.overrideFor(library.globalKey);
  final choices = <(bool?, String)>[
    (null, RetroStrings.topBarDefault(TopBarPin.appDefault)),
    (true, RetroStrings.topBarPinned),
    (false, RetroStrings.topBarFloating),
  ];
  final picked = await showScopedDialog<(bool?,)>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text('${RetroStrings.topBarMenu}: ${library.title}'),
      children: [
        for (final (value, label) in choices)
          ListTile(
            leading: AppIcon(
              value == current ? Symbols.radio_button_checked_rounded : Symbols.radio_button_unchecked_rounded,
              fill: 1,
            ),
            title: Text(label),
            onTap: () => Navigator.of(dialogContext).pop((value,)),
          ),
      ],
    ),
  );
  if (picked != null && picked.$1 != current) await TopBarPin.setOverride(library.globalKey, picked.$1);
}

/// Fork: asks for the audio and subtitle language of a library (ISO codes
/// such as "ja" or "de"; empty = the profile's languages).
Future<void> _editLibraryLanguages(BuildContext context, MediaLibrary library) async {
  await LibraryLanguageRules.load();
  if (!context.mounted) return;
  final rule = LibraryLanguageRules.forLibrary(library.globalKey);
  final result = await showScopedDialog<({String audio, String subtitle})>(
    context: context,
    builder: (_) => _LibraryLanguagesDialog(title: library.title, audio: rule?.audio, subtitle: rule?.subtitle),
  );
  if (result != null) {
    await LibraryLanguageRules.set(library.globalKey, audio: result.audio, subtitle: result.subtitle);
  }
}

/// Owns its text controllers so they outlive the closing animation.
class _LibraryLanguagesDialog extends StatefulWidget {
  const _LibraryLanguagesDialog({required this.title, this.audio, this.subtitle});

  final String title;
  final String? audio;
  final String? subtitle;

  @override
  State<_LibraryLanguagesDialog> createState() => _LibraryLanguagesDialogState();
}

class _LibraryLanguagesDialogState extends State<_LibraryLanguagesDialog> {
  late String _audio = _normalized(widget.audio);
  late String _subtitle = _normalized(widget.subtitle);

  static String _normalized(String? code) =>
      code == null || code.isEmpty ? '' : LanguageCodes.getIso6391Code(code) ?? code;

  /// Common languages first, then every language by name. Empty = the
  /// profile's language.
  static final List<({String code, String name})> _choices = () {
    const common = ['de', 'en', 'ja', 'fr', 'es', 'it', 'ko', 'zh', 'pt', 'ru', 'nl', 'sv', 'da', 'no', 'fi', 'pl', 'tr'];
    final all = LanguageCodes.getAllLanguages();
    final byCode = {for (final l in all) l.code: l};
    return [
      for (final code in common) ?byCode[code],
      for (final l in all)
        if (!common.contains(l.code)) l,
    ];
  }();

  Widget _picker(String label, String value, ValueChanged<String> onChanged) {
    return DropdownMenu<String>(
      initialSelection: value,
      label: Text(label),
      expandedInsets: EdgeInsets.zero,
      menuHeight: 360,
      enableFilter: true,
      requestFocusOnTap: true,
      onSelected: (v) => onChanged(v ?? ''),
      dropdownMenuEntries: [
        DropdownMenuEntry(value: '', label: RetroStrings.profileLanguage),
        for (final l in _choices) DropdownMenuEntry(value: l.code, label: l.name),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(RetroStrings.libraryLanguagesTitle(widget.title)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _picker(RetroStrings.audioLanguageCode, _audio, (v) => setState(() => _audio = v)),
            const SizedBox(height: 16),
            _picker(RetroStrings.subtitleLanguageCode, _subtitle, (v) => setState(() => _subtitle = v)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.common.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, (audio: _audio, subtitle: _subtitle)),
          child: Text(t.common.save),
        ),
      ],
    );
  }
}
