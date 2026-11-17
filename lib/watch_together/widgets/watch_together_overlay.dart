import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../theme/player_style.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/overlay_sheet.dart';
import '../providers/watch_together_provider.dart';
import 'watch_session_sheet.dart';

/// The player header's room pill: participant count and connection; it opens
/// the session sheet.
class WatchTogetherSessionIndicator extends StatelessWidget {
  const WatchTogetherSessionIndicator({super.key, this.onCancelAutoHide, this.onStartAutoHide});

  final VoidCallback? onCancelAutoHide;
  final VoidCallback? onStartAutoHide;

  void _open(BuildContext context) {
    onCancelAutoHide?.call();
    unawaited(showWatchSessionSheet(context).whenComplete(() => onStartAutoHide?.call()));
  }

  @override
  Widget build(BuildContext context) {
    final (count, connected, reconnecting, isHost) = context.select<WatchTogetherProvider, (int, bool, bool, bool)>(
      (provider) => (provider.participantCount, provider.isConnected, provider.isReconnecting, provider.isHost),
    );
    // Who drives playback: "HOST" for the host; for a guest in a host-only
    // room, a lock and the host's name, so a dimmed play button explains
    // itself.
    final (hostOnly, hostName) = context.select<WatchTogetherProvider, (bool, String?)>(
      (provider) => (!provider.canControl, provider.host?.name),
    );
    final highlight = playerActiveColor(context);
    final status = reconnecting
        ? t.watchTogether.reconnecting
        : connected
        ? t.watchTogether.connected
        : t.watchTogether.connecting;
    return FocusableWrapper(
      onSelect: () => _open(context),
      semanticLabel: t.watchTogether.openSessionControls,
      semanticValue: [
        t.watchTogether.participantCount(n: count),
        status,
        if (isHost) t.watchTogether.youAreHost,
      ].join(', '),
      descendantsAreFocusable: false,
      borderRadius: 20,
      useBackgroundFocus: true,
      focusColor: FocusTheme.onMediaFocusFill,
      child: Material(
        color: Colors.black54,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        child: InkWell(
          canRequestFocus: false,
          onTap: () => _open(context),
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!connected)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: PlatformDetector.isTV()
                        ? const AppIcon(Symbols.sync_rounded, size: 16, color: Colors.white)
                        : const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                else
                  AppIcon(Symbols.group_rounded, size: 18, fill: 1, color: isHost ? highlight : Colors.white),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (connected && isHost) ...[
                  const SizedBox(width: 8),
                  Text(
                    t.watchTogether.hostBadge,
                    style: TextStyle(color: highlight, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.8),
                  ),
                ] else if (connected && hostOnly && hostName != null) ...[
                  const SizedBox(width: 8),
                  const AppIcon(Symbols.lock_rounded, size: 14, fill: 1, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(
                    t.watchTogether.hostedBy(name: hostName),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
                if (reconnecting) ...[
                  const SizedBox(width: 6),
                  Text(t.watchTogether.reconnecting, style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the mismatch prompt in the player's sheet host when the room offers
/// a copy of a different length: once per mismatch, never for the host's own
/// media, and only once no other sheet is open.
class WatchMismatchPromptLauncher extends StatefulWidget {
  const WatchMismatchPromptLauncher({super.key});

  @override
  State<WatchMismatchPromptLauncher> createState() => _WatchMismatchPromptLauncherState();
}

class _WatchMismatchPromptLauncherState extends State<WatchMismatchPromptLauncher> {
  WatchTogetherProvider? _provider;
  String? _askedKey;
  bool _waitingForSheet = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<WatchTogetherProvider>(context, listen: false);
    if (identical(provider, _provider)) return;
    _provider?.removeListener(_scheduleCheck);
    _provider = provider..addListener(_scheduleCheck);
    _scheduleCheck();
  }

  @override
  void dispose() {
    _provider?.removeListener(_scheduleCheck);
    _stopWaiting();
    super.dispose();
  }

  /// Checks after the frame: the room may change mid-build, and opening a
  /// sheet rebuilds the host.
  void _scheduleCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _check() {
    final provider = _provider;
    if (!mounted || provider == null) return;
    final key = watchMismatchPromptKey(provider);
    if (key == null || key == _askedKey) return;
    final controller = OverlaySheetController.maybeOf(context);
    if (controller == null) return;
    if (controller.isOpen) {
      _waitForSheet();
      return;
    }
    _askedKey = key;
    unawaited(controller.show<void>(showDragHandle: true, builder: (_) => WatchMismatchPrompt(promptKey: key)));
  }

  void _waitForSheet() {
    if (_waitingForSheet) return;
    _waitingForSheet = true;
    OverlaySheetController.openSheetCount.addListener(_onSheetCountChanged);
  }

  void _stopWaiting() {
    if (!_waitingForSheet) return;
    _waitingForSheet = false;
    OverlaySheetController.openSheetCount.removeListener(_onSheetCountChanged);
  }

  void _onSheetCountChanged() {
    _stopWaiting();
    // A sheet that just opened elsewhere keeps this one waiting; one that
    // closed is off its host by now.
    _scheduleCheck();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
