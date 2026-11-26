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
  static String get search => _t('Search YouTube', 'YouTube durchsuchen');
  static String get latestPerChannel => _t('Latest per channel', 'Neuestes pro Kanal');
  static String get latestPerChannelHint =>
      _t('Each channel once, with its newest video', 'Jeder Kanal einmal, mit seinem neuesten Video');
  static String searchResults(String q) => _t('Results for "$q"', 'Ergebnisse für „$q“');
  static String get searching => _t('Searching…', 'Suche läuft…');
  static String get noResults => _t('No videos found.', 'Keine Videos gefunden.');
  static String get clearSearch => _t('Clear search', 'Suche löschen');
  static String get searchSubtitle => _t('Public YouTube search', 'Öffentliche YouTube-Suche');
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
  static String get inWatchlist => _t('In the watchlist', 'Auf der Merkliste');
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
  static String get miniPlayer => _t('Mini player', 'Mini-Player');
  static String get posterInfoPills => _t('Quality and languages under posters', 'Qualität und Sprachen unter Postern');
  static String get posterInfoPillsDescription => _t(
    'Small pills with resolution, HDR and audio languages below each poster.',
    'Kleine Pillen mit Auflösung, HDR und Tonsprachen unter jedem Poster.',
  );
  static String get resumeWatching => _t('Continue where you left off', 'Weiterschauen, wo du aufgehört hast');
  static String resumeAt(String time) => _t('Resume at $time', 'Bei $time fortsetzen');
  static String get fitHeight => _t('Fit height (nothing cut at top or bottom)', 'Höhe füllen (oben und unten nichts abgeschnitten)');
  static String get hdrBrightness => _t('HDR brightness boost', 'HDR-Helligkeitsboost');
  static String get hdrBrightnessOff => _t('Off · as mastered', 'Aus · wie gemastert');
  static String get hdrBoostShort => _t('Extra lift for dark HDR. Off = as mastered; HDR stays on.', 'Extra-Aufhellung für dunkles HDR. Aus = wie gemastert; HDR bleibt an.');
  static String get hdrBrightnessDescription => _t(
    'An extra lift for HDR videos that look too dark. Off keeps the full HDR picture exactly as mastered; higher values brighten the midtones on top of it. HDR stays on at every setting. Changes apply right away.',
    'Zusätzliche Aufhellung für HDR-Videos, die zu dunkel wirken. Aus zeigt das volle HDR-Bild genau wie gemastert; höhere Werte hellen die Mitteltöne zusätzlich auf. HDR bleibt bei jeder Einstellung aktiv. Änderungen wirken sofort.',
  );
  static String get cropLetterbox => _t('Fill the screen when letterboxed', 'Bildschirm bei Letterbox füllen');
  static String get cropLetterboxDescription => _t(
    'Detects black bars baked into a video and crops them, so wide films fill ultrawide screens. The aspect ratio is always kept. Applies to newly started videos.',
    'Erkennt schwarze Balken im Video und schneidet sie ab, damit Breitbildfilme Ultrawide-Bildschirme füllen. Das Seitenverhältnis bleibt immer erhalten. Gilt für neu gestartete Videos.',
  );
  static String get backMinimizes => _t('Back opens the mini player', 'Zurück öffnet den Mini-Player');
  static String get backMinimizesDescription => _t(
    'Back in the Plex or YouTube player keeps the video playing in the bar at the bottom. Off: Back closes the player.',
    'Zurück im Plex- oder YouTube-Player spielt das Video in der Leiste unten weiter. Aus: Zurück schließt den Player.',
  );
  static String get openPlayer => _t('Open player', 'Player öffnen');
  static String get stop => _t('Stop', 'Stopp');
  static String get stopAndClose => _t('Stop and close', 'Stoppen und schließen');
  static String get nextItem => _t('Next', 'Weiter');
  static String get back10s => _t('Back 10 s', '10 s zurück');
  static String get forward30s => _t('Forward 30 s', '30 s vor');
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
  static String get likeComment => _t('Like', 'Mag ich');
  static String get unlikeComment => _t('Remove like', '„Mag ich“ entfernen');
  static String get likeNeedsChannel => _t(
    'YouTube asks to create a channel first: the account selected on youtube.com in the app has none. Open "Sign in for the player" in the YouTube settings and switch to your channel there (profile picture > Switch account).',
    'YouTube verlangt zuerst einen Kanal: Das in der App auf youtube.com gewählte Konto hat keinen. Unter „Für den Player anmelden" in den YouTube-Einstellungen zum Kanal wechseln (Profilbild > Konto wechseln).',
  );
  static String get likeFailed => _t('The like could not be placed.', 'Das „Mag ich“ konnte nicht gesetzt werden.');
  static String get description => _t('Description', 'Beschreibung');
  static String get noDescription => _t('No description.', 'Keine Beschreibung.');
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
  static String get quality => _t('Quality', 'Qualität');
  static String get qualityAuto => 'Auto';
  static String qualityLabel(String q) => switch (q) {
    'highres' => '4320p (8K)',
    'hd2880' => '2880p (5K)',
    'hd2160' => '2160p (4K)',
    'hd1440' => '1440p',
    'hd1080' => '1080p',
    'hd720' => '720p',
    'large' => '480p',
    'medium' => '360p',
    'small' => '240p',
    'tiny' => '144p',
    'auto' => qualityAuto,
    _ => q,
  };
  static String qualityShort(String q) => switch (q) {
    'highres' => '8K',
    'hd2880' => '5K',
    'hd2160' => '4K',
    'hd1440' => '1440p',
    'hd1080' => '1080p',
    'hd720' => '720p',
    'large' => '480p',
    'medium' => '360p',
    'small' => '240p',
    'tiny' => '144p',
    _ => '',
  };
  static String get moreFromChannel => _t('More from this channel', 'Mehr von diesem Kanal');
  static String moreFrom(String channel) => _t('More from $channel', 'Mehr von $channel');
  static String get openChannel => _t('Open channel', 'Kanal öffnen');
  static String get channelEmpty => _t('No videos found.', 'Keine Videos gefunden.');
  static String subscribers(int n) => _t('${compact(n)} subscribers', '${compact(n)} Abonnenten');
  static String videoCount(int n) => _t('$n videos', '$n Videos');
  static String views(int n) => _t('${compact(n)} views', '${compact(n)} Aufrufe');
  static String get nowPlaying => _t('Now playing', 'Läuft gerade');
  static String compact(int n) {
    if (n >= 1000000000) return '${(n / 1000000000).toStringAsFixed(1)}B';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
    return '$n';
  }
  static String get defaultSpeed => _t('Playback speed', 'Wiedergabegeschwindigkeit');
  static String get defaultSpeedSub =>
      _t('Also changes when you pick a speed in the player', 'Ändert sich auch, wenn du im Player eine wählst');
  static String speedLabel(double s) => s == 1 ? normalSpeed : '${s == s.roundToDouble() ? s.toStringAsFixed(0) : s}×';
  static String get queue => _t('Playing order', 'Reihenfolge');
  static String get addVideos => _t('Add videos', 'Videos hinzufügen');
  static String get addFromSubscriptions =>
      _t('Newest from your subscriptions', 'Neueste aus deinen Abos');
  static String get addToQueue => _t('Add to watchlist and queue', 'Zur Merkliste und Warteschlange');
  static String get inQueue => _t('In the queue', 'In der Warteschlange');
  static String get removeFromQueue => _t('Remove from queue', 'Aus der Warteschlange entfernen');
  static String get noFeedVideos => _t('No new videos in your subscriptions.', 'Keine neuen Videos in deinen Abos.');
  static String get captionsOff => _t('Off', 'Aus');
  static String get autoGenerated => _t('auto-generated', 'automatisch erstellt');
  static String get autoTranslate => _t('Auto-translate', 'Automatisch übersetzen');
  static String get audioLanguage => _t('Audio language', 'Audiosprache');
  static String get captionsAndAudio => _t('Captions and audio', 'Untertitel und Audio');
  static String get showCaptions => _t('Show captions', 'Untertitel anzeigen');
  static String get showCaptionsSub =>
      _t('Turned on automatically when the language is available', 'Automatisch an, wenn die Sprache verfügbar ist');
  static String get captionsLanguage => _t('Captions language', 'Untertitelsprache');
  static String get allowAutoCaptions => _t('Use auto-generated captions', 'Automatisch erstellte Untertitel nutzen');
  static String get allowAutoCaptionsSub =>
      _t('When the creator didn\'t add captions in that language', 'Wenn der Ersteller keine in dieser Sprache hat');
  static String get translateCaptions => _t('Auto-translate as a fallback', 'Automatisch übersetzen als Notlösung');
  static String get translateCaptionsSub =>
      _t('Translates other captions into your language', 'Übersetzt andere Untertitel in deine Sprache');
  static String get audioPreference => _t('Audio track', 'Tonspur');
  static String get audioPreferenceSub => _t(
    'Videos with several audio tracks (often AI dubs) start with this one',
    'Videos mit mehreren Tonspuren (oft KI-Synchronisationen) starten mit dieser',
  );
  static String get audioOriginal => _t('Original (no dubbing)', 'Original (keine Synchronisation)');
  static String get share => _t('Share', 'Teilen');
  static String get copyLink => _t('Copy link', 'Link kopieren');
  static String copyLinkAt(String time) => _t('Copy link at $time', 'Link bei $time kopieren');
  static String get linkCopied => _t('Link copied.', 'Link kopiert.');
  static String get continueWatching => _t('Continue', 'Weiterschauen');
  static String get notInterested => _t('Not interested (hide video)', 'Kein Interesse (Video ausblenden)');
  static String muteChannel(String c) => _t('Hide all videos from $c', 'Alle Videos von $c ausblenden');
  static String get favoriteChannelAction =>
      _t('Favourite channel (notify on new videos)', 'Lieblingskanal (bei neuen Videos benachrichtigen)');
  static String get unfavoriteChannel => _t('Remove from favourites', 'Aus Lieblingskanälen entfernen');
  static String get hiddenAndMuted => _t('Hidden and favourites', 'Ausgeblendet und Favoriten');
  static String hiddenVideos(int n) => _t('$n hidden videos', '$n ausgeblendete Videos');
  static String get showHiddenAgain => _t('Show again', 'Wieder zeigen');
  static String get mutedChannels => _t('Hidden channels', 'Ausgeblendete Kanäle');
  static String get favoriteChannels => _t('Favourite channels', 'Lieblingskanäle');
  static String get notifyFavorites => _t('Notify about new videos', 'Bei neuen Videos benachrichtigen');
  static String get notifyFavoritesSub => _t(
    'Windows notification when a favourite channel uploads (while the app is running)',
    'Windows-Benachrichtigung, wenn ein Lieblingskanal hochlädt (solange die App läuft)',
  );
  static String get noneYet => _t('None yet. Right-click a video to add.', 'Noch keine. Rechtsklick auf ein Video.');
  static String get communityFeatures => _t('Community features', 'Community-Funktionen');
  static String get deArrowTitles => _t('DeArrow: better titles', 'DeArrow: bessere Titel');
  static String get deArrowThumbs => _t('DeArrow: better thumbnails', 'DeArrow: bessere Vorschaubilder');
  static String get deArrowSub =>
      _t('Community replacements for clickbait (dearrow.ajay.app)', 'Community-Ersatz für Clickbait (dearrow.ajay.app)');
  static String get returnDislikes => _t('Return YouTube Dislike', 'Return YouTube Dislike');
  static String get returnDislikesSub =>
      _t('Estimated dislike counts (returnyoutubedislike.com)', 'Geschätzte Dislikes (returnyoutubedislike.com)');
  static String get historySync => _t('Add watched videos to my YouTube history', 'Gesehene Videos zu meinem YouTube-Verlauf hinzufügen');
  static String get historySyncSub => _t(
    'YouTube does not record videos played here. With this on, after each video you watched for at least 30 seconds the app opens its YouTube page in the background with the signed-in player account, muted at the point where you stopped, for about 15 seconds. That adds it to your history and shows your progress on youtube.com. It uses a few MB of data per video, counts as one more view, may load an ad without YouTube Premium, and is not an official YouTube feature, so it can stop working when YouTube changes its pages. When switched on, the videos watched in the app before are added too, one after another in the background while the app runs (about 15 seconds and a few MB each). Needs "Sign in for the player".',
    'YouTube zeichnet hier abgespielte Videos nicht auf. Ist dies an, öffnet die App nach jedem Video, das du mindestens 30 Sekunden geschaut hast, dessen YouTube-Seite im Hintergrund mit dem angemeldeten Player-Konto, stumm an der Stelle, an der du aufgehört hast, für etwa 15 Sekunden. So landet es in deinem Verlauf und dein Fortschritt erscheint auf youtube.com. Das braucht ein paar MB Daten pro Video, zählt als ein weiterer Aufruf, kann ohne YouTube Premium Werbung laden und ist keine offizielle YouTube-Funktion, kann also aufhören zu funktionieren, wenn YouTube seine Seiten ändert. Beim Einschalten werden auch die zuvor in der App geschauten Videos hinzugefügt, nacheinander im Hintergrund, solange die App läuft (etwa 15 Sekunden und ein paar MB pro Video). Setzt „Für den Player anmelden" voraus.',
  );
  static String get historySyncNow => _t('Sync watched videos now', 'Geschaute Videos jetzt abgleichen');
  static String historySyncNowSub(int n) => n == 0
      ? _t('Everything watched here is in the YouTube history.', 'Alles hier Geschaute ist im YouTube-Verlauf.')
      : _t('$n videos are not in the YouTube history yet.', '$n Videos sind noch nicht im YouTube-Verlauf.');
  static String historySyncStarted(int n) =>
      _t('Adding $n videos to the YouTube history in the background…', '$n Videos werden im Hintergrund zum YouTube-Verlauf hinzugefügt…');
  static String get sleepTimer => _t('Sleep timer', 'Sleep-Timer');
  static String get sleepOff => _t('Off', 'Aus');
  static String sleepMinutes(int m) => _t('$m minutes', '$m Minuten');
  static String get sleepEndOfVideo => _t('End of this video', 'Ende dieses Videos');
  static String sleepActive(String left) => _t('Pauses in $left', 'Pausiert in $left');
  static String get sleepActiveEnd => _t('Stops after this video', 'Stoppt nach diesem Video');
  static String get sleepDone => _t('Sleep timer: paused.', 'Sleep-Timer: pausiert.');
  static String get playerButtons => _t('Player buttons', 'Player-Buttons');
  static String get showChannelStrip =>
      _t('"More from this channel" row when paused', '„Mehr von diesem Kanal“-Leiste bei Pause');
  static String get moreOptions => _t('More options', 'Weitere Optionen');
  static String buttonLabel(String id) => switch (id) {
    'watchlist' => watchlist,
    'comments' => comments,
    'description' => description,
    'channelVideos' => moreFromChannel,
    'openChannel' => openChannel,
    'share' => share,
    'openOnYouTube' => openOnYouTube,
    'rating' => '$like / $dislike',
    'back10' => back10,
    'forward10' => forward10,
    'previousNext' => _t('Previous / next video', 'Vorheriges / nächstes Video'),
    'highlight' => jumpToHighlight,
    'volume' => _t('Volume', 'Lautstärke'),
    'quality' => quality,
    'speed' => speed,
    'audio' => audioLanguage,
    'captions' => captions,
    'sleep' => sleepTimer,
    'chapters' => chapters,
    'fullscreen' => fullscreen,
    _ => id,
  };
  static String get youtubeHome => _t('YouTube home', 'YouTube-Startseite');
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
    'Follow channels right here, no account needed: add them by link or @handle, or import your subscriptions '
        'from Google Takeout. Signing in with Google is optional and adds automatic import, likes and comments.',
    'Folge Kanälen direkt hier, ganz ohne Konto: per Link oder @Handle hinzufügen oder deine Abos aus Google '
        'Takeout importieren. Die Google-Anmeldung ist optional und bringt automatischen Import, Likes und Kommentare.',
  );
  static String get addChannelsNoAccount => _t('Add channels', 'Kanäle hinzufügen');
  static String get signInOptional => _t('Sign in with Google (optional)', 'Mit Google anmelden (optional)');
  static String get channels => _t('Channels', 'Kanäle');
  static String get guide => _t('How it works', 'So funktioniert es');
  static String get channelsTitle => _t('Followed channels', 'Gefolgte Kanäle');
  static String get channelsSubtitle => _t(
    'Channels followed in the app, no Google account needed. Their newest videos come from YouTube\'s public feeds.',
    'In der App gefolgte Kanäle, ohne Google-Konto. Ihre neuesten Videos kommen aus YouTubes öffentlichen Feeds.',
  );
  static String get addChannelHint =>
      _t('Channel link, video link or @handle', 'Kanal-Link, Video-Link oder @Handle');
  static String get add => _t('Add', 'Hinzufügen');
  static String get importTakeout => _t('Import from Google Takeout', 'Aus Google Takeout importieren');
  static String get importTakeoutHelp => _t(
    'Pick the subscriptions.csv from your Takeout download (see "How it works").',
    'Wähle die subscriptions.csv aus deinem Takeout-Download (siehe „So funktioniert es“).',
  );
  static String imported(int n) => _t('$n channels imported.', '$n Kanäle importiert.');
  static String added(String title) => _t('Added $title.', '$title hinzugefügt.');
  static String get alreadyFollowed => _t('You already follow this channel.', 'Du folgst diesem Kanal bereits.');
  static String get channelNotFound => _t('Channel not found. Check the link or handle.',
      'Kanal nicht gefunden. Prüfe den Link oder das Handle.');
  static String get removeChannel => _t('Remove', 'Entfernen');
  static String get removeAllChannels => _t('Remove all', 'Alle entfernen');
  static String get noChannels => _t('No channels yet.', 'Noch keine Kanäle.');
  static String googleChannels(int n) => _t(
    '+ $n subscriptions from your Google account',
    '+ $n Abos aus deinem Google-Konto',
  );
  static String get signInForComments => _t(
    'Sign in with Google in the YouTube settings to see comments.',
    'Melde dich in den YouTube-Einstellungen mit Google an, um Kommentare zu sehen.',
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
  static String get minLength => _t('Minimum length', 'Mindestlänge');
  static String get minLengthSub =>
      _t('Shorter videos are left out of the feed', 'Kürzere Videos werden im Feed ausgeblendet');
  static String minLengthLabel(int m) => m == 0 ? _t('Any', 'Alle') : '$m min';
  static String get newBadge => _t('NEW', 'NEU');
  static String get speedForChannel => _t('Always for this channel', 'Immer für diesen Kanal');
  static String get speedForChannelOff => _t('Forget for this channel', 'Für diesen Kanal vergessen');
  static String get showShorts => _t('Show Shorts', 'Shorts anzeigen');
  static String get showPremieres => _t('Show premieres and upcoming', 'Premieren und Geplantes anzeigen');
  static String get hiddenByDefault => _t('Hidden by default', 'Standardmäßig ausgeblendet');
  static String get refreshEvery => _t('Refresh every', 'Aktualisieren alle');
  static String minutes(int m) => m >= 60 ? _t('${m ~/ 60} hour', '${m ~/ 60} Stunde') : _t('$m minutes', '$m Minuten');

  static String age(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.isNegative) return _t('soon', 'bald');
    if (diff.inMinutes < 1) return _t('just now', 'gerade eben');
    if (diff.inHours < 1) return _t('${diff.inMinutes}m ago', 'vor ${diff.inMinutes}m');
    if (diff.inDays < 1) return _t('${diff.inHours}h ago', 'vor ${diff.inHours}h');
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

  // Channel groups
  static String get allChannels => _t('All channels', 'Alle Kanäle');
  static String get newGroup => _t('New group', 'Neue Gruppe');
  static String get editGroup => _t('Edit group', 'Gruppe bearbeiten');
  static String get groupName => _t('Group name', 'Gruppenname');
  static String get groupChannels => _t('Channels in this group', 'Kanäle in dieser Gruppe');
  static String get noChannelsYet =>
      _t('Channels appear here once their videos are in the feed.', 'Kanäle erscheinen hier, sobald ihre Videos im Feed sind.');
  static String get emptyGroup => _t('No videos from this group yet.', 'Noch keine Videos aus dieser Gruppe.');
  static String get suggestGroups => _t('Suggest groups', 'Gruppen vorschlagen');
  static String get suggestGroupsHint => _t(
    'Groups by each channel\'s most common video category. Existing groups with the same name get the channels added.',
    'Gruppiert nach der häufigsten Videokategorie jedes Kanals. Bestehende Gruppen mit gleichem Namen erhalten die Kanäle zusätzlich.',
  );
  static String channelCount(int n) => _t(n == 1 ? '1 channel' : '$n channels', n == 1 ? '1 Kanal' : '$n Kanäle');
  static String get create => _t('Create', 'Erstellen');
  static String get noCategoryData => _t(
    'Categories come from the YouTube account. Sign in and refresh to get suggestions.',
    'Kategorien kommen vom YouTube-Konto. Anmelden und aktualisieren, um Vorschläge zu erhalten.',
  );
  static String get uncategorized => _t('Other', 'Sonstige');
}
