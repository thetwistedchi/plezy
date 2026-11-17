import '../../i18n/strings.g.dart';

/// Texts for the fork's YouTube screens, English and German. Kept here rather
/// than in the slang files so the fork's additions stay easy to rebase onto
/// upstream Plezy.
class YtStrings {
  YtStrings._();

  static bool get _de => LocaleSettings.currentLocale == AppLocale.de;
  static String _t(String en, String de) => _de ? de : en;

  static String get tab => 'YouTube';
  static String get subscriptions => _t('Subscriptions', 'Abos');
  static String get newestSubtitle =>
      _t('Newest uploads from the channels you follow', 'Neueste Videos der Kanäle, denen du folgst');
  static String get relevantSubtitle => _t(
    'Ranked by channels you watch, trending views and freshness',
    'Sortiert nach deinen Lieblingskanälen, Trend und Aktualität',
  );
  static String updatedAgo(String age) => _t('updated $age', 'aktualisiert $age');
  static String get newest => _t('Newest', 'Neueste');
  static String get mostRelevant => _t('Most relevant', 'Relevanteste');
  static String get all => _t('All', 'Alle');
  static String get unwatched => _t('Unwatched', 'Ungesehen');
  static String get refresh => _t('Refresh', 'Aktualisieren');
  static String get settings => _t('YouTube settings', 'YouTube-Einstellungen');
  static String get hiddenBanner =>
      _t('Shorts and premieres are hidden.', 'Shorts und Premieren sind ausgeblendet.');
  static String get shortsHiddenBanner => _t('Shorts are hidden.', 'Shorts sind ausgeblendet.');
  static String get premieresHiddenBanner => _t('Premieres are hidden.', 'Premieren sind ausgeblendet.');
  static String get changeInSettings => _t('Change in settings', 'In den Einstellungen ändern');
  static String get watched => _t('Watched', 'Gesehen');
  static String get live => 'LIVE';
  static String get upcoming => _t('UPCOMING', 'DEMNÄCHST');
  static String trending(String factor) =>
      _t('Trending · $factor× this channel\'s usual views', 'Im Trend · $factor× so viele Aufrufe wie sonst');
  static String get favoriteChannel => _t('You watch this channel often', 'Diesen Kanal schaust du oft');
  static String get empty => _t('No videos to show.', 'Keine Videos zum Anzeigen.');
  static String loadingChannels(int done, int total) =>
      _t('Loading channels $done / $total…', 'Kanäle werden geladen: $done / $total…');
  static String get loading => _t('Loading your subscriptions…', 'Abos werden geladen…');
  static String get errorTitle => _t('Could not load YouTube', 'YouTube konnte nicht geladen werden');
  static String get retry => _t('Try again', 'Erneut versuchen');

  static String get connectTitle => _t('Connect YouTube', 'YouTube verbinden');
  static String get connectBody => _t(
    'Sign in with your Google account to see the newest videos of your subscriptions here.',
    'Melde dich mit deinem Google-Konto an, um hier die neuesten Videos deiner Abos zu sehen.',
  );
  static String get openSettings => _t('Set up YouTube', 'YouTube einrichten');

  static String get account => _t('Account', 'Konto');
  static String get oauthClient => _t('Google OAuth client', 'Google-OAuth-Client');
  static String get oauthHelp => _t(
    'Create a free project at console.cloud.google.com, enable "YouTube Data API v3", '
        'then create an OAuth client of type "Desktop app" and paste its ID and secret here. '
        'Add your Google account as a test user on the OAuth consent screen.',
    'Lege auf console.cloud.google.com ein kostenloses Projekt an, aktiviere "YouTube Data API v3", '
        'erstelle dann einen OAuth-Client vom Typ "Desktop-App" und füge ID und Secret hier ein. '
        'Trage dein Google-Konto im OAuth-Zustimmungsbildschirm als Testnutzer ein.',
  );
  static String get openConsole => _t('Open Google Cloud Console', 'Google Cloud Console öffnen');
  static String get clientId => 'Client ID';
  static String get clientSecret => 'Client secret';
  static String get save => _t('Save', 'Speichern');
  static String get signIn => _t('Sign in with Google', 'Mit Google anmelden');
  static String get signOut => _t('Sign out', 'Abmelden');
  static String get signingIn =>
      _t('Finish the sign-in in your browser…', 'Schließe die Anmeldung im Browser ab…');
  static String get notSignedIn => _t('Not signed in', 'Nicht angemeldet');
  static String signedInAs(String name) => _t('Signed in as $name', 'Angemeldet als $name');
  static String get signedIn => _t('Signed in', 'Angemeldet');
  static String get readOnly => _t('Read-only access to your subscriptions', 'Nur Lesezugriff auf deine Abos');
  static String get needClientId => _t('Enter the client ID first.', 'Gib zuerst die Client ID ein.');

  static String get library => _t('Library', 'Mediathek');
  static String get showShorts => _t('Show Shorts', 'Shorts anzeigen');
  static String get showPremieres => _t('Show premieres and upcoming', 'Premieren und Geplantes anzeigen');
  static String get hiddenByDefault => _t('Hidden by default', 'Standardmäßig ausgeblendet');
  static String get refreshEvery => _t('Refresh every', 'Aktualisieren alle');
  static String minutes(int m) => m >= 60 ? _t('${m ~/ 60} hour', '${m ~/ 60} Stunde') : _t('$m minutes', '$m Minuten');

  static String age(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.isNegative) return _t('soon', 'bald');
    if (diff.inMinutes < 1) return _t('just now', 'gerade eben');
    if (diff.inHours < 1) return _t('${diff.inMinutes} min ago', 'vor ${diff.inMinutes} Min.');
    if (diff.inDays < 1) return _t('${diff.inHours} h ago', 'vor ${diff.inHours} Std.');
    if (diff.inDays == 1) return _t('yesterday', 'gestern');
    if (diff.inDays < 30) return _t('${diff.inDays} days ago', 'vor ${diff.inDays} Tagen');
    final months = diff.inDays ~/ 30;
    if (months < 12) return _t('$months months ago', 'vor $months Monaten');
    return _t('${diff.inDays ~/ 365} years ago', 'vor ${diff.inDays ~/ 365} Jahren');
  }

  static String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
