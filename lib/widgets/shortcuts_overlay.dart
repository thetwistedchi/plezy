import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/retro_strings.dart';
import '../services/keyboard_shortcuts_service.dart';
import '../theme/retrowave_colors.dart';
import '../utils/platform_detector.dart';

/// Desktop: `?` anywhere (outside text fields) lists the keyboard shortcuts,
/// including the player keys as currently configured.
class ShortcutsOverlay {
  ShortcutsOverlay._();

  static BuildContext Function()? _contextOf;
  static bool _open = false;

  /// Installs the global `?` handler. [contextOf] gives a context below the
  /// app's Navigator.
  static void install(BuildContext Function() contextOf) {
    if (!PlatformDetector.isDesktopOS() || _contextOf != null) return;
    _contextOf = contextOf;
    HardwareKeyboard.instance.addHandler(_handle);
  }

  static void uninstall() {
    if (_contextOf == null) return;
    HardwareKeyboard.instance.removeHandler(_handle);
    _contextOf = null;
  }

  static bool _handle(KeyEvent event) {
    if (event is! KeyDownEvent || event.character != '?' || _open) return false;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && (focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    final context = _contextOf?.call();
    if (context == null || !context.mounted) return false;
    unawaited(show(context));
    return true;
  }

  static Future<void> show(BuildContext context) async {
    if (_open) return;
    _open = true;
    try {
      final service = await KeyboardShortcutsService.getInstance();
      if (!context.mounted) return;
      await showDialog<void>(context: context, builder: (_) => _ShortcutsDialog(service: service));
    } finally {
      _open = false;
    }
  }
}

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog({required this.service});
  final KeyboardShortcutsService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final retro = RetroColors.isActive(context);
    final heading = theme.textTheme.titleSmall?.copyWith(
      color: retro ? const Color(0xFF9DB4FF) : theme.colorScheme.primary,
      fontWeight: FontWeight.w700,
    );
    final general = <(String, String)>[
      ('?', RetroStrings.shortcuts),
      ('← ↑ → ↓', _arrowLabel),
      ('Enter', _enterLabel),
      ('Esc', _backLabel),
    ];
    final hotkeys = service.hotkeys;
    final player = [
      for (final entry in hotkeys.entries)
        if (entry.value != null) (service.formatHotkey(entry.value), service.getActionDisplayName(entry.key)),
    ];

    Widget row((String, String) item) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 96),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(item.$1, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(item.$2, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );

    return AlertDialog(
      title: Text(RetroStrings.shortcuts),
      content: SizedBox(
        width: 520,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(RetroStrings.general, style: heading),
            const SizedBox(height: 6),
            ...general.map(row),
            if (player.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(RetroStrings.player, style: heading),
              const SizedBox(height: 6),
              ...player.map(row),
            ],
            const SizedBox(height: 12),
            Text(RetroStrings.shortcutsHint, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(RetroStrings.close))],
    );
  }

  static String get _arrowLabel => RetroStrings.moveFocus;
  static String get _enterLabel => RetroStrings.openSelect;
  static String get _backLabel => RetroStrings.goBack;
}
