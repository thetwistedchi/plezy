import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../models/catalog/catalog_item.dart';
import '../../providers/seerr_account_provider.dart';
import '../../services/discord_rpc_service.dart';
import '../../services/settings_service.dart';
import '../../services/youtube/youtube_settings.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/catalog_source_logo.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_section.dart';
import '../youtube/youtube_settings_screen.dart';
import 'seerr_connect_screen.dart';
import 'seerr_settings_screen.dart';
import 'tracker_service_info.dart';
import '../youtube/youtube_routes.dart';

/// Unified hub for all connected services: the watch-progress trackers
/// (Trakt, MyAnimeList, AniList, Simkl) and the Seerr request server. Each
/// row opens its service-specific settings screen.
bool get _de => LocaleSettings.currentLocale == AppLocale.de;

class ServicesSettingsScreen extends StatelessWidget {
  const ServicesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FocusedScrollScaffold(
      title: Text(t.services.title),
      slivers: [
        SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                t.services.hubSubtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            SettingsGroup(
              children: [for (final info in TrackerServiceInfo.all) _TrackerHubRow(info), _seerr(), _youtube()],
            ),
            SettingsGroup(
              title: _de ? 'Bewertungsquellen' : 'Rating sources',
              children: [
                _ApiKeyTile(
                  pref: SettingsService.mdblistApiKey,
                  title: 'MDBList',
                  subtitle: _de
                      ? 'Eine Anfrage für IMDb, TMDB, Trakt, Letterboxd, Rotten Tomatoes, Metacritic und MyAnimeList. Kostenloser API-Schlüssel auf mdblist.com (1.000 Anfragen pro Tag).'
                      : 'One request for IMDb, TMDB, Trakt, Letterboxd, Rotten Tomatoes, Metacritic and MyAnimeList. Free API key at mdblist.com (1,000 requests a day).',
                  keyUrl: 'https://mdblist.com/preferences/',
                ),
                _ApiKeyTile(
                  pref: SettingsService.omdbApiKey,
                  title: 'OMDb',
                  subtitle: _de
                      ? 'IMDb, Tomatometer und Metascore, wenn MDBList sie nicht liefert. Kostenloser API-Schlüssel auf omdbapi.com (1.000 Anfragen pro Tag).'
                      : 'IMDb, Tomatometer and Metascore when MDBList has none. Free API key at omdbapi.com (1,000 requests a day).',
                  keyUrl: 'https://www.omdbapi.com/apikey.aspx',
                ),
                SettingSwitchTile(
                  pref: SettingsService.jikanRatings,
                  icon: Symbols.animation_rounded,
                  title: 'MyAnimeList (Jikan)',
                  subtitle: _de
                      ? 'MyAnimeList-Wertung für Anime, ohne Schlüssel.'
                      : 'MyAnimeList score for anime, no key needed.',
                ),
              ],
            ),
            if (DiscordRPCService.isAvailable)
              SettingsGroup(
                title: t.services.integrations,
                children: [
                  SettingSwitchTile(
                    pref: SettingsService.enableDiscordRPC,
                    icon: Symbols.chat_rounded,
                    title: t.settings.discordRichPresence,
                    subtitle: t.settings.discordRichPresenceDescription,
                  ),
                ],
              ),
            const SizedBox(height: 24),
          ]),
        ),
      ],
    );
  }

  Widget _youtube() => ListenableBuilder(
    listenable: YouTubeSettings.instance,
    builder: (context, _) {
      final settings = YouTubeSettings.instance;
      if (!settings.isLoaded) unawaited(settings.load());
      return _ServiceHubRow(
        leading: const AppIcon(Symbols.smart_display_rounded, size: 24),
        title: 'YouTube',
        username: settings.isSignedIn ? (settings.accountName.isEmpty ? 'Google' : settings.accountName) : null,
        onTap: () => Navigator.push(context, ytRoute('settings', (_) => const YouTubeSettingsScreen())),
      );
    },
  );

  Widget _seerr() => Consumer<SeerrAccountProvider>(
    builder: (context, account, _) => _ServiceHubRow(
      leading: const CatalogSourceLogo(CatalogSourceId.seerr, size: 24),
      title: t.services.names.seerr,
      username: account.isConnected ? account.displayName : null,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => account.isConnected ? const SeerrSettingsScreen() : const SeerrConnectScreen(),
          ),
        );
      },
    ),
  );
}

/// Hub row for a watch tracker. Owns the `watch` on that service's account
/// provider so only this row rebuilds when the connection state changes.
class _TrackerHubRow extends StatelessWidget {
  final TrackerServiceInfo info;

  const _TrackerHubRow(this.info);

  @override
  Widget build(BuildContext context) {
    final connected = info.isConnected(context);
    return _ServiceHubRow(
      leading: CatalogSourceLogo(info.logoSource, size: 24),
      title: info.displayName,
      username: connected ? info.username(context) : null,
      onTap: () {
        if (connected) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => info.buildSettingsScreen()));
        } else {
          info.startConnection(context);
        }
      },
    );
  }
}

class _ServiceHubRow extends StatelessWidget {
  final Widget leading;
  final String title;

  /// Non-null when connected. When null, the subtitle shows "Not connected".
  final String? username;

  final VoidCallback onTap;

  const _ServiceHubRow({required this.leading, required this.title, required this.username, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FocusableListTile(
      leading: leading,
      title: Text(title),
      subtitle: Text(username != null ? t.services.connectedAs(username: username!) : t.services.notConnected),
      trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
      onTap: onTap,
    );
  }
}

/// A rating provider's API key: shows whether one is set, edits it in a
/// dialog. Keys stay on this device and are not part of settings exports.
class _ApiKeyTile extends StatelessWidget {
  const _ApiKeyTile({required this.pref, required this.title, required this.subtitle, required this.keyUrl});

  final StringPref pref;
  final String title;
  final String subtitle;
  final String keyUrl;

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: SettingsService.instance.read(pref));
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(keyUrl),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(labelText: _de ? 'API-Schlüssel' : 'API key'),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ''), child: Text(_de ? 'Entfernen' : 'Remove')),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(_de ? 'Abbrechen' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(_de ? 'Speichern' : 'Save')),
        ],
      ),
    );
    controller.dispose();
    if (result != null) await SettingsService.instance.write(pref, result.trim());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: SettingsService.instance.listenable(pref),
      builder: (context, value, _) {
        final set = value.trim().isNotEmpty;
        final status = set
            ? (_de ? 'Schlüssel gesetzt' : 'Key set')
            : (_de ? 'Kein Schlüssel' : 'No key');
        return FocusableListTile(
          leading: AppIcon(set ? Symbols.key_rounded : Symbols.key_off_rounded),
          title: Text('$title · $status'),
          subtitle: Text(subtitle),
          onTap: () => unawaited(_edit(context)),
        );
      },
    );
  }
}
