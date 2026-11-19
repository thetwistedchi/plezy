import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../widgets/app_icon.dart';

/// Compact search box next to the library tabs. Typing narrows Browse to
/// titles containing the text; Esc or the clear button empties it.
class LibrarySearchField extends StatefulWidget {
  const LibrarySearchField({super.key, required this.controller, required this.onChanged, this.libraryTitle});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? libraryTitle;

  @override
  State<LibrarySearchField> createState() => _LibrarySearchFieldState();
}

class _LibrarySearchFieldState extends State<LibrarySearchField> {
  bool get _de => LocaleSettings.currentLocale == AppLocale.de;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant LibrarySearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = widget.libraryTitle;
    final hint = title == null
        ? (_de ? 'In Mediathek suchen' : 'Search library')
        : (_de ? 'In $title suchen' : 'Search $title');
    return SizedBox(
      width: 240,
      height: 36,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clear},
        child: TextField(
          controller: widget.controller,
          onChanged: widget.onChanged,
          textInputAction: TextInputAction.search,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            prefixIcon: const AppIcon(Symbols.search_rounded, size: 18),
            prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            suffixIcon: widget.controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: _de ? 'Leeren' : 'Clear',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    icon: const AppIcon(Symbols.close_rounded, size: 16),
                    onPressed: _clear,
                  ),
            suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            filled: true,
            fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: scheme.primary, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}
