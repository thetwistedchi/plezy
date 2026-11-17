import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import '../../theme/player_style.dart';
import '../../widgets/app_icon.dart';
import 'youtube_strings.dart';

/// In-app how-to for the YouTube tab: what works without an account, how to
/// import subscriptions, Premium, the optional Google sign-in, SponsorBlock
/// and the player's shortcuts.
class YouTubeGuideScreen extends StatelessWidget {
  const YouTubeGuideScreen({super.key});

  static bool get _de => LocaleSettings.currentLocale == AppLocale.de;
  static String _t(String en, String de) => _de ? de : en;

  @override
  Widget build(BuildContext context) {
    final sections = <_Section>[
      _Section(
        icon: Symbols.rocket_launch_rounded,
        title: _t('Quick start, no account needed', 'Schnellstart, ohne Konto'),
        steps: [
          _t(
            'Open YouTube › Channels and paste a channel link, a video link or an @handle, then click Add.',
            'Öffne YouTube › Kanäle und füge einen Kanal-Link, Video-Link oder ein @Handle ein, dann Hinzufügen.',
          ),
          _t(
            'Or import all your subscriptions at once with Google Takeout (next section).',
            'Oder importiere alle Abos auf einmal mit Google Takeout (nächster Abschnitt).',
          ),
          _t(
            'The newest videos of these channels appear in the Subscriptions view. They come from YouTube\'s '
                'public RSS feeds, so no Google account and no API quota is used.',
            'Die neuesten Videos dieser Kanäle erscheinen unter Abos. Sie kommen aus YouTubes öffentlichen '
                'RSS-Feeds, ganz ohne Google-Konto und ohne API-Kontingent.',
          ),
        ],
        note: _t(
          'Without a Google sign-in, video lengths, comments, likes and full channel pages (beyond the newest 15 '
              'videos) are not available.',
          'Ohne Google-Anmeldung fehlen Videolängen, Kommentare, Likes und vollständige Kanalseiten (über die '
              'neuesten 15 Videos hinaus).',
        ),
      ),
      _Section(
        icon: Symbols.upload_file_rounded,
        title: _t('Import subscriptions with Google Takeout', 'Abos mit Google Takeout importieren'),
        steps: [
          _t('Open takeout.google.com and sign in.', 'Öffne takeout.google.com und melde dich an.'),
          _t('Click "Deselect all", then tick only "YouTube and YouTube Music".',
              'Klicke „Auswahl aufheben“ und hake nur „YouTube und YouTube Music“ an.'),
          _t('Click "All YouTube data included", keep only "subscriptions" and confirm.',
              'Klicke „Alle YouTube-Daten ausgewählt“, lass nur „Abos“ an und bestätige.'),
          _t('Create the export and download the zip file when Google emails you.',
              'Erstelle den Export und lade die ZIP-Datei herunter, sobald Google dir eine Mail schickt.'),
          _t(
            'Unzip it. In YouTube › Channels click "Import from Google Takeout" and pick '
                'Takeout/YouTube and YouTube Music/subscriptions/subscriptions.csv.',
            'Entpacke sie. Klicke unter YouTube › Kanäle auf „Aus Google Takeout importieren“ und wähle '
                'Takeout/YouTube und YouTube Music/Abos/subscriptions.csv.',
          ),
        ],
        link: ('takeout.google.com', 'https://takeout.google.com'),
      ),
      _Section(
        icon: Symbols.workspace_premium_rounded,
        title: _t('YouTube Premium (no ads)', 'YouTube Premium (ohne Werbung)'),
        steps: [
          _t('Open YouTube settings › Player sign-in › Sign in to YouTube.',
              'Öffne die YouTube-Einstellungen › Player-Anmeldung › Bei YouTube anmelden.'),
          _t('Sign in with your Premium account and click Done.',
              'Melde dich mit deinem Premium-Konto an und klicke Fertig.'),
          _t(
            'The player now plays without ads. This works with or without the Google sign-in below.',
            'Der Player spielt jetzt ohne Werbung. Das klappt mit und ohne die Google-Anmeldung unten.',
          ),
        ],
      ),
      _Section(
        icon: Symbols.account_circle_rounded,
        title: _t('Optional: sign in with Google', 'Optional: mit Google anmelden'),
        intro: _t(
          'Adds automatic import of your subscriptions, video lengths, comments (read and write), likes and full '
              'channel pages. Each user needs their own free Google Cloud project:',
          'Bringt automatischen Import deiner Abos, Videolängen, Kommentare (lesen und schreiben), Likes und '
              'vollständige Kanalseiten. Jeder Nutzer braucht ein eigenes, kostenloses Google-Cloud-Projekt:',
        ),
        steps: [
          _t('Open console.cloud.google.com and create a new project.',
              'Öffne console.cloud.google.com und lege ein neues Projekt an.'),
          _t('APIs & Services › Library: enable "YouTube Data API v3".',
              'APIs & Dienste › Bibliothek: „YouTube Data API v3“ aktivieren.'),
          _t(
            'Google Auth Platform › Branding: enter an app name and your email. Leave the logo empty.',
            'Google Auth Platform › Branding: App-Namen und deine E-Mail eintragen. Kein Logo hochladen.',
          ),
          _t(
            'Audience: add your Google account as a test user, or click "Publish app".',
            'Zielgruppe: dein Google-Konto als Testnutzer eintragen oder „App veröffentlichen“ klicken.',
          ),
          _t(
            'Clients › Create client: type "Desktop app". Copy the client ID and secret into YouTube settings.',
            'Clients › Client erstellen: Typ „Desktop-App“. Client ID und Secret in die YouTube-Einstellungen kopieren.',
          ),
          _t(
            'Click "Sign in with Google". Google warns that the app is unverified: click Advanced › Continue.',
            'Klicke „Mit Google anmelden“. Google warnt vor einer nicht verifizierten App: Erweitert › Weiter.',
          ),
        ],
        note: _t(
          'In "Testing" Google signs you out every 7 days; publishing the app avoids that. The sign-in is stored '
              'encrypted with Windows.',
          'Im Status „Testen“ meldet Google dich alle 7 Tage ab; Veröffentlichen verhindert das. Die Anmeldung '
              'wird von Windows verschlüsselt gespeichert.',
        ),
        link: ('console.cloud.google.com', 'https://console.cloud.google.com/apis/credentials'),
      ),
      _Section(
        icon: Symbols.fast_forward_rounded,
        title: 'SponsorBlock',
        steps: [
          _t(
            'Community-marked sponsor spots, intros, reminders and more are shown on the timeline.',
            'Von der Community markierte Werbung, Intros, Erinnerungen und mehr erscheinen auf der Zeitleiste.',
          ),
          _t(
            'Per category choose Auto-skip, Button or Off in YouTube settings. Auto-skips can be undone.',
            'Pro Kategorie in den YouTube-Einstellungen Auto, Button oder Aus wählen. Auto-Sprünge lassen sich '
                'rückgängig machen.',
          ),
        ],
      ),
      _Section(
        icon: Symbols.keyboard_rounded,
        title: _t('Player shortcuts', 'Player-Tastenkürzel'),
        steps: [
          _t('Space or K: play / pause · click the video: play / pause',
              'Leertaste oder K: Play/Pause · Klick aufs Video: Play/Pause'),
          _t('J / L or ← / →: 10 seconds back / forward', 'J / L oder ← / →: 10 Sekunden zurück / vor'),
          _t('↑ / ↓: volume · M: mute', '↑ / ↓: Lautstärke · M: stumm'),
          _t('F or double-click: fullscreen · Esc: leave fullscreen / player',
              'F oder Doppelklick: Vollbild · Esc: Vollbild / Player verlassen'),
          _t('C: comments · N / Shift+N: next / previous video', 'C: Kommentare · N / Umschalt+N: nächstes / vorheriges Video'),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(YtStrings.guide)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final s in sections) _SectionCard(section: s)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section {
  const _Section({required this.icon, required this.title, required this.steps, this.intro, this.note, this.link});

  final IconData icon;
  final String title;
  final String? intro;
  final List<String> steps;
  final String? note;
  final (String, String)? link;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final _Section section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final accent = playerActiveColor(context);
    final link = section.link;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: mono.surface,
        borderRadius: BorderRadius.circular(mono.radiusLg),
        border: Border.all(color: mono.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(section.icon, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(section.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (section.intro != null) ...[
            const SizedBox(height: 10),
            Text(section.intro!, style: theme.textTheme.bodyMedium?.copyWith(color: mono.textMuted, height: 1.45)),
          ],
          const SizedBox(height: 12),
          for (var i = 0; i < section.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: accent)),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(section.steps[i], style: theme.textTheme.bodyMedium?.copyWith(height: 1.45))),
                ],
              ),
            ),
          if (section.note != null) ...[
            const SizedBox(height: 4),
            Text(section.note!, style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted, height: 1.4)),
          ],
          if (link != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => unawaited(launchUrl(Uri.parse(link.$2), mode: LaunchMode.externalApplication)),
              icon: const AppIcon(Symbols.open_in_new_rounded, size: 18),
              label: Text(link.$1),
            ),
          ],
        ],
      ),
    );
  }
}
