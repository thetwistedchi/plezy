import 'strings.g.dart';

/// Texts for the fork's 0.8 additions, English and German. Kept out of the
/// slang files so the fork stays easy to rebase onto upstream Plezy.
class RetroStrings {
  RetroStrings._();

  static bool get _de => LocaleSettings.currentLocale == AppLocale.de;
  static String _t(String en, String de) => _de ? de : en;

  // Home rows
  static String get hideWatched => _t('Hide watched', 'Gesehenes ausblenden');

  // Free on Plex (Plex's ad-supported Movies & Shows)
  static String get freeOnPlex => _t('Free on Plex', 'Kostenlos auf Plex');
  static String get freeOnPlexAll => _t('All titles', 'Alle Titel');
  static String get freeOnPlexWatch => _t('Plex (free, with ads)', 'Plex (kostenlos, mit Werbung)');
  static String get freeOnPlexHint => _t(
    'Plex\'s free, ad-supported movies and shows. They play in Plex\'s own app or Plex Web: open a title and use the Plex button.',
    'Die kostenlosen, werbefinanzierten Filme und Serien von Plex. Sie laufen in der Plex-App oder Plex Web: Titel öffnen und den Plex-Knopf nutzen.',
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

  // In-app browser
  static String get browser => _t('Browser', 'Browser');
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
  static String get downloadsFolder => _t('Saved to your Downloads folder.', 'Wird in deinem Download-Ordner gespeichert.');

  static String get newPrivateTab => _t('New private tab', 'Neuer privater Tab');
  static String get privateTab => _t('Private tab', 'Privater Tab');
  static String get privateTabHint => _t(
    'Private tab: cookies, history and site data of private tabs are deleted when the last private tab closes. Downloads and bookmarks stay.',
    'Privater Tab: Cookies, Verlauf und Websitedaten privater Tabs werden gelöscht, sobald der letzte private Tab geschlossen wird. Downloads und Lesezeichen bleiben.',
  );
  static String get reopenClosedTab => _t('Reopen closed tab', 'Geschlossenen Tab wieder öffnen');
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
  static String listsUpdated(String when) => _t('Last checked $when', 'Zuletzt geprüft $when');
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
  static String get trackingDescription => _t(
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
  static String get browserProtectionDescription => _t(
    'Pop-ups only open from a clicked link or within the same site, pages can\'t jump to another site right after opening one, notification requests are declined, passwords and form data are not saved, and Microsoft Defender SmartScreen warns about known dangerous sites and downloads.',
    'Pop-ups öffnen sich nur über einen angeklickten Link oder innerhalb derselben Seite, Seiten können nach einem Pop-up nicht sofort zu einer anderen Seite springen, Benachrichtigungsanfragen werden abgelehnt, Passwörter und Formulardaten werden nicht gespeichert und Microsoft Defender SmartScreen warnt vor bekannten gefährlichen Seiten und Downloads.',
  );
}
