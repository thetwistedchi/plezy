import 'dart:io' show Platform;

import 'strings.g.dart';

/// Texts for the fork's 0.8 additions, English and German. Kept out of the
/// slang files so the fork stays easy to rebase onto upstream Plezy.
class RetroStrings {
  RetroStrings._();

  static bool get _de => LocaleSettings.currentLocale == AppLocale.de;
  static String _t(String en, String de) => _de ? de : en;

  static bool get isGerman => _de;
  static String get remoteShortcuts => _t('Remote shortcuts', 'Tasten der Fernbedienung');
  static String get remoteShortcutsSubtitle => _t('What the TV remote\'s buttons do', 'Was die Tasten der TV-Fernbedienung tun');

  static String get germanVoicesLoading => _t('Looking up German voices…', 'Deutsche Stimmen werden gesucht…');
  static String get germanVoicesNone => _t('No German voices found', 'Keine deutschen Stimmen gefunden');
  static String germanVoicesFrom(String source) => _t('German voices: $source', 'Deutsche Stimmen: $source');
  static String get audioTrack => _t('Audio track', 'Tonspur');
  static String get subtitleTrack => _t('Subtitles', 'Untertitel');
  /// Skip button label for the extra Jellyfin segment kinds, else null.
  static String? skipSegment(String type) => switch (type) {
    'recap' => _t('Skip recap', 'Rückblick überspringen'),
    'preview' => _t('Skip preview', 'Vorschau überspringen'),
    'commercial' => _t('Skip ad', 'Werbung überspringen'),
    _ => null,
  };
  static String get libraryLanguages => _t('Languages for this library', 'Sprachen für diese Mediathek');
  static String libraryLanguagesTitle(String library) => _t('Languages: $library', 'Sprachen: $library');
  static String get libraryLanguagesHelp => _t(
    'Two-letter language codes, for example ja, de or en. Leave a field empty to use your profile language.',
    'Sprachcodes mit zwei Buchstaben, z. B. ja, de oder en. Leer lassen = Sprache des Profils.',
  );
  static String get audioLanguageCode => _t('Audio language', 'Audiosprache');
  static String get subtitleLanguageCode => _t('Subtitle language', 'Untertitelsprache');
  static String get readerView => _t('Reader view', 'Leseansicht');
  static String get readerFailed => _t('This page could not be loaded.', 'Diese Seite konnte nicht geladen werden.');
  static String get readerEmpty =>
      _t('No article text found on this page.', 'Auf dieser Seite wurde kein Artikeltext gefunden.');
  static String get smallerText => _t('Smaller text', 'Kleinere Schrift');
  static String get largerText => _t('Larger text', 'Größere Schrift');
  static String get playInAppPlayer => _t("Play video in the app's player", 'Video im App-Player abspielen');
  static String get noVideoFound => _t(
    'No playable video found on this page.',
    'Auf dieser Seite wurde kein abspielbares Video gefunden.',
  );
  static String get back10 => _t('Back 10 seconds', '10 Sekunden zurück');
  static String get forward10 => _t('Forward 10 seconds', '10 Sekunden vor');
  static String filmSeries(String name, int have, int total) => _t(
    'Part of the film series "$name" · $have of $total parts in your library',
    'Teil der Filmreihe „$name“ · $have von $total Teilen in deiner Mediathek',
  );
  static String get notInLibrary => _t('Not in your library', 'Nicht in deiner Mediathek');
  static String get yourViewing => _t('Your viewing', 'Dein Schauen');
  static String get upcomingEpisodes => _t('Upcoming episodes', 'Kommende Folgen');
  static String get upcomingEpisodesDescription =>
      _t('Next air dates of the shows you are watching', 'Nächste Sendetermine deiner laufenden Serien');
  static String get upcomingNone => _t('No upcoming episodes announced.', 'Keine kommenden Folgen angekündigt.');
  static String get upcomingNoShows =>
      _t('No shows on Continue Watching yet.', 'Noch keine Serien unter Weiterschauen.');
  static String get subtitleManagementNotAllowed => _t(
    'This server lets only users with subtitle management search for subtitles. '
        'An administrator can turn on "Allow subtitle management" for your user in the dashboard (Users).',
    'Dieser Server erlaubt die Untertitelsuche nur Benutzern mit Untertitelverwaltung. '
        'Ein Administrator kann „Untertitelverwaltung erlauben“ für deinen Benutzer im Dashboard (Benutzer) einschalten.',
  );
  static String get subtitleAddedOnServer => _t(
    'Subtitle added on the server. It shows up the next time the video starts.',
    'Untertitel auf dem Server hinzugefügt. Er steht beim nächsten Start des Videos bereit.',
  );
  static String get videoNotPlayable => _t(
    'This video can\'t be played in the app player. Start it on the page first, then try again.',
    'Dieses Video kann der App-Player nicht abspielen. Starte es zuerst auf der Seite und versuche es dann erneut.',
  );
  static String get tomorrow => _t('Tomorrow', 'Morgen');
  static String get upcomingTab => _t('Upcoming', 'Demnächst');
  static String upcomingChecking(int done, int total) =>
      _t('Checking air dates: $done of $total shows', 'Prüfe Sendetermine: $done von $total Serien');
  static String get upcomingOnHome => _t('Show on Home', 'Auf der Startseite zeigen');
  static String get upcomingOnHomeDescription =>
      _t('A row after Continue Watching', 'Eine Reihe nach Weiterschauen');
  static String get watchStats => _t('Watch statistics', 'Statistik');
  static String get watchStatsDescription =>
      _t('Hours watched, favourite genres, recent months', 'Gesehene Stunden, Lieblingsgenres, letzte Monate');
  static String get statsHours => _t('hours watched', 'Stunden gesehen');
  static String get statsMovies => _t('films', 'Filme');
  static String get statsEpisodes => _t('episodes', 'Folgen');
  static String get statsShows => _t('shows', 'Serien');
  static String get statsGenres => _t('Favourite genres', 'Lieblingsgenres');
  static String get statsMonths => _t('Last twelve months', 'Letzte zwölf Monate');
  static String get statsMonthsHint =>
      _t('Titles by the month they were last watched', 'Titel nach dem Monat, in dem sie zuletzt gesehen wurden');
  static String get traktImport => _t('Import watch history from Trakt', 'Verlauf von Trakt importieren');
  static String get traktImportDescription =>
      _t('Mark everything watched on Trakt as watched', 'Alles auf Trakt Gesehene als gesehen markieren');
  static String get traktImportHelp => _t(
    'Every film and episode you have watched on Trakt is marked as watched on your servers. Titles are matched by their IMDb, TMDB and TVDB ids. Nothing is marked as unwatched.',
    'Jeder Film und jede Folge, die du auf Trakt gesehen hast, wird auf deinen Servern als gesehen markiert. Zugeordnet wird über IMDb-, TMDB- und TVDB-IDs. Nichts wird als ungesehen markiert.',
  );
  static String get traktNotConnected =>
      _t('Connect Trakt first under Settings > Services.', 'Zuerst Trakt unter Einstellungen > Dienste verbinden.');
  static String get traktImportStart => _t('Start import', 'Import starten');
  static String get traktReading => _t('Reading your Trakt history…', 'Trakt-Verlauf wird gelesen…');
  static String traktProgress(int n, int total) => _t('Title $n of $total', 'Titel $n von $total');
  static String get traktFailed => _t('The import stopped with an error.', 'Der Import wurde mit einem Fehler beendet.');
  static String traktImportDone(int movies, int episodes, int missing) => _t(
    'Done: $movies films and $episodes episodes marked as watched. $missing titles are not in your libraries.',
    'Fertig: $movies Filme und $episodes Folgen als gesehen markiert. $missing Titel sind nicht in deinen Mediatheken.',
  );
  static String get nightMode => _t('Night mode', 'Nachtmodus');
  static String get nightModeDescription => _t(
    'Quieter loud scenes and clearer dialogue at low volume',
    'Leisere laute Szenen und verständlichere Dialoge bei geringer Lautstärke',
  );
  static String get importBookmarks => _t('Import bookmarks', 'Lesezeichen importieren');
  static String get importBookmarksDescription => _t(
    'From an HTML export of Chrome, Firefox, Edge, Brave or Safari',
    'Aus einem HTML-Export von Chrome, Firefox, Edge, Brave oder Safari',
  );
  static String get importAction => _t('Import', 'Importieren');
  static String bookmarksImported(int n) =>
      _t('$n bookmark${n == 1 ? '' : 's'} imported', '$n Lesezeichen importiert');
  static String get bookmarksImportFailed =>
      _t('That file could not be read', 'Die Datei konnte nicht gelesen werden');
  static String get saveLogs => _t('Save logs to a file', 'Logs in Datei speichern');
  static String get logsSaved => _t('Logs saved', 'Logs gespeichert');
  static String get logsSaveFailed => _t('Could not save the logs', 'Logs konnten nicht gespeichert werden');
  static String get logsSavedTvHint =>
      _t('Copy the file to a computer with this command:', 'Die Datei mit diesem Befehl auf einen Computer kopieren:');
  static String get gamepadInput => _t('Game controller input', 'Controller-Eingaben');
  static String get gamepadInputDescription =>
      _t('Navigate with a connected game controller', 'Mit einem angeschlossenen Controller navigieren');
  static String get germanVoiceActors => _t('German voice actors', 'Deutsche Synchronsprecher');
  static String get germanVoiceActorsDescription => _t(
    'With German audio selected, show the German voice under each cast member (Deutsche Synchronkartei)',
    'Bei deutscher Tonspur die deutsche Stimme unter jedem Darsteller zeigen (Deutsche Synchronkartei)',
  );

  // Home rows
  static String get hideWatched => _t('Hide watched', 'Gesehenes ausblenden');

  // Free on Plex (Plex's ad-supported Movies & Shows)
  static String get freeOnPlex => _t('Free on plex.tv', 'Kostenlos auf plex.tv');
  static String get freeOnPlexAll => _t('All titles', 'Alle Titel');
  static String get freeOnPlexEpisodes => _t('Episodes (free on Plex)', 'Folgen (kostenlos auf Plex)');
  static String get freeOnPlexChooseSeason => _t('Choose a season', 'Staffel wählen');
  static String get freeOnPlexChooseEpisode => _t('Choose an episode', 'Folge wählen');
  static String get freeOnPlexPlexChoice => _t('Where Plex continues', 'Wo Plex weitermacht');
  static String get freeOnPlexContinue => _t('Continue watching', 'Weiterschauen');
  static String get freeOnPlexWatchlist => _t('Free on your watchlist', 'Kostenlos auf deiner Merkliste');
  static String get freeOnPlexSearch => _t('Search Plex\'s free titles', 'Kostenlose Titel von Plex suchen');
  static String freeOnPlexResults(String query) => _t('Free results for "$query"', 'Kostenlose Treffer für „$query"');
  static String freeOnPlexSearching(String query) => _t('Searching Plex\'s free titles for "$query"…', 'Suche in den kostenlosen Titeln von Plex nach „$query“…');
  static String get freeOnPlexNoResults => _t('No free titles found.', 'Keine kostenlosen Titel gefunden.');
  static String get freeOnPlexPlay => _t('Watch free on Plex', 'Kostenlos auf Plex ansehen');
  static String get freeOnPlexWatch => _t('Plex (free, with ads)', 'Plex (kostenlos, mit Werbung)');
  static String get freeOnPlexHint => Platform.isAndroid
      ? _t(
          'Plex\'s free, ad-supported movies and shows. Open a title and press "Watch free on Plex": it plays full screen in Plex Web, Back closes it.',
          'Die kostenlosen, werbefinanzierten Filme und Serien von Plex. Titel öffnen und „Kostenlos auf Plex ansehen" drücken: Er läuft im Vollbild in Plex Web, Zurück schließt ihn.',
        )
      : _t(
          'Plex\'s free, ad-supported movies and shows. Open a title and press "Watch free on Plex": it plays in Plex Web.',
          'Die kostenlosen, werbefinanzierten Filme und Serien von Plex. Titel öffnen und „Kostenlos auf Plex ansehen" drücken: Er läuft in Plex Web.',
        );
  static String get freeOnPlexNoAccount =>
      _t('Sign in with a Plex account to see Plex\'s free titles.', 'Melde dich mit einem Plex-Konto an, um die kostenlosen Titel von Plex zu sehen.');
  static String get freeOnPlexEmpty => _t('Plex offers no free titles here right now.', 'Plex bietet hier gerade keine kostenlosen Titel an.');
  static String get freeOnPlexFailed =>
      _t('Plex\'s free catalog could not be loaded.', 'Der kostenlose Katalog von Plex konnte nicht geladen werden.');
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

  // In-app browser
  static String get browser => _t('Browser', 'Browser');

  /// The browser's menu entry; still a beta on Android.
  static String get browserNav => Platform.isAndroid ? _t('Browser (Beta)', 'Browser (Beta)') : browser;
  /// Same label as the sidebar's Home entry.
  static String get home => t.common.home;
  static String get newTab => _t('New tab', 'Neuer Tab');
  static String get closeTab => _t('Close tab', 'Tab schließen');
  static String get forward => _t('Forward', 'Vorwärts');
  static String get reload => _t('Reload', 'Neu laden');
  static String get stopLoading => _t('Stop', 'Stopp');
  static String get leaveBrowser => _t('Leave browser', 'Browser verlassen');
  static String addressHint(String engine) =>
      _t('Search with $engine or enter an address', 'Mit $engine suchen oder Adresse eingeben');
  static String get secureConnection => _t('Secure connection', 'Sichere Verbindung');
  static String get insecureConnection =>
      _t('Not secure: this page is not encrypted', 'Nicht sicher: Diese Seite ist nicht verschlüsselt');
  static String get addBookmark => _t('Add bookmark', 'Lesezeichen hinzufügen');
  static String get removeBookmark => _t('Remove bookmark', 'Lesezeichen entfernen');
  static String get bookmarks => _t('Bookmarks', 'Lesezeichen');
  static String get noBookmarks =>
      _t('No bookmarks yet. Use the star in the address bar to add one.', 'Noch keine Lesezeichen. Mit dem Stern in der Adressleiste fügst du eins hinzu.');
  static String get renameBookmark => _t('Rename', 'Umbenennen');
  static String get delete => _t('Delete', 'Löschen');
  static String get cancel => _t('Cancel', 'Abbrechen');
  static String get save => _t('Save', 'Speichern');
  static String get allow => _t('Allow', 'Erlauben');
  static String get block => _t('Block', 'Blockieren');
  static String get popupBlocked => _t('Pop-up blocked', 'Pop-up blockiert');
  static String popupBlockedFrom(String site) => _t('Pop-up from $site blocked', 'Pop-up von $site blockiert');
  static String redirectBlocked(String site) =>
      _t('$site tried to leave for another site after opening a pop-up', '$site wollte nach einem Pop-up zu einer anderen Seite wechseln');
  static String get alwaysAllow => _t('Always allow', 'Immer erlauben');
  static String get popupNeverHere => _t('Never show for this site', 'Für diese Seite nie anzeigen');
  static String get popupQuietSites =>
      _t('Pop-ups blocked without a notice on', 'Pop-ups ohne Hinweis blockiert auf');
  static String get popupSites => _t('Pop-ups allowed on', 'Pop-ups erlaubt auf');
  static String get popupSitesEmpty => _t(
    'Pop-ups only open after a click on a link or within the same site. Sites you allow from the pop-up notice are listed here.',
    'Pop-ups öffnen sich nur nach einem Klick auf einen Link oder innerhalb derselben Seite. Seiten, die du über den Pop-up-Hinweis erlaubst, stehen hier.',
  );
  static String get openAnyway => _t('Open anyway', 'Trotzdem öffnen');
  static String get httpsFailed =>
      _t('This site could not be loaded securely.', 'Diese Seite konnte nicht sicher geladen werden.');
  static String get loadOverHttp => _t('Load without encryption', 'Unverschlüsselt laden');
  static String get schemeBlocked =>
      _t('Local files and scripts in the address bar are blocked.', 'Lokale Dateien und Skripte in der Adressleiste sind blockiert.');
  static String get tabUnresponsive => _t('This page is not responding.', 'Diese Seite reagiert nicht.');
  static String get wait => _t('Wait', 'Warten');
  static String get tabCrashed => _t('This tab stopped working.', 'Dieser Tab funktioniert nicht mehr.');
  static String permissionAsk(String host, String what) =>
      _t('$host wants to use your $what.', '$host möchte $what verwenden.');
  static String permissionKind(int kind) => switch (kind) {
    1 => permMicrophone,
    2 => permCamera,
    3 => permLocation,
    5 => permSensors,
    6 => permClipboard,
    _ => permOther,
  };
  static String permissionLabel(int kind) => switch (kind) {
    1 => _t('Microphone', 'Mikrofon'),
    2 => _t('Camera', 'Kamera'),
    3 => _t('Location', 'Standort'),
    5 => _t('Motion sensors', 'Bewegungssensoren'),
    6 => _t('Clipboard', 'Zwischenablage'),
    _ => _t('Device features', 'Gerätefunktionen'),
  };
  static String get rememberForSite => _t('Remember for this site', 'Für diese Seite merken');
  static String get permCamera => _t('camera', 'deine Kamera');
  static String get permMicrophone => _t('microphone', 'dein Mikrofon');
  static String get permLocation => _t('location', 'deinen Standort');
  static String get permClipboard => _t('clipboard', 'deine Zwischenablage');
  static String get permSensors => _t('motion sensors', 'Bewegungssensoren');
  static String get permOther => _t('device features', 'Gerätefunktionen');
  static String get downloadTitle => _t('Download file?', 'Datei herunterladen?');
  static String downloadFrom(String host) => _t('From $host', 'Von $host');
  static String get downloadRisky => _t(
    'This file type can run programs on your PC. Only download it if you trust the site.',
    'Dieser Dateityp kann Programme auf deinem PC ausführen. Lade ihn nur herunter, wenn du der Seite vertraust.',
  );
  static String get download => _t('Download', 'Herunterladen');
  static String saveTo(String folder) => _t('Saved to $folder', 'Wird gespeichert in $folder');
  static String get saveAs => _t('Save as…', 'Speichern unter…');
  static String get downloadDone => _t('Done', 'Fertig');
  static String get downloadSection => _t('Downloads', 'Downloads');
  static String get downloadFolder => _t('Download folder', 'Download-Ordner');
  static String get downloadFolderDefault => _t('Windows Downloads folder', 'Windows-Download-Ordner');
  static String get privateTabsUnsupported => _t(
    'Private tabs need a newer Android System WebView. Update it in the Play Store.',
    'Private Tabs brauchen ein neueres Android System WebView. Aktualisiere es im Play Store.',
  );
  static String get openDownloads => _t('Open downloads', 'Downloads öffnen');
  static String get phoneRemote => _t('Phone as remote', 'Handy als Fernbedienung');
  static String get phoneRemoteHint => _t(
    'Scan the code with a phone in the same network. The page that opens moves the pointer, clicks, scrolls and types into the browser. Only the first phone that opens it is accepted.',
    'Scanne den Code mit einem Handy im selben Netzwerk. Die Seite, die sich öffnet, bewegt den Zeiger, klickt, scrollt und tippt in den Browser. Nur das erste Handy, das sie öffnet, wird angenommen.',
  );
  static String get phoneRemoteConnected => _t('Phone connected', 'Handy verbunden');
  static String get phoneRemoteNoNetwork => _t(
    'No local network found for the phone remote.',
    'Kein lokales Netzwerk für die Handy-Fernbedienung gefunden.',
  );
  static String get stopRemote => _t('Stop', 'Beenden');

  static String get change => _t('Change', 'Ändern');
  static String get reset => _t('Reset', 'Zurücksetzen');
  static String get askWhereToSave => _t('Ask where to save each file', 'Bei jeder Datei fragen, wo sie gespeichert wird');

  static String get tabSleeping =>
      _t('Sleeping: paused to save resources, continues when opened', 'Schläft: pausiert, um Ressourcen zu sparen, läuft beim Öffnen weiter');
  static String get newPrivateTab => _t('New private tab', 'Neuer privater Tab');
  static String get privateTab => _t('Private tab', 'Privater Tab');
  static String get privateTabHint => _t(
    'Private tab: cookies, history and site data of private tabs are deleted when the last private tab closes. Downloads and bookmarks stay.',
    'Privater Tab: Cookies, Verlauf und Websitedaten privater Tabs werden gelöscht, sobald der letzte private Tab geschlossen wird. Downloads und Lesezeichen bleiben.',
  );
  static String get recentlyClosed => _t('Recently closed tabs…', 'Kürzlich geschlossene Tabs…');
  static String reopenAllClosed(int n) => _t('Reopen all ($n)', 'Alle wieder öffnen ($n)');
  static String get duplicateTab => _t('Duplicate tab', 'Tab duplizieren');
  static String get closeOtherTabs => _t('Close other tabs', 'Andere Tabs schließen');
  static String get muteTab => _t('Mute tab', 'Tab stummschalten');
  static String get unmuteTab => _t('Unmute tab', 'Ton wieder einschalten');
  static String get openInDefaultBrowser => _t('Open in default browser', 'Im Standardbrowser öffnen');
  static String get moreActions => _t('More', 'Mehr');
  static String get downloads => _t('Downloads', 'Downloads');
  static String get noDownloads => _t('No downloads yet.', 'Noch keine Downloads.');
  static String get showInFolder => _t('Show in folder', 'Im Ordner anzeigen');
  static String get pause => _t('Pause', 'Pausieren');
  static String get resume => _t('Resume', 'Fortsetzen');
  static String get clearList => _t('Clear list', 'Liste leeren');
  static String get downloadFailed => _t('Failed', 'Fehlgeschlagen');
  static String get downloadPaused => _t('Paused', 'Pausiert');

  // Ad blocker
  static String get adblock => _t('Ad blocker', 'Werbeblocker');
  static String adblockCount(int n) => _t(
    n == 1 ? '1 request blocked on this page' : '$n requests blocked on this page',
    n == 1 ? '1 Anfrage auf dieser Seite blockiert' : '$n Anfragen auf dieser Seite blockiert',
  );
  static String adblockOnSite(String site) => _t('Blocking on $site', 'Blockieren auf $site');
  static String get adblockOffEverywhere => _t('The ad blocker is switched off.', 'Der Werbeblocker ist ausgeschaltet.');
  static String get filterLists => _t('Filter lists', 'Filterlisten');
  static String get adblockDescription => _t(
    'Blocks ads, trackers and known malware sites with the filter lists below. Uses Brave\'s open-source adblock engine and uBlock Origin\'s filter syntax.',
    'Blockiert Werbung, Tracker und bekannte Schadseiten mit den Filterlisten unten. Nutzt Braves Open-Source-Werbeblocker und die Filtersyntax von uBlock Origin.',
  );
  static String get updateLists => _t('Update now', 'Jetzt aktualisieren');
  static String get updatingLists => _t('Updating…', 'Wird aktualisiert…');
  static String listRules(int n) => _t('$n rules', '$n Regeln');
  static String get listNotLoaded => _t('Not downloaded yet', 'Noch nicht heruntergeladen');
  static String get listFailed => _t('Download failed', 'Download fehlgeschlagen');
  static String get customLists => _t('Your lists', 'Eigene Listen');
  static String get addListUrl => _t('Add a list by its address', 'Liste über ihre Adresse hinzufügen');
  static String get addList => _t('Add', 'Hinzufügen');
  static String get myFilters => _t('My filters', 'Meine Filter');
  static String get myFiltersHint => _t(
    'One filter per line, in uBlock Origin / Adblock Plus syntax, e.g. ||ads.example.com^ or example.com##.banner',
    'Ein Filter pro Zeile, in uBlock-Origin-/Adblock-Plus-Syntax, z. B. ||ads.example.com^ oder example.com##.banner',
  );
  static String get apply => _t('Apply', 'Übernehmen');
  static String get adblockOffSites => _t('Sites without blocking', 'Seiten ohne Blockieren');
  static String get adblockOffSitesEmpty => _t(
    'Sites you switch blocking off for (shield button) appear here.',
    'Seiten, auf denen du das Blockieren ausschaltest (Schild-Knopf), erscheinen hier.',
  );
  static String filterGroup(String group) => switch (group) {
    'builtin' => 'uBlock Origin',
    'ads' => _t('Ads', 'Werbung'),
    'privacy' => _t('Privacy', 'Privatsphäre'),
    'malware' => _t('Malware protection, security', 'Schutz vor Schadsoftware, Sicherheit'),
    'annoyances' => _t('Annoyances (cookie notices, pop-ups)', 'Störendes (Cookie-Hinweise, Pop-ups)'),
    'multipurpose' => _t('Multipurpose', 'Mehrzweck'),
    'regional' => _t('Regions, languages', 'Regionen, Sprachen'),
    _ => _t('Your lists', 'Eigene Listen'),
  };
  static String get pageBlockedTitle => _t('Page blocked', 'Seite blockiert');
  static String pageBlockedText(String host) => _t(
    '$host is on one of your filter lists, for example as a known malware, phishing, tracking or ad site. The ad blocker kept it from opening.',
    '$host steht auf einer deiner Filterlisten, zum Beispiel als bekannte Schad-, Phishing-, Tracking- oder Werbeseite. Der Werbeblocker hat das Öffnen verhindert.',
  );
  static String get proceedOnce => _t('Open anyway', 'Trotzdem öffnen');

  // Browser settings
  static String get browserSettings => _t('Browser settings', 'Browser-Einstellungen');
  static String get searchEngine => _t('Search engine', 'Suchmaschine');
  static String get customSearchEngine => _t('Custom', 'Eigene');
  static String get customSearchHint =>
      _t('Address with %s for the search words', 'Adresse mit %s für die Suchbegriffe');
  static String get newTabPageSetting => _t('New tab page', 'Neuer-Tab-Seite');
  static String get newTabRecent => _t('Recently visited pages', 'Zuletzt besuchte Seiten');
  static String get recentCount => _t('Pages shown', 'Angezeigte Seiten');
  static String get recentEmpty => _t('Pages you visit will show up here.', 'Besuchte Seiten erscheinen hier.');
  static String get removeFromList => _t('Remove from list', 'Aus der Liste entfernen');
  static String get history => _t('History', 'Verlauf');
  static String get searchHistory => _t('Search history', 'Verlauf durchsuchen');
  static String get historyEmpty => _t('No visited pages.', 'Keine besuchten Seiten.');
  static String get today => _t('Today', 'Heute');
  static String get yesterday => _t('Yesterday', 'Gestern');
  static String get earlier => _t('Earlier', 'Früher');
  static String get clearHistory => _t('Clear history', 'Verlauf löschen');
  static String get historyDescription =>
      _t('The recently visited pages on the new tab page', 'Die zuletzt besuchten Seiten auf der Neuer-Tab-Seite');
  static String get keepHistory => _t('Remember visited pages', 'Besuchte Seiten merken');
  static String get keepHistoryDescription => _t(
    'Keep the recently visited pages after the app is closed. When off, the list starts empty with every app start.',
    'Die zuletzt besuchten Seiten auch nach dem Schließen der App behalten. Wenn aus, ist die Liste bei jedem App-Start leer.',
  );
  static String get historyCleared => _t('History cleared.', 'Verlauf gelöscht.');
  static String get open => _t('Open', 'Öffnen');
  static String get newTabBlank => _t('Empty', 'Leer');
  static String get newTabCustom => _t('Custom address', 'Eigene Adresse');
  static String get suspendTabs => _t('Pause tabs in the background', 'Tabs im Hintergrund pausieren');
  static String suspendAfter(int minutes) => minutes <= 0
      ? _t('Never', 'Nie')
      : _t('After $minutes ${minutes == 1 ? 'minute' : 'minutes'}', 'Nach $minutes ${minutes == 1 ? 'Minute' : 'Minuten'}');
  static String get suspendDescription => _t(
    'Only the tab on screen keeps running. Others pause after this time and continue when you open them. When memory runs low, they pause right away.',
    'Nur der sichtbare Tab läuft weiter. Andere pausieren nach dieser Zeit und laufen weiter, sobald du sie öffnest. Bei knappem Arbeitsspeicher pausieren sie sofort.',
  );
  static String get tvPointer => _t('Pointer for the remote', 'Zeiger für die Fernbedienung');
  static String get tvPointerHere => _t('Pointer on this site', 'Zeiger auf dieser Seite');
  static String get tvPointerDescription => _t(
    'The arrows move a pointer over the page (hold for faster) and OK clicks. Off: the arrows select the page\'s links and buttons. Holding OK on a page or the ⋮ menu switches it for that website; the choice is remembered per site.',
    'Die Pfeiltasten bewegen einen Zeiger über die Seite (gedrückt halten für schneller), OK klickt. Aus: Die Pfeiltasten wählen die Links und Schaltflächen der Seite. OK gedrückt halten oder das ⋮-Menü schaltet ihn für diese Website um; das wird pro Seite gemerkt.',
  );
  static String get keepPlayingAwake => _t('Keep tabs playing audio running', 'Tabs mit Ton weiterlaufen lassen');
  static String get restoreTabs => _t('Restore tabs', 'Tabs wiederherstellen');
  static String get restoreTabsDescription =>
      _t('Open the last tabs again after a restart', 'Nach einem Neustart die letzten Tabs wieder öffnen');
  static String get httpsUpgrade => _t('Always use HTTPS', 'Immer HTTPS verwenden');
  static String get httpsUpgradeDescription => _t(
    'Loads pages encrypted when possible. Addresses in your home network are left as they are.',
    'Lädt Seiten wenn möglich verschlüsselt. Adressen im Heimnetz bleiben unverändert.',
  );
  static String get browserCacheLimit => _t('Cache limit', 'Cache-Limit');
  static String get browserCacheLimitDescription => _t(
    'Applies after clearing the cache or restarting the app',
    'Gilt nach dem Leeren des Caches oder einem Neustart der App',
  );
  static String get browserCache => _t('Browser cache', 'Browser-Cache');
  static String browserCacheUsed(String size) =>
      _t('$size used · clearing keeps you signed in on websites', '$size belegt · Leeren hält dich auf Webseiten angemeldet');
  static String get clearBrowserCache => _t('Clear cache', 'Cache leeren');
  static String get browserCacheCleared => _t('Browser cache cleared.', 'Browser-Cache geleert.');
  static String fileSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    return '${(bytes / 1024).ceil()} KB';
  }

  static String get darkMode => _t('Dark mode for websites', 'Dunkelmodus für Webseiten');
  static String get darkModeDescription => _t(
    'Shows bright websites dark, using Dark Reader. Can slow down very large pages.',
    'Zeigt helle Webseiten dunkel an, mit Dark Reader. Kann sehr große Seiten verlangsamen.',
  );
  static String darkOnSite(String site) => _t('Dark mode on $site', 'Dunkelmodus auf $site');
  static String get darkBrightness => _t('Brightness', 'Helligkeit');
  static String get darkContrast => _t('Contrast', 'Kontrast');
  static String get darkExcluded => _t('Shown without dark mode', 'Ohne Dunkelmodus angezeigt');
  static String get darkExcludedEmpty => _t(
    'Sites you turn dark mode off for (⋮ menu) appear here.',
    'Seiten, für die du den Dunkelmodus ausschaltest (⋮-Menü), erscheinen hier.',
  );
  static String get trackingPrevention => _t('Tracking prevention', 'Schutz vor Tracking');
  static String get trackingDescription => Platform.isAndroid ? _trackingAndroid : _trackingWindows;
  static String get _trackingAndroid => _t(
    'Balanced and Strict block third-party cookies, which other sites use to follow you across pages, and tell pages not to track you or sell your data (Global Privacy Control). Turn it down if a sign-in on another site stops working.',
    'Ausgewogen und Streng blockieren Drittanbieter-Cookies, mit denen fremde Seiten dich über Seiten hinweg verfolgen, und teilen Seiten mit, dich nicht zu verfolgen und deine Daten nicht zu verkaufen (Global Privacy Control). Stell es niedriger, wenn eine Anmeldung über eine andere Seite nicht mehr klappt.',
  );
  static String get _trackingWindows => _t(
    'Blocks known trackers and fingerprinting services, like in Microsoft Edge. Strict blocks the most and may break some sites.',
    'Blockiert bekannte Tracker und Fingerprinting-Dienste wie in Microsoft Edge. Streng blockiert am meisten und kann einzelne Seiten stören.',
  );
  static String trackingLevel(int level) => switch (level) {
    0 => _t('Off', 'Aus'),
    1 => _t('Basic', 'Einfach'),
    3 => _t('Strict', 'Streng'),
    _ => _t('Balanced', 'Ausgewogen'),
  };
  static String get siteData => _t('Cookies and site data', 'Cookies und Websitedaten');
  static String get siteDataDescription => _t(
    'Signs you out of all websites and removes what they stored on this PC.',
    'Meldet dich auf allen Webseiten ab und entfernt, was sie auf diesem PC gespeichert haben.',
  );
  static String get deleteSiteData => _t('Delete', 'Löschen');
  static String get siteDataDeleted => _t('Cookies and site data deleted.', 'Cookies und Websitedaten gelöscht.');
  static String get clearOnExit => _t('Delete when the app closes', 'Beim Schließen der App löschen');
  static String get clearOnExitDescription => _t(
    'Every app start begins without cookies, so you are signed out of websites each time.',
    'Jeder App-Start beginnt ohne Cookies, du bist also jedes Mal auf Webseiten abgemeldet.',
  );
  static String get sitePermissions => _t('Site permissions', 'Website-Berechtigungen');
  static String get sitePermissionsEmpty => _t(
    'Answers you choose to remember when a site asks for the camera, microphone or location appear here.',
    'Antworten, die du dir beim Zugriff auf Kamera, Mikrofon oder Standort merken lässt, erscheinen hier.',
  );
  static String get allowed => _t('Allowed', 'Erlaubt');
  static String get blocked => _t('Blocked', 'Blockiert');

  static String get browserProtection => _t('Built-in protection', 'Eingebauter Schutz');
  static String get browserProtectionDescription => Platform.isAndroid ? _browserProtectionAndroid : _browserProtectionWindows;
  static String get _browserProtectionAndroid => _t(
    'Pop-ups only open from a clicked link or within the same site, pages can\'t jump to another site right after opening one, websites get no access to the camera, microphone or location, and Google Safe Browsing warns about known dangerous sites.',
    'Pop-ups öffnen sich nur über einen angeklickten Link oder innerhalb derselben Seite, Seiten können nach einem Pop-up nicht sofort zu einer anderen Seite springen, Websites erhalten keinen Zugriff auf Kamera, Mikrofon oder Standort und Google Safe Browsing warnt vor bekannten gefährlichen Seiten.',
  );
  static String get _browserProtectionWindows => _t(
    'Pop-ups only open from a clicked link or within the same site, pages can\'t jump to another site right after opening one, notification requests are declined, passwords and form data are not saved, and Microsoft Defender SmartScreen warns about known dangerous sites and downloads.',
    'Pop-ups öffnen sich nur über einen angeklickten Link oder innerhalb derselben Seite, Seiten können nach einem Pop-up nicht sofort zu einer anderen Seite springen, Benachrichtigungsanfragen werden abgelehnt, Passwörter und Formulardaten werden nicht gespeichert und Microsoft Defender SmartScreen warnt vor bekannten gefährlichen Seiten und Downloads.',
  );
}
