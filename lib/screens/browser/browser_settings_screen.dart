import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/retro_strings.dart';
import '../../services/browser/browser_controller.dart';
import '../../services/browser/browser_settings.dart';
import '../../theme/mono_tokens.dart';
import '../../theme/player_style.dart';

/// Options of the in-app browser.
class BrowserSettingsScreen extends StatefulWidget {
  const BrowserSettingsScreen({super.key});

  @override
  State<BrowserSettingsScreen> createState() => _BrowserSettingsScreenState();
}

class _BrowserSettingsScreenState extends State<BrowserSettingsScreen> {
  final _settings = BrowserSettings.instance;
  late final _customSearch = TextEditingController(text: _settings.customSearch);
  late final _customNewTab = TextEditingController(text: _settings.customNewTab);

  static const _suspendChoices = [1, 2, 5, 10, 15, 30, 60, 0];

  @override
  void initState() {
    super.initState();
    unawaited(_settings.load());
  }

  @override
  void dispose() {
    _customSearch.dispose();
    _customNewTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(RetroStrings.browserSettings)),
      body: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) {
          if (!_settings.isLoaded) return const Center(child: CircularProgressIndicator());
          final engine = _settings.searchEngine;
          final newTab = _settings.newTabPage;
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionTitle(RetroStrings.searchEngine),
                      _Card(
                        children: [
                          ListTile(
                            title: Text(RetroStrings.searchEngine),
                            trailing: DropdownButton<BrowserSearchEngine>(
                              value: engine,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final e in BrowserSearchEngine.values)
                                  DropdownMenuItem(
                                    value: e,
                                    child: Text(e == BrowserSearchEngine.custom ? RetroStrings.customSearchEngine : e.label),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v != null) unawaited(_settings.update(searchEngine: v));
                              },
                            ),
                          ),
                          if (engine == BrowserSearchEngine.custom)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: TextField(
                                controller: _customSearch,
                                decoration: InputDecoration(
                                  hintText: 'https://example.com/search?q=%s',
                                  helperText: RetroStrings.customSearchHint,
                                ),
                                onChanged: (v) => unawaited(_settings.update(customSearch: v.trim())),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(RetroStrings.newTabPageSetting),
                      _Card(
                        children: [
                          ListTile(
                            title: Text(RetroStrings.newTabPageSetting),
                            trailing: DropdownButton<BrowserNewTabPage>(
                              value: newTab,
                              underline: const SizedBox.shrink(),
                              items: [
                                DropdownMenuItem(value: BrowserNewTabPage.bookmarks, child: Text(RetroStrings.newTabBookmarks)),
                                DropdownMenuItem(value: BrowserNewTabPage.blank, child: Text(RetroStrings.newTabBlank)),
                                DropdownMenuItem(value: BrowserNewTabPage.custom, child: Text(RetroStrings.newTabCustom)),
                              ],
                              onChanged: (v) {
                                if (v != null) unawaited(_settings.update(newTabPage: v));
                              },
                            ),
                          ),
                          if (newTab == BrowserNewTabPage.custom)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: TextField(
                                controller: _customNewTab,
                                decoration: const InputDecoration(hintText: 'https://'),
                                onChanged: (v) => unawaited(_settings.update(customNewTab: v.trim())),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(RetroStrings.browser),
                      _Card(
                        children: [
                          ListTile(
                            title: Text(RetroStrings.suspendTabs),
                            subtitle: Text(RetroStrings.suspendDescription),
                            trailing: DropdownButton<int>(
                              value: _suspendChoices.contains(_settings.suspendMinutes) ? _settings.suspendMinutes : 5,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final m in _suspendChoices)
                                  DropdownMenuItem(value: m, child: Text(RetroStrings.suspendAfter(m))),
                              ],
                              onChanged: (v) {
                                if (v != null) unawaited(_settings.update(suspendMinutes: v));
                              },
                            ),
                          ),
                          SwitchListTile(
                            title: Text(RetroStrings.keepPlayingAwake),
                            value: _settings.keepPlayingAwake,
                            onChanged: (v) => unawaited(_settings.update(keepPlayingAwake: v)),
                          ),
                          SwitchListTile(
                            title: Text(RetroStrings.restoreTabs),
                            subtitle: Text(RetroStrings.restoreTabsDescription),
                            value: _settings.restoreTabs,
                            onChanged: (v) => unawaited(_settings.update(restoreTabs: v)),
                          ),
                          SwitchListTile(
                            title: Text(RetroStrings.httpsUpgrade),
                            subtitle: Text(RetroStrings.httpsUpgradeDescription),
                            value: _settings.httpsUpgrade,
                            onChanged: (v) {
                              unawaited(_settings.update(httpsUpgrade: v));
                              unawaited(BrowserController.instance.setHttpsUpgrade(v));
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(RetroStrings.browserProtection),
                      _Card(children: [ListTile(subtitle: Text(RetroStrings.browserProtectionDescription))]),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
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
