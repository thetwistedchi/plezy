import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/retro_strings.dart';
import '../../services/browser/browser_controller.dart';
import '../../services/browser/browser_history.dart';
import '../../theme/mono_tokens.dart';
import 'browser_icon.dart';

/// The browser's history, shown in a tab (plezy://history): searchable,
/// grouped by day, single entries removable.
class BrowserHistoryPage extends StatefulWidget {
  const BrowserHistoryPage({super.key});

  @override
  State<BrowserHistoryPage> createState() => _BrowserHistoryPageState();
}

class _BrowserHistoryPageState extends State<BrowserHistoryPage> {
  final _history = BrowserHistory.instance;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _group(DateTime? at) {
    if (at == null) return RetroStrings.earlier;
    final now = DateTime.now();
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return RetroStrings.today;
    if (diff == 1) return RetroStrings.yesterday;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.day)}.${two(at.month)}.${at.year}';
  }

  String _time(DateTime? at) {
    if (at == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    final local = at.toLocal();
    return '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_history, _search]),
      builder: (context, _) {
        final query = _search.text.trim().toLowerCase();
        final items = _history
            .recent(BrowserHistory.maxEntries)
            .where((p) => query.isEmpty || p.url.toLowerCase().contains(query) || p.title.toLowerCase().contains(query))
            .toList();
        final children = <Widget>[];
        String? last;
        for (final page in items) {
          final group = _group(page.at?.toLocal());
          if (group != last) {
            last = group;
            children.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text(group, style: TextStyle(color: t.textMuted, fontWeight: FontWeight.w600)),
              ),
            );
          }
          children.add(
            ListTile(
              dense: true,
              leading: SizedBox(
                width: 44,
                child: Text(_time(page.at), style: TextStyle(color: t.textMuted, fontSize: 12)),
              ),
              title: Text(page.title.isEmpty ? page.host : page.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(page.host, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => unawaited(BrowserController.instance.go(page.url)),
              trailing: IconButton(
                icon: const BrowserIcon(Symbols.close_rounded, size: 16),
                tooltip: RetroStrings.removeFromList,
                onPressed: () => unawaited(_history.remove(page.url)),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(RetroStrings.history, style: Theme.of(context).textTheme.headlineSmall),
                          ),
                          TextButton(
                            onPressed: items.isEmpty && query.isEmpty ? null : () => unawaited(_history.clear()),
                            child: Text(RetroStrings.clearHistory),
                          ),
                        ],
                      ),
                    ),
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        hintText: RetroStrings.searchHistory,
                        prefixIcon: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: BrowserIcon(Symbols.search_rounded, size: 18),
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 40),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(t.radiusLg),
                        border: Border.all(color: t.outline),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children.isEmpty
                            ? [ListTile(subtitle: Text(RetroStrings.historyEmpty))]
                            : [...children, const SizedBox(height: 8)],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
