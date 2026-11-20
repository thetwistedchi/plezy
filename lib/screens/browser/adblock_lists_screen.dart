import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/retro_strings.dart';
import '../../services/browser/adblock_lists.dart';
import '../../theme/mono_tokens.dart';
import '../../theme/player_style.dart';
import '../../widgets/app_icon.dart';

/// The ad blocker's filter lists, like uBlock Origin's "Filter lists" page,
/// plus the user's own filters and the sites without blocking.
class AdblockListsScreen extends StatefulWidget {
  const AdblockListsScreen({super.key});

  @override
  State<AdblockListsScreen> createState() => _AdblockListsScreenState();
}

class _AdblockListsScreenState extends State<AdblockListsScreen> {
  final _adblock = AdblockManager.instance;
  final _customUrl = TextEditingController();
  final _filters = TextEditingController();
  bool _filtersLoaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      _adblock.load().then((_) {
        if (!mounted) return;
        setState(() {
          _filters.text = _adblock.userFilters;
          _filtersLoaded = true;
        });
      }),
    );
  }

  @override
  void dispose() {
    _customUrl.dispose();
    _filters.dispose();
    super.dispose();
  }

  String _when(DateTime time) {
    final local = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}. ${two(local.hour)}:${two(local.minute)}';
  }

  String _status(String id) {
    final state = _adblock.states[id];
    if (state == null || state.updatedAt == null) {
      return state?.error != null ? RetroStrings.listFailed : RetroStrings.listNotLoaded;
    }
    final parts = [RetroStrings.listRules(state.rules), _when(state.updatedAt!)];
    if (state.error != null) parts.add(RetroStrings.listFailed);
    return parts.join(' · ');
  }

  Future<void> _addCustom() async {
    final url = _customUrl.text.trim();
    if (url.isEmpty) return;
    _customUrl.clear();
    final ok = await _adblock.addCustomList(url);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(RetroStrings.listFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Shown inside a browser tab (plezy://filters), so no app bar.
    return ListenableBuilder(
        listenable: _adblock,
        builder: (context, _) {
          if (!_adblock.isLoaded) return const Center(child: CircularProgressIndicator());
          final groups = <FilterGroup, List<FilterListInfo>>{};
          for (final list in filterListCatalog) {
            groups.putIfAbsent(list.group, () => []).add(list);
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
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(RetroStrings.filterLists, style: Theme.of(context).textTheme.headlineSmall),
                            ),
                            TextButton.icon(
                              onPressed: _adblock.updating || !_adblock.enabled
                                  ? null
                                  : () => unawaited(_adblock.update(force: true)),
                              icon: _adblock.updating
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const AppIcon.retro(Symbols.refresh_rounded, size: 18),
                              label: Text(_adblock.updating ? RetroStrings.updatingLists : RetroStrings.updateLists),
                            ),
                          ],
                        ),
                      ),
                      _Card(
                        children: [
                          SwitchListTile(
                            title: Text(RetroStrings.adblock),
                            subtitle: Text(RetroStrings.adblockDescription),
                            value: _adblock.enabled,
                            onChanged: (v) => unawaited(_adblock.setEnabled(v)),
                          ),
                        ],
                      ),
                      for (final entry in groups.entries) ...[
                        const SizedBox(height: 24),
                        _SectionTitle(RetroStrings.filterGroup(entry.key.name)),
                        _Card(
                          children: [
                            for (final list in entry.value)
                              CheckboxListTile(
                                value: _adblock.enabledLists.contains(list.id),
                                onChanged: _adblock.enabled
                                    ? (v) => unawaited(_adblock.setListEnabled(list.id, v ?? false))
                                    : null,
                                title: Text(list.name),
                                subtitle: _adblock.enabledLists.contains(list.id) ? Text(_status(list.id)) : null,
                                controlAffinity: ListTileControlAffinity.leading,
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      _SectionTitle(RetroStrings.customLists),
                      _Card(
                        children: [
                          for (final url in _adblock.customUrls)
                            ListTile(
                              title: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(_status(AdblockManager.customId(url))),
                              trailing: IconButton(
                                icon: const AppIcon.retro(Symbols.close_rounded, size: 18),
                                tooltip: RetroStrings.delete,
                                onPressed: () => unawaited(_adblock.removeCustomList(url)),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _customUrl,
                                    keyboardType: TextInputType.url,
                                    decoration: InputDecoration(hintText: RetroStrings.addListUrl, isDense: true),
                                    onSubmitted: (_) => unawaited(_addCustom()),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(onPressed: () => unawaited(_addCustom()), child: Text(RetroStrings.addList)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(RetroStrings.myFilters),
                      _Card(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _filters,
                                  enabled: _filtersLoaded,
                                  minLines: 6,
                                  maxLines: 16,
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: RetroStrings.myFiltersHint,
                                    hintMaxLines: 3,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton(
                                    onPressed: () => unawaited(_adblock.setUserFilters(_filters.text)),
                                    child: Text(RetroStrings.apply),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(RetroStrings.adblockOffSites),
                      _Card(
                        children: [
                          if (_adblock.offSites.isEmpty)
                            ListTile(subtitle: Text(RetroStrings.adblockOffSitesEmpty))
                          else
                            for (final site in _adblock.offSites)
                              ListTile(
                                title: Text(site),
                                trailing: IconButton(
                                  icon: const AppIcon.retro(Symbols.close_rounded, size: 18),
                                  tooltip: RetroStrings.delete,
                                  onPressed: () => unawaited(_adblock.setOffForSite(site, false)),
                                ),
                              ),
                        ],
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: playerActiveColor(context),
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return Container(
      decoration: BoxDecoration(
        color: mono.surface,
        borderRadius: BorderRadius.circular(mono.radiusLg),
        border: Border.all(color: mono.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}
