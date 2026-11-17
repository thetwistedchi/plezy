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
  static String get watchlist => _t('Watchlist', 'Merkliste');
  static String watchlistCount(int n) => n == 0 ? watchlist : '$watchlist ($n)';
  static String get addToWatchlist => _t('Add to watchlist', 'Zur Merkliste hinzufügen');
  static String get removeFromWatchlist => _t('Remove from watchlist', 'Von der Merkliste entfernen');
  static String get playAll => _t('Play all', 'Alle abspielen');
  static String get clearWatchlist => _t('Clear', 'Leeren');
  static String get watchlistEmpty => _t(
    'Your watchlist is empty. Use the + on a video to add it.',
    'Deine Merkliste ist leer. Füge Videos mit dem + hinzu.',
  );
  static String get watchlistSubtitle =>
      _t('Plays in this order. Drag to reorder.', 'Wird in dieser Reihenfolge abgespielt. Zum Sortieren ziehen.');
  static String get dismiss => _t('Dismiss', 'Ausblenden');
  static String get dragToReorder => _t('Drag to reorder', 'Zum Sortieren ziehen');
  // Player
  static String get back => _t('Back', 'Zurück');
  static String get play => _t('Play', 'Abspielen');
  static String get pause => _t('Pause', 'Pause');
  static String get back10 => _t('Back 10 seconds', '10 Sekunden zurück');
  static String get forward10 => _t('Forward 10 seconds', '10 Sekunden vor');
  static String get previous => _t('Previous video', 'Vorheriges Video');
  static String get next => _t('Next video', 'Nächstes Video');
  static String get jumpToHighlight => _t('Jump to highlight', 'Zum Highlight springen');
  static String get mute => _t('Mute', 'Stumm');
  static String get unmute => _t('Unmute', 'Ton an');
  static String get captions => _t('Captions', 'Untertitel');
  static String get speed => _t('Playback speed', 'Geschwindigkeit');
  static String get chapters => _t('Chapters', 'Kapitel');
  static String get comments => _t('Comments', 'Kommentare');
  static String get fullscreen => _t('Fullscreen', 'Vollbild');
  static String get exitFullscreen => _t('Exit fullscreen', 'Vollbild beenden');
  static String get openOnYouTube => _t('Open on YouTube', 'Auf YouTube öffnen');
  static String get like => _t('Like', 'Mag ich');
  static String get dislike => _t('Dislike', 'Mag ich nicht');
  static String get needWriteAccess => _t(
    'Sign in again in the YouTube settings to allow rating and comments.',
    'Melde dich in den YouTube-Einstellungen neu an, um Bewertungen und Kommentare zu erlauben.',
  );
  static String get ratingFailed => _t('Could not save the rating.', 'Bewertung konnte nicht gespeichert werden.');
  static String queuePosition(int i, int n) => '$i / $n';
  static String upNext(String title) => _t('Up next: $title', 'Als Nächstes: $title');
  static String get playerLoading => _t('Loading player…', 'Player wird geladen…');
  static String get playerFailed => _t('The player could not start.', 'Der Player konnte nicht starten.');
  static String get webviewMissing => _t(
    'The Microsoft Edge WebView2 runtime is needed for the in-app player.',
    'Für den Player in der App wird die Microsoft Edge WebView2-Laufzeit benötigt.',
  );
  static String get embedBlocked => _t(
    'The creator doesn\'t allow this video to be played outside YouTube.',
    'Der Ersteller erlaubt dieses Video nicht außerhalb von YouTube.',
  );
  static String get videoUnavailable => _t('This video is unavailable.', 'Dieses Video ist nicht verfügbar.');
  static String skipCategory(String c) => _t('SKIP ${sbLabelEn(c).toUpperCase()} ›', '${sbLabelDe(c).toUpperCase()} ÜBERSPRINGEN ›');
  static String skipped(String c) => _t('Skipped ${sbLabelEn(c).toLowerCase()}', '${sbLabelDe(c)} übersprungen');
  static String get undo => _t('Undo', 'Rückgängig');
  static String get normalSpeed => _t('Normal', 'Normal');

  // SponsorBlock
  static String get sponsorBlock => 'SponsorBlock';
  static String get useSponsorBlock => _t('Use SponsorBlock', 'SponsorBlock verwenden');
  static String get useSponsorBlockSub =>
      _t('Community-marked segments in creator videos', 'Von der Community markierte Abschnitte');
  static String get showSegments => _t('Show segments on the timeline', 'Abschnitte auf der Zeitleiste zeigen');
  static String get showSegmentsSub =>
      _t('Plus a star button that jumps to the highlight', 'Dazu ein Stern-Button, der zum Highlight springt');
  static String get modeAuto => _t('Auto-skip', 'Auto');
  static String get modeButton => _t('Button', 'Button');
  static String get modeOff => _t('Off', 'Aus');
  static String get sbCredit => _t(
    'Segment data from SponsorBlock (sponsor.ajay.app), used under CC BY-NC-SA 4.0.',
    'Segmentdaten von SponsorBlock (sponsor.ajay.app), genutzt unter CC BY-NC-SA 4.0.',
  );
  static String sbLabel(String c) => _t(sbLabelEn(c), sbLabelDe(c));
  static String sbLabelEn(String c) => switch (c) {
    'sponsor' => 'Sponsor',
    'selfpromo' => 'Self-promotion',
    'interaction' => 'Interaction reminder',
    'intro' => 'Intro',
    'outro' => 'Outro',
    'preview' => 'Recap',
    'filler' => 'Filler',
    'music_offtopic' => 'Non-music part',
    _ => c,
  };
  static String sbLabelDe(String c) => switch (c) {
    'sponsor' => 'Sponsor',
    'selfpromo' => 'Eigenwerbung',
    'interaction' => 'Interaktions-Erinnerung',
    'intro' => 'Intro',
    'outro' => 'Outro',
    'preview' => 'Rückblick',
    'filler' => 'Füller',
    'music_offtopic' => 'Nicht-Musik-Teil',
    _ => c,
  };
  static String sbDescription(String c) => switch (c) {
    'sponsor' => _t('Paid promotion or product placement', 'Bezahlte Werbung oder Produktplatzierung'),
    'selfpromo' => _t('Merch, Patreon, the creator\'s own products', 'Merch, Patreon, eigene Produkte'),
    'interaction' => _t('"Like and subscribe" reminders', '„Liken und abonnieren“-Erinnerungen'),
    'intro' => _t('Intro animation or recurring opener', 'Intro-Animation oder wiederkehrender Einstieg'),
    'outro' => _t('End cards and credits', 'Endkarten und Abspann'),
    'preview' => _t('Recap or preview of other episodes', 'Rückblick oder Vorschau'),
    'filler' => _t('Tangents and jokes off the topic', 'Abschweifungen und Witze abseits des Themas'),
    'music_offtopic' => _t('Talking in music videos', 'Gerede in Musikvideos'),
    _ => '',
  };

  // Premium / web sign-in
  static String get playerAccount => _t('Player sign-in (YouTube Premium)', 'Player-Anmeldung (YouTube Premium)');
  static String get playerAccountSub => _t(
    'Sign in to YouTube inside the app so the player uses your Premium (no ads).',
    'Melde dich in der App bei YouTube an, damit der Player dein Premium nutzt (ohne Werbung).',
  );
  static String get signInPlayer => _t('Sign in to YouTube', 'Bei YouTube anmelden');
  static String get signOutPlayer => _t('Sign out of the player', 'Vom Player abmelden');
  static String get playerCache => _t('Player cache', 'Player-Cache');
  static String playerCacheSub(String size) =>
      _t('$size used · clearing keeps you signed in', '$size belegt · Leeren hält dich angemeldet');
  static String get cacheLimit => _t('Cache limit', 'Cache-Limit');
  static String get cacheLimitSub => _t(
    'Takes effect after restarting the app',
    'Gilt nach einem Neustart der App',
  );
  static String get clearPlayerCache => _t('Clear player cache', 'Player-Cache leeren');
  static String get cacheCleared => _t('Player cache cleared.', 'Player-Cache geleert.');
  static String fileSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
  static String get done => _t('Done', 'Fertig');
  static String get writeAccessMissing => _t(
    'This sign-in can only read. Sign out and in again to allow rating and comments.',
    'Diese Anmeldung kann nur lesen. Melde dich ab und neu an, um Bewertungen und Kommentare zu erlauben.',
  );

  // Comments
  static String commentsCount(int? n) => n == null ? comments : '$comments  $n';
  static String get sortTop => _t('Top comments', 'Top-Kommentare');
  static String get sortNewest => _t('Newest first', 'Neueste zuerst');
  static String get close => _t('Close', 'Schließen');
  static String replies(int n) => n == 1 ? _t('1 reply', '1 Antwort') : _t('$n replies', '$n Antworten');
  static String get hideReplies => _t('Hide replies', 'Antworten ausblenden');
  static String get reply => _t('Reply', 'Antworten');
  static String get addComment => _t('Add a comment…', 'Kommentar hinzufügen…');
  static String get addReply => _t('Add a reply…', 'Antwort hinzufügen…');
  static String get send => _t('Send', 'Senden');
  static String get cancel => _t('Cancel', 'Abbrechen');
  static String get edit => _t('Edit', 'Bearbeiten');
  static String get delete => _t('Delete', 'Löschen');
  static String get edited => _t('(edited)', '(bearbeitet)');
  static String get commentsDisabled =>
      _t('Comments are turned off for this video.', 'Kommentare sind für dieses Video deaktiviert.');
  static String get noComments => _t('No comments yet.', 'Noch keine Kommentare.');
  static String get commentFailed => _t('Could not post the comment.', 'Kommentar konnte nicht gesendet werden.');
  static String get loadMore => _t('Load more', 'Mehr laden');

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
