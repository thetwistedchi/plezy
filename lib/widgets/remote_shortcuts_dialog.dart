import 'package:flutter/material.dart';

import '../i18n/retro_strings.dart';
import '../utils/dialogs.dart';
import '../theme/mono_tokens.dart';

/// Fork: what the TV remote's buttons do (Settings, and the browser's ⋮ menu).
Future<void> showRemoteShortcuts(BuildContext context) => showScopedDialog<void>(
  context: context,
  builder: (context) {
    final t = tokens(context);
    final de = RetroStrings.isGerman;
    Widget section(String title, List<(String, String)> rows) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: t.accent, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final (key, action) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 190,
                    child: Text(key, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Expanded(child: Text(action, style: TextStyle(color: t.textMuted))),
                ],
              ),
            ),
        ],
      ),
    );
    return AlertDialog(
      title: Text(RetroStrings.remoteShortcuts),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: de
                ? [
                    section('Überall', [
                      ('Zurück', 'Zurück, schließt offene Menüs zuerst'),
                      ('Zurück 1,5 s halten', 'Direkt zur Startseite'),
                    ]),
                    section('Browser', [
                      ('Pfeiltasten', 'Links, Schaltflächen und Felder der Seite wählen'),
                      ('OK', 'Öffnen bzw. klicken'),
                      ('OK gedrückt halten', 'Zeiger für diese Website an/aus'),
                      ('Runter in der Leiste', 'In die Seite'),
                      ('Hoch oben auf der Seite', 'Zur Leiste'),
                      ('Hoch dreimal schnell', 'Direkt in die Adressleiste'),
                      ('Rechts auf einem Tab', 'Dessen Schließen-Knopf'),
                      ('Zeiger an: Pfeiltasten', 'Zeiger bewegen, halten für schneller, am Rand scrollen'),
                      ('Play/Pause, ⏩, ⏪', 'Video der Seite steuern'),
                      ('Im Video-Vollbild', 'OK pausiert, Links/Rechts springen 10 s'),
                      ('Zurück', 'Vollbild verlassen, dann eine Seite zurück'),
                    ]),
                    section('Handy als Fernbedienung', [
                      ('Handy-Knopf in der Leiste', 'QR-Code zum Scannen'),
                      ('Touchpad', 'Zeiger bewegen, tippen klickt, zwei Finger scrollen'),
                      ('Leiste rechts am Touchpad', 'Scrollen wie mit einer Bildlaufleiste'),
                    ]),
                    section('Kostenlos auf plex.tv', [
                      ('Play/Pause', 'Pausieren und weiter'),
                      ('Zurück', 'Wiedergabe schließen'),
                    ]),
                  ]
                : [
                    section('Everywhere', [
                      ('Back', 'Back, closes open menus first'),
                      ('Hold Back for 1.5 s', 'Straight to Home'),
                    ]),
                    section('Browser', [
                      ('Arrows', "Select the page's links, buttons and fields"),
                      ('OK', 'Open or click'),
                      ('Hold OK', 'Pointer on/off for this website'),
                      ('Down in the toolbar', 'Into the page'),
                      ('Up at the top of a page', 'To the toolbar'),
                      ('Up three times quickly', 'Straight to the address bar'),
                      ('Right on a tab', 'Its close button'),
                      ('Pointer on: arrows', 'Move the pointer, hold for faster, scroll at the edges'),
                      ('Play/Pause, ⏩, ⏪', "Control the page's video"),
                      ("In a video's fullscreen", 'OK pauses, Left/Right jump 10 s'),
                      ('Back', 'Leave fullscreen, then go back a page'),
                    ]),
                    section('Phone as remote', [
                      ('Phone button in the toolbar', 'QR code to scan'),
                      ('Touchpad', 'Move the pointer, tap to click, two fingers scroll'),
                      ('Bar on the right of the touchpad', 'Scroll like a scroll bar'),
                    ]),
                    section('Free on plex.tv', [
                      ('Play/Pause', 'Pause and resume'),
                      ('Back', 'Close playback'),
                    ]),
                  ],
          ),
        ),
      ),
      actions: [
        FilledButton(autofocus: true, onPressed: () => Navigator.pop(context), child: Text(RetroStrings.close)),
      ],
    );
  },
);
