import '../../../media/media_item.dart';
import '../../settings_service.dart';
import 'release_date.dart';

/// Fork: what a music library holds. Audiobooks and audio dramas
/// (Hörspiele) play like books: skip buttons, speed, resume, chapters.
enum AudioMode {
  music,
  audiobook,
  audioDrama,
  podcast;

  bool get isBookLike => this == audiobook || this == audioDrama;
  bool get isSpoken => this != music;
}

/// Volume levelling for music.
enum AudioLevelling { off, track, album, automatic }

/// Equalizer presets, as chains of ffmpeg `equalizer` bands (mpv `af`).
enum AudioEqPreset {
  flat,
  bass,
  treble,
  loudness,
  speech,
  vocal;

  /// The filter chain, empty for [flat].
  String get filter => switch (this) {
    flat => '',
    bass => 'equalizer=f=60:t=q:w=1:g=6,equalizer=f=150:t=q:w=1:g=3',
    treble => 'equalizer=f=6000:t=q:w=1:g=3,equalizer=f=12000:t=q:w=1:g=5',
    loudness => 'equalizer=f=60:t=q:w=1:g=5,equalizer=f=1000:t=q:w=1:g=-2,equalizer=f=10000:t=q:w=1:g=4',
    speech =>
      'highpass=f=90,equalizer=f=250:t=q:w=1:g=-3,equalizer=f=3000:t=q:w=1.2:g=4,equalizer=f=9000:t=q:w=1:g=-2',
    vocal => 'equalizer=f=200:t=q:w=1:g=-2,equalizer=f=2000:t=q:w=1:g=3,equalizer=f=4500:t=q:w=1:g=2',
  };
}

/// Preferences of the fork's audio features.
abstract final class AudioSettings {
  /// `serverId:libraryId=mode` per music library.
  static const libraryModes = StringListPref('retrowave_audio_library_modes');
  static const levelling = EnumPref<AudioLevelling>(
    'retrowave_audio_levelling',
    values: AudioLevelling.values,
    defaultValue: AudioLevelling.off,
  );

  /// Seconds of fade out and in between tracks of different albums; 0 = off.
  static const fadeSeconds = IntPref('retrowave_audio_fade_seconds', defaultValue: 0);
  static const musicNightMode = BoolPref('retrowave_audio_night_mode');
  static const eqMusic = EnumPref<AudioEqPreset>(
    'retrowave_audio_eq_music',
    values: AudioEqPreset.values,
    defaultValue: AudioEqPreset.flat,
  );
  static const eqSpoken = EnumPref<AudioEqPreset>(
    'retrowave_audio_eq_spoken',
    values: AudioEqPreset.values,
    defaultValue: AudioEqPreset.flat,
  );

  /// Seconds the skip buttons jump in spoken modes.
  /// Books and audio dramas: play only the chosen track, then pause.
  static const singleTrack = BoolPref('retrowave_audio_single_track');

  /// Lyrics from LRCLIB when the server has none.
  static const onlineLyrics = BoolPref('retrowave_audio_online_lyrics', defaultValue: true);

  /// Podcasts: skip chapters whose title names an ad (as Podshelf does).
  static const skipAdChapters = BoolPref('retrowave_audio_skip_ad_chapters', defaultValue: true);
  static const adKeywords = StringPref(
    'retrowave_audio_ad_keywords',
    defaultValue: 'werbung, anzeige, sponsor, sponsored, ad, ads, advertisement, promo, commercial',
  );

  static const skipBack = IntPref('retrowave_audio_skip_back', defaultValue: 10);
  static const skipForward = IntPref('retrowave_audio_skip_forward', defaultValue: 30);

  static const listenBrainzToken = StringPref('retrowave_listenbrainz_token');
  static const lastFmApiKey = StringPref('retrowave_lastfm_api_key');
  static const lastFmSecret = StringPref('retrowave_lastfm_secret');
  static const lastFmSession = StringPref('retrowave_lastfm_session');
  static const lastFmUser = StringPref('retrowave_lastfm_user');

  static SettingsService get _s => SettingsService.instance;

  static Map<String, AudioMode> get modes {
    final map = <String, AudioMode>{};
    for (final entry in _s.read(libraryModes)) {
      final i = entry.lastIndexOf('=');
      if (i <= 0) continue;
      final mode = AudioMode.values.where((m) => m.name == entry.substring(i + 1)).firstOrNull;
      if (mode != null) map[entry.substring(0, i)] = mode;
    }
    return map;
  }

  static AudioMode modeForLibrary(String? serverId, String? libraryId) =>
      serverId == null || libraryId == null ? AudioMode.music : modes['$serverId:$libraryId'] ?? AudioMode.music;

  static AudioMode modeFor(MediaItem? track) => modeForLibrary(track?.serverId, track?.libraryId);

  static Future<void> setMode(String serverId, String libraryId, AudioMode mode) async {
    final map = modes..remove('$serverId:$libraryId');
    if (mode != AudioMode.music) map['$serverId:$libraryId'] = mode;
    await _s.write(libraryModes, [for (final e in map.entries) '${e.key}=${e.value.name}']);
  }
}

/// Fork: order of the tracks in an album or folder.
enum AudioTrackSort { trackOrder, title, newest, oldest, longest, shortest }

/// Fork: order of an artist's albums (folders).
enum AudioFolderSort { standard, title, newest, oldest, recentlyAdded }

abstract final class AudioSorting {
  static const trackSortMusic = EnumPref<AudioTrackSort>(
    'retrowave_track_sort_music',
    values: AudioTrackSort.values,
    defaultValue: AudioTrackSort.trackOrder,
  );
  static const trackSortBooks = EnumPref<AudioTrackSort>(
    'retrowave_track_sort_books',
    values: AudioTrackSort.values,
    defaultValue: AudioTrackSort.trackOrder,
  );
  static const trackSortPodcasts = EnumPref<AudioTrackSort>(
    'retrowave_track_sort_podcasts',
    values: AudioTrackSort.values,
    defaultValue: AudioTrackSort.newest,
  );
  static const folderSort = EnumPref<AudioFolderSort>(
    'retrowave_folder_sort',
    values: AudioFolderSort.values,
    defaultValue: AudioFolderSort.standard,
  );

  /// Reverse order, per library type, and for albums.
  static const trackReverseMusic = BoolPref('retrowave_track_reverse_music');
  static const trackReverseBooks = BoolPref('retrowave_track_reverse_books');
  static const trackReversePodcasts = BoolPref('retrowave_track_reverse_podcasts');
  static const folderReverse = BoolPref('retrowave_folder_reverse');

  static BoolPref trackReverseFor(AudioMode mode) => switch (mode) {
    AudioMode.music => trackReverseMusic,
    AudioMode.podcast => trackReversePodcasts,
    _ => trackReverseBooks,
  };

  static EnumPref<AudioTrackSort> trackPrefFor(AudioMode mode) => switch (mode) {
    AudioMode.music => trackSortMusic,
    AudioMode.podcast => trackSortPodcasts,
    _ => trackSortBooks,
  };

  static int _date(MediaItem i) =>
      ReleaseDate.of(i)?.millisecondsSinceEpoch ??
      (i.year != null ? DateTime(i.year!).millisecondsSinceEpoch : (i.addedAt ?? 0) * 1000);

  /// [tracks] (in the server's order) sorted by [sort], reversed on request.
  static List<MediaItem> sortTracks(List<MediaItem> tracks, AudioTrackSort sort, {bool reverse = false}) {
    final sorted = _sortTracks(tracks, sort);
    return reverse ? sorted.reversed.toList() : sorted;
  }

  static List<MediaItem> _sortTracks(List<MediaItem> tracks, AudioTrackSort sort) {
    final list = [...tracks];
    int title(MediaItem a, MediaItem b) => (a.title ?? '').toLowerCase().compareTo((b.title ?? '').toLowerCase());
    switch (sort) {
      case AudioTrackSort.trackOrder:
        break;
      case AudioTrackSort.title:
        list.sort(title);
      case AudioTrackSort.newest:
        list.sort((a, b) => _date(b).compareTo(_date(a)));
      case AudioTrackSort.oldest:
        list.sort((a, b) => _date(a).compareTo(_date(b)));
      case AudioTrackSort.longest:
        list.sort((a, b) => (b.durationMs ?? 0).compareTo(a.durationMs ?? 0));
      case AudioTrackSort.shortest:
        list.sort((a, b) => (a.durationMs ?? 0).compareTo(b.durationMs ?? 0));
    }
    return list;
  }

  /// [albums] (in the server's order) sorted by [sort], reversed on request.
  static List<MediaItem> sortFolders(List<MediaItem> albums, AudioFolderSort sort, {bool reverse = false}) {
    final sorted = _sortFolders(albums, sort);
    return reverse ? sorted.reversed.toList() : sorted;
  }

  static List<MediaItem> _sortFolders(List<MediaItem> albums, AudioFolderSort sort) {
    final list = [...albums];
    switch (sort) {
      case AudioFolderSort.standard:
        break;
      case AudioFolderSort.title:
        list.sort((a, b) => (a.titleSort ?? a.title ?? '').toLowerCase().compareTo((b.titleSort ?? b.title ?? '').toLowerCase()));
      case AudioFolderSort.newest:
        list.sort((a, b) => _date(b).compareTo(_date(a)));
      case AudioFolderSort.oldest:
        list.sort((a, b) => _date(a).compareTo(_date(b)));
      case AudioFolderSort.recentlyAdded:
        list.sort((a, b) => (b.addedAt ?? 0).compareTo(a.addedAt ?? 0));
    }
    return list;
  }
}
