import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/retro_strings.dart';
import '../../services/browser/browser_controller.dart';
import '../../services/browser/browser_history.dart';
import '../../services/browser/browser_native.dart';
import '../../services/browser/browser_settings.dart';
import '../../theme/mono_tokens.dart';
import '../../theme/player_style.dart';
import '../../widgets/app_icon.dart';

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
  final _cacheLimit = TextEditingController();
  int? _cacheBytes;
  bool _clearing = false;
  bool _clearingSiteData = false;

  Future<void> _clearSiteData() async {
    setState(() => _clearingSiteData = true);
    try {
      await BrowserController.instance.clearSiteData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(RetroStrings.siteDataDeleted)));
      }
    } finally {
      if (mounted) setState(() => _clearingSiteData = false);
    }
  }

  static const _suspendChoices = [1, 2, 5, 10, 15, 30, 60, 0];
  static const _recentChoices = [5, 10, 15, 20, 30];

  @override
  void initState() {
    super.initState();
    unawaited(
      _settings.load().then((_) {
        if (mounted) _cacheLimit.text = '${_settings.cacheLimitMb}';
      }),
    );
    unawaited(_loadCacheSize());
  }

  Future<void> _loadCacheSize() async {
    final bytes = await BrowserNative.cacheSize();
    if (mounted) setState(() => _cacheBytes = bytes);
  }

  Future<void> _saveCacheLimit() async {
    final value = int.tryParse(_cacheLimit.text.trim());
    if (value != null) await _settings.update(cacheLimitMb: value);
    _cacheLimit.text = '${_settings.cacheLimitMb}';
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    try {
      await BrowserController.instance.clearCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(RetroStrings.browserCacheCleared)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _clearing = false);
      await _loadCacheSize();
    }
  }

  @override
  void dispose() {
    _customSearch.dispose();
    _customNewTab.dispose();
    _cacheLimit.dispose();
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
                                DropdownMenuItem(value: BrowserNewTabPage.recent, child: Text(RetroStrings.newTabRecent)),
                                DropdownMenuItem(value: BrowserNewTabPage.blank, child: Text(RetroStrings.newTabBlank)),
                                DropdownMenuItem(value: BrowserNewTabPage.custom, child: Text(RetroStrings.newTabCustom)),
                              ],
                              onChanged: (v) {
                                if (v != null) unawaited(_settings.update(newTabPage: v));
                              },
                            ),
                          ),
                          if (newTab == BrowserNewTabPage.recent)
                            ListTile(
                              title: Text(RetroStrings.recentCount),
                              trailing: DropdownButton<int>(
                                value: _recentChoices.contains(_settings.recentCount) ? _settings.recentCount : 10,
                                underline: const SizedBox.shrink(),
                                items: [
                                  for (final n in _recentChoices) DropdownMenuItem(value: n, child: Text('$n')),
                                ],
                                onChanged: (v) {
                                  if (v != null) unawaited(_settings.update(recentCount: v));
                                },
                              ),
                            ),
                          SwitchListTile(
                            title: Text(RetroStrings.keepHistory),
                            subtitle: Text(RetroStrings.keepHistoryDescription),
                            value: _settings.keepHistory,
                            onChanged: (v) async {
                              await _settings.update(keepHistory: v);
                              await BrowserHistory.instance.persistChanged();
                            },
                          ),
                          ListTile(
                            title: Text(RetroStrings.clearHistory),
                            subtitle: Text(RetroStrings.historyDescription),
                            trailing: OutlinedButton(
                              onPressed: () async {
                                await BrowserHistory.instance.clear();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(RetroStrings.historyCleared)),
                                  );
                                }
                              },
                              child: Text(RetroStrings.clearHistory),
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
                      _SectionTitle(RetroStrings.browserCache),
                      _Card(
                        children: [
                          ListTile(
                            leading: AppIcon(Symbols.storage_rounded, color: tokens(context).textMuted),
                            title: Text(RetroStrings.browserCacheLimit),
                            subtitle: Text(RetroStrings.browserCacheLimitDescription),
                            trailing: SizedBox(
                              width: 140,
                              child: Focus(
                                onFocusChange: (focused) {
                                  if (!focused) unawaited(_saveCacheLimit());
                                },
                                child: TextField(
                                  controller: _cacheLimit,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  textAlign: TextAlign.end,
                                  decoration: const InputDecoration(isDense: true, suffixText: 'MB'),
                                  onSubmitted: (_) => unawaited(_saveCacheLimit()),
                                ),
                              ),
                            ),
                          ),
                          ListTile(
                            leading: AppIcon(Symbols.cleaning_services_rounded, color: tokens(context).textMuted),
                            title: Text(RetroStrings.browserCache),
                            subtitle: Text(RetroStrings.browserCacheUsed(RetroStrings.fileSize(_cacheBytes ?? 0))),
                            trailing: OutlinedButton(
                              onPressed: _clearing ? null : () => unawaited(_clearCache()),
                              child: _clearing
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(RetroStrings.clearBrowserCache),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(RetroStrings.trackingPrevention),
                      _Card(
                        children: [
                          ListTile(
                            title: Text(RetroStrings.trackingPrevention),
                            subtitle: Text(RetroStrings.trackingDescription),
                            trailing: DropdownButton<int>(
                              value: _settings.trackingLevel.clamp(0, 3),
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final level in const [0, 1, 2, 3])
                                  DropdownMenuItem(value: level, child: Text(RetroStrings.trackingLevel(level))),
                              ],
                              onChanged: (v) {
                                if (v != null) unawaited(BrowserController.instance.setTrackingLevel(v));
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(RetroStrings.siteData),
                      _Card(
                        children: [
                          ListTile(
                            title: Text(RetroStrings.siteData),
                            subtitle: Text(RetroStrings.siteDataDescription),
                            trailing: OutlinedButton(
                              onPressed: _clearingSiteData ? null : () => unawaited(_clearSiteData()),
                              child: _clearingSiteData
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(RetroStrings.deleteSiteData),
                            ),
                          ),
                          SwitchListTile(
                            title: Text(RetroStrings.clearOnExit),
                            subtitle: Text(RetroStrings.clearOnExitDescription),
                            value: _settings.clearSiteDataOnExit,
                            onChanged: (v) => unawaited(_settings.update(clearSiteDataOnExit: v)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(RetroStrings.sitePermissions),
                      _Card(
                        children: [
                          if (_settings.permissions.isEmpty)
                            ListTile(subtitle: Text(RetroStrings.sitePermissionsEmpty))
                          else
                            for (final entry in _settings.permissions.entries)
                              ListTile(
                                title: Text(entry.key.substring(0, entry.key.lastIndexOf('|'))),
                                subtitle: Text(
                                  '${RetroStrings.permissionLabel(int.tryParse(entry.key.substring(entry.key.lastIndexOf('|') + 1)) ?? 0)}: '
                                  '${entry.value ? RetroStrings.allowed : RetroStrings.blocked}',
                                ),
                                trailing: IconButton(
                                  icon: const AppIcon.retro(Symbols.close_rounded, size: 18),
                                  tooltip: RetroStrings.delete,
                                  onPressed: () {
                                    final i = entry.key.lastIndexOf('|');
                                    unawaited(
                                      _settings.setPermission(
                                        entry.key.substring(0, i),
                                        int.tryParse(entry.key.substring(i + 1)) ?? 0,
                                        null,
                                      ),
                                    );
                                  },
                                ),
                              ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(RetroStrings.popupSites),
                      _Card(
                        children: [
                          if (_settings.popupSites.isEmpty)
                            ListTile(subtitle: Text(RetroStrings.popupSitesEmpty))
                          else
                            for (final site in _settings.popupSites)
                              ListTile(
                                title: Text(site),
                                trailing: IconButton(
                                  icon: const AppIcon.retro(Symbols.close_rounded, size: 18),
                                  tooltip: RetroStrings.delete,
                                  onPressed: () => unawaited(BrowserController.instance.setPopupAllowed(site, false)),
                                ),
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
