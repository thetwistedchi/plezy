import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      child: _ScrollableNotes(notes: _withoutTitle(release.notes), autofocus: true),
    ),
    actions: [
      FilledButton(onPressed: () => Navigator.pop(context), child: Text(_t('Close', 'Schließen'))),
    ],
  ),
);

String get retrowaveReleaseNotesTitle => _t('Release notes', 'Versionshinweise');
String get retrowaveReleaseNotesSubtitle => _t("What's new in this version", 'Neuerungen dieser Version');

/// From Settings: this version's notes again, after the dialog shown at the
/// first start following an update was closed.
Future<void> showRetrowaveReleaseNotes(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final release = await RetrowaveUpdater.currentRelease();
  if (!context.mounted) return;
  if (release == null) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(_t('Could not load the release notes.', 'Versionshinweise konnten nicht geladen werden.')),
      ),
    );
    return;
  }
  await showRetrowaveWhatsNewDialog(context, release);
}

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

/// Release notes that scroll with touch, mouse and the remote: the notes take
/// focus, Up/Down scroll them, and at the top or bottom the key moves on to
/// the buttons as usual.
class _ScrollableNotes extends StatefulWidget {
  const _ScrollableNotes({required this.notes, this.autofocus = false});

  final String notes;
  final bool autofocus;

  @override
  State<_ScrollableNotes> createState() => _ScrollableNotesState();
}

class _ScrollableNotesState extends State<_ScrollableNotes> {
  final _controller = ScrollController();
  bool _focused = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (!_controller.hasClients) return KeyEventResult.ignored;
    final position = _controller.position;
    final step = position.viewportDimension * 0.6;
    double? target;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && position.pixels < position.maxScrollExtent) {
      target = (position.pixels + step).clamp(0.0, position.maxScrollExtent);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp && position.pixels > position.minScrollExtent) {
      target = (position.pixels - step).clamp(0.0, position.maxScrollExtent);
    }
    if (target == null) return KeyEventResult.ignored;
    unawaited(_controller.animateTo(target, duration: const Duration(milliseconds: 160), curve: Curves.easeOut));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _focused ? scheme.primary : Colors.transparent, width: 2),
        ),
        child: Scrollbar(
          controller: _controller,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
            child: SimpleMarkdown(widget.notes),
          ),
        ),
      ),
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

class _UpdateDialogState extends State<_UpdateDialog> with WidgetsBindingObserver {
  bool _busy = false;
  double? _progress;
  String? _problem;

  /// Fork: waiting for the user to allow installs in Android's settings;
  /// coming back with it allowed continues the update by itself.
  bool _awaitingPermission = false;

  /// Fork: the APK was handed to Android's installer; the button now only
  /// opens that prompt again.
  bool _installerOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_awaitingPermission || _busy) return;
    unawaited(() async {
      if (!await RetrowaveUpdater.canInstallApks() || !mounted) return;
      _awaitingPermission = false;
      await _update();
    }());
  }

  String get _actionLabel => switch (RetrowaveUpdater.mode) {
    RetrowaveUpdateMode.windowsInstaller => _t('Update and restart', 'Aktualisieren und neu starten'),
    RetrowaveUpdateMode.androidApk =>
      _installerOpened ? _t('Install', 'Installieren') : _t('Download and install', 'Herunterladen und installieren'),
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
      if (result == 'installerOpened') {
        setState(() {
          _busy = false;
          _installerOpened = true;
          _problem = _t(
            "Android's install prompt should be open now. If it did not appear, press Install again; the download is not repeated.",
            'Die Installationsabfrage von Android sollte jetzt offen sein. Falls nicht, erneut auf Installieren drücken; es wird nicht noch einmal heruntergeladen.',
          );
        });
        return;
      }
      _awaitingPermission = result == 'needsPermission';
      setState(() {
        _busy = false;
        _problem = result == 'needsPermission'
            ? _t(
                'Allow installing apps from Plezy Retrowave in the settings that just opened. The update continues when you come back.',
                'Im eben geöffneten Einstellungsfenster das Installieren von Apps durch Plezy Retrowave erlauben. Das Update geht danach von selbst weiter.',
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
              child: _ScrollableNotes(notes: release.notes.trim().isEmpty ? '–' : _withoutTitle(release.notes)),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
            ],
            if (_problem != null) ...[
              const SizedBox(height: 12),
              Text(
                _problem!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _installerOpened ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.error,
                ),
              ),
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
