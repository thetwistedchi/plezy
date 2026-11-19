import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../services/retrowave/retrowave_updater.dart';
import 'simple_markdown.dart';

bool get _de => LocaleSettings.currentLocale == AppLocale.de;
String _t(String en, String de) => _de ? de : en;

bool _dialogOpen = false;

/// Release bodies start with the release's own title line, which the dialog
/// already shows.
String _withoutTitle(String notes) {
  final lines = notes.trim().split('\n');
  if (lines.isNotEmpty && lines.first.startsWith('## Plezy Retrowave')) lines.removeAt(0);
  return lines.join('\n').trim();
}

/// Shows [release] with its notes and offers to update right away. Does
/// nothing while an update dialog is already open.
Future<void> showRetrowaveUpdateDialog(BuildContext context, RetrowaveRelease release, {bool showSkip = true}) async {
  if (_dialogOpen) return;
  _dialogOpen = true;
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(release: release, showSkip: showSkip),
    );
  } finally {
    _dialogOpen = false;
  }
}

/// Once after an update: what this version brought.
Future<void> showRetrowaveWhatsNewDialog(BuildContext context, RetrowaveRelease release) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(_t("What's new in ${release.version}", 'Neu in ${release.version}')),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(child: SimpleMarkdown(_withoutTitle(release.notes))),
    ),
    actions: [
      FilledButton(autofocus: true, onPressed: () => Navigator.pop(context), child: Text(_t('Close', 'Schließen'))),
    ],
  ),
);

/// Manual check from Settings: says when there is nothing new or the check
/// failed, else opens the update dialog.
Future<void> checkForRetrowaveUpdate(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final release = await RetrowaveUpdater.check(manual: true);
    if (!context.mounted) return;
    if (release == null) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Plezy Retrowave ${RetrowaveUpdater.currentVersion} is the latest version.',
              'Plezy Retrowave ${RetrowaveUpdater.currentVersion} ist die neueste Version.',
            ),
          ),
        ),
      );
      return;
    }
    await showRetrowaveUpdateDialog(context, release, showSkip: false);
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(content: Text(_t('Could not check for updates.', 'Suche nach Updates nicht möglich.'))),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.release, required this.showSkip});

  final RetrowaveRelease release;
  final bool showSkip;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  double? _progress;
  String? _problem;

  String get _actionLabel => switch (RetrowaveUpdater.mode) {
    RetrowaveUpdateMode.windowsInstaller => _t('Update and restart', 'Aktualisieren und neu starten'),
    RetrowaveUpdateMode.androidApk => _t('Download and install', 'Herunterladen und installieren'),
    RetrowaveUpdateMode.releasePage => _t('Open download page', 'Downloadseite öffnen'),
  };

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _problem = null;
      _progress = null;
    });
    try {
      final result = await RetrowaveUpdater.install(
        widget.release,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      if (result == null) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        _busy = false;
        _problem = result == 'needsPermission'
            ? _t(
                'Allow installing apps from Plezy Retrowave in the settings that just opened, then press the button again.',
                'Im eben geöffneten Einstellungsfenster das Installieren von Apps durch Plezy Retrowave erlauben, dann erneut drücken.',
              )
            : _t(
                'This release has no file for this device. Use the download page instead.',
                'Dieses Release enthält keine Datei für dieses Gerät. Bitte die Downloadseite nutzen.',
              );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = _t('The update failed: $e', 'Das Update ist fehlgeschlagen: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final release = widget.release;
    return AlertDialog(
      title: Text(_t('Update available', 'Update verfügbar')),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(
                '${release.name} (installed: ${RetrowaveUpdater.currentVersion})',
                '${release.name} (installiert: ${RetrowaveUpdater.currentVersion})',
              ),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: SimpleMarkdown(release.notes.trim().isEmpty ? '–' : _withoutTitle(release.notes)),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
            ],
            if (_problem != null) ...[
              const SizedBox(height: 12),
              Text(_problem!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.showSkip)
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    unawaited(RetrowaveUpdater.skip(release.version));
                    Navigator.pop(context);
                  },
            child: Text(_t('Skip this version', 'Diese Version überspringen')),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(_t('Later', 'Später'))),
        FilledButton(autofocus: true, onPressed: _busy ? null : _update, child: Text(_actionLabel)),
      ],
    );
  }
}
