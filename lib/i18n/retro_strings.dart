import 'strings.g.dart';

/// Texts for the fork's 0.8 additions, English and German. Kept out of the
/// slang files so the fork stays easy to rebase onto upstream Plezy.
class RetroStrings {
  RetroStrings._();

  static bool get _de => LocaleSettings.currentLocale == AppLocale.de;
  static String _t(String en, String de) => _de ? de : en;

  // Home rows
  static String get hideWatched => _t('Hide watched', 'Gesehenes ausblenden');
  static String get showWatched => _t('Show watched', 'Gesehenes anzeigen');
  static String get hideWatchedInRow => _t('Hide watched in this row', 'Gesehenes in dieser Reihe ausblenden');
  static String get showWatchedInRow => _t('Show watched in this row', 'Gesehenes in dieser Reihe anzeigen');

  // Startup
  static String get startupLibrary => _t('Startup library', 'Mediathek beim Start');
  static String get lastUsedLibrary => _t('Last used', 'Zuletzt genutzt');

  // Hover preview
  static String get hoverPreview => _t('Poster preview on hover', 'Poster-Vorschau beim Darüberfahren');
  static String get hoverPreviewDescription => _t(
    'Shows plot, runtime and genres after resting the mouse on a poster',
    'Zeigt Handlung, Laufzeit und Genres, wenn die Maus kurz auf einem Poster ruht',
  );

  static String get hoverPreviewDelay => _t('Hover preview delay', 'Verzögerung der Vorschau');
  static String delayLabel(int ms) {
    final seconds = (ms / 1000).toStringAsFixed(ms % 1000 == 0 ? 0 : (ms % 100 == 0 ? 1 : 2));
    return _de ? '${seconds.replaceAll('.', ',')} s' : '$seconds s';
  }

  // Details page
  static String get playFromStart => _t('Play from start', 'Von vorne abspielen');
  static String resumeAt(String time) => _t('Resume at $time', 'Fortsetzen bei $time');
  static String get trailer => 'Trailer';
  static String get noTrailer => _t('No trailer found', 'Kein Trailer gefunden');
  static String allScores(int median) => _t('All scores · median $median', 'Alle Wertungen · Median $median');
  static String get similarInLibrary => _t('Similar in your library', 'Ähnliches in deiner Mediathek');

  // Per-title memory
  static String get rememberTracks => _t('Remember tracks per title', 'Spuren pro Titel merken');
  static String get rememberTracksDescription => _t(
    'Reuses the audio and subtitle track and the zoom mode last chosen for a movie or series',
    'Nutzt die zuletzt gewählte Audio- und Untertitelspur und den Zoom eines Films oder einer Serie wieder',
  );

  // Shortcuts overlay
  static String get shortcuts => _t('Keyboard shortcuts', 'Tastenkürzel');
  static String get shortcutsHint => _t('Press ? anywhere to show this list', 'Drücke überall ?, um diese Liste zu zeigen');
  static String get general => _t('General', 'Allgemein');
  static String get player => _t('Player', 'Player');
  static String get close => _t('Close', 'Schließen');
  static String get moveFocus => _t('Move between items', 'Zwischen Einträgen wechseln');
  static String get openSelect => _t('Open or select', 'Öffnen oder auswählen');
  static String get goBack => _t('Back', 'Zurück');
}
