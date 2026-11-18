import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as pathlib;
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_token_store.dart';

/// What happens when playback reaches a SponsorBlock segment.
enum SegmentMode { auto, button, off }

/// SponsorBlock categories offered in the settings, with their defaults.
const Map<String, SegmentMode> sponsorBlockDefaults = {
  'sponsor': SegmentMode.auto,
  'selfpromo': SegmentMode.button,
  'interaction': SegmentMode.button,
  'intro': SegmentMode.button,
  'outro': SegmentMode.button,
  'preview': SegmentMode.button,
  'filler': SegmentMode.off,
  'music_offtopic': SegmentMode.off,
};

/// Persisted YouTube settings and the small amount of local watch history the
/// subscriptions screen uses (which videos were opened, how often each channel
/// was opened). Kept apart from [SettingsService] so the fork's YouTube
/// feature stays self-contained. The Google refresh token is kept encrypted
/// in [SecureTokenStore], not in the preferences.
class YouTubeSettings extends ChangeNotifier {
  YouTubeSettings._();

  static final YouTubeSettings instance = YouTubeSettings._();

  static const _kClientId = 'youtube_client_id';
  static const _kClientSecret = 'youtube_client_secret';
  static const _kLegacyRefreshToken = 'youtube_refresh_token';
  static const _kAccountName = 'youtube_account_name';
  static const _kAccountChannelId = 'youtube_account_channel_id';
  static const _kGrantedScopes = 'youtube_granted_scopes';
  static const _kShowShorts = 'youtube_show_shorts';
  static const _kShowPremieres = 'youtube_show_premieres';
  static const _kRefreshMinutes = 'youtube_refresh_minutes';
  static const _kWatched = 'youtube_watched_ids';
  static const _kChannelOpens = 'youtube_channel_opens';
  static const _kBannerDismissed = 'youtube_hidden_banner_dismissed';
  static const _kSbEnabled = 'youtube_sponsorblock_enabled';
  static const _kSbModes = 'youtube_sponsorblock_modes';
  static const _kSbShowSegments = 'youtube_sponsorblock_show_segments';
  static const _kVolume = 'youtube_player_volume';
  static const _kCacheLimitMb = 'youtube_player_cache_mb';
  static const _kProgress = 'youtube_progress';
  static const _kQuality = 'youtube_preferred_quality';
  static const _kSpeed = 'youtube_playback_speed';
  static const _kCcEnabled = 'youtube_captions_enabled';
  static const _kCcLanguage = 'youtube_captions_language';
  static const _kCcAuto = 'youtube_captions_allow_auto';
  static const _kCcTranslate = 'youtube_captions_translate';
  static const _kAudioLanguage = 'youtube_audio_language';
  static const _kHiddenVideos = 'youtube_hidden_videos';
  static const _kMutedChannels = 'youtube_muted_channels';
  static const _kFavoriteChannels = 'youtube_favorite_channels';
  static const _kNotify = 'youtube_notify_favorites';
  static const _kDeArrowTitles = 'youtube_dearrow_titles';
  static const _kDeArrowThumbs = 'youtube_dearrow_thumbnails';
  static const _kRyd = 'youtube_return_dislikes';
  static const _kHiddenButtons = 'youtube_hidden_player_buttons';
  static const _kChannelStrip = 'youtube_show_channel_strip';

  /// Player controls that can be hidden in the settings, in display order.
  static const List<String> playerButtons = [
    'watchlist',
    'comments',
    'channelVideos',
    'openChannel',
    'share',
    'openOnYouTube',
    'rating',
    'back10',
    'forward10',
    'previousNext',
    'highlight',
    'volume',
    'quality',
    'speed',
    'audio',
    'captions',
    'sleep',
    'chapters',
    'fullscreen',
  ];

  static const List<double> speedChoices = [0.25, 0.5, 0.75, 1.0, 1.1, 1.2, 1.25, 1.5, 1.75, 2.0];
  static const int _maxProgress = 2000;

  static const int defaultCacheLimitMb = 300;
  static const int minCacheLimitMb = 50;
  static const int maxCacheLimitMb = 20000;

  static const int _maxWatched = 3000;
  static const List<int> refreshChoices = [15, 30, 60];

  final SecureTokenStore _tokenStore = SecureTokenStore('youtube_refresh_token');

  SharedPreferences? _prefs;
  Future<void>? _loading;
  String _refreshToken = '';
  Set<String>? _watched;
  Map<String, int>? _channelOpens;
  Map<String, SegmentMode> _sbModes = Map.of(sponsorBlockDefaults);

  Set<String> _hiddenVideos = {};

  /// channelId → title, for the settings list.
  Map<String, String> _mutedChannels = {};
  Map<String, String> _favoriteChannels = {};

  /// videoId → [position, duration] in seconds, most recent last.
  Map<String, List<double>> _progress = {};

  bool get isLoaded => _prefs != null;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _watched = (prefs.getStringList(_kWatched) ?? const <String>[]).toSet();
    try {
      final raw = prefs.getString(_kChannelOpens);
      final decoded = raw == null ? const <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
      _channelOpens = {for (final e in decoded.entries) e.key: (e.value as num).toInt()};
    } catch (_) {
      _channelOpens = {};
    }
    try {
      final raw = prefs.getString(_kSbModes);
      final decoded = raw == null ? const <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
      for (final e in decoded.entries) {
        final mode = SegmentMode.values.where((m) => m.name == e.value).firstOrNull;
        if (mode != null && sponsorBlockDefaults.containsKey(e.key)) _sbModes[e.key] = mode;
      }
    } catch (_) {}

    _progress = await _readProgress(prefs);

    _hiddenVideos = (prefs.getStringList(_kHiddenVideos) ?? const <String>[]).toSet();
    _mutedChannels = _readMap(prefs.getString(_kMutedChannels));
    _favoriteChannels = _readMap(prefs.getString(_kFavoriteChannels));

    // Move a refresh token from the old unencrypted preference.
    final legacy = prefs.getString(_kLegacyRefreshToken);
    if (legacy != null && legacy.isNotEmpty) {
      try {
        await _tokenStore.write(legacy);
        await prefs.remove(_kLegacyRefreshToken);
      } catch (_) {}
      _refreshToken = legacy;
    } else {
      _refreshToken = await _tokenStore.read() ?? '';
    }
    _prefs = prefs;
    notifyListeners();
  }

  static Map<String, String> _readMap(String? raw) {
    try {
      final decoded = raw == null ? const <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in decoded.entries) e.key: e.value.toString()};
    } catch (_) {
      return {};
    }
  }

  bool showButton(String id) => !(_prefs?.getStringList(_kHiddenButtons) ?? const <String>[]).contains(id);

  Future<void> setShowButton(String id, bool show) async {
    await load();
    final hidden = (_prefs!.getStringList(_kHiddenButtons) ?? const <String>[]).toSet();
    if (show) {
      hidden.remove(id);
    } else {
      hidden.add(id);
    }
    await _prefs!.setStringList(_kHiddenButtons, hidden.toList());
    notifyListeners();
  }

  /// The "More from this channel" row while paused and at the end.
  bool get showChannelStrip => _prefs?.getBool(_kChannelStrip) ?? true;
  Future<void> setShowChannelStrip(bool v) => _setBool(_kChannelStrip, v);

  bool get deArrowTitles => _prefs?.getBool(_kDeArrowTitles) ?? true;
  bool get deArrowThumbnails => _prefs?.getBool(_kDeArrowThumbs) ?? true;
  bool get returnDislikes => _prefs?.getBool(_kRyd) ?? true;
  bool get notifyFavorites => _prefs?.getBool(_kNotify) ?? true;

  Future<void> setDeArrowTitles(bool v) => _setBool(_kDeArrowTitles, v);
  Future<void> setDeArrowThumbnails(bool v) => _setBool(_kDeArrowThumbs, v);
  Future<void> setReturnDislikes(bool v) => _setBool(_kRyd, v);
  Future<void> setNotifyFavorites(bool v) => _setBool(_kNotify, v);

  bool isHidden(String videoId) => _hiddenVideos.contains(videoId);
  bool isMuted(String channelId) => _mutedChannels.containsKey(channelId);
  bool isFavorite(String channelId) => _favoriteChannels.containsKey(channelId);
  Map<String, String> get mutedChannels => Map.unmodifiable(_mutedChannels);
  Map<String, String> get favoriteChannels => Map.unmodifiable(_favoriteChannels);
  int get hiddenVideoCount => _hiddenVideos.length;

  Future<void> hideVideo(String videoId) async {
    await load();
    _hiddenVideos.add(videoId);
    if (_hiddenVideos.length > 5000) _hiddenVideos = _hiddenVideos.skip(_hiddenVideos.length - 5000).toSet();
    await _prefs!.setStringList(_kHiddenVideos, _hiddenVideos.toList());
    notifyListeners();
  }

  Future<void> unhideAllVideos() async {
    await load();
    _hiddenVideos.clear();
    await _prefs!.setStringList(_kHiddenVideos, const []);
    notifyListeners();
  }

  Future<void> setMuted(String channelId, String title, bool muted) async {
    await load();
    if (muted) {
      _mutedChannels[channelId] = title;
    } else {
      _mutedChannels.remove(channelId);
    }
    await _prefs!.setString(_kMutedChannels, jsonEncode(_mutedChannels));
    notifyListeners();
  }

  Future<void> setFavorite(String channelId, String title, bool favorite) async {
    await load();
    if (favorite) {
      _favoriteChannels[channelId] = title;
    } else {
      _favoriteChannels.remove(channelId);
    }
    await _prefs!.setString(_kFavoriteChannels, jsonEncode(_favoriteChannels));
    notifyListeners();
  }

  String get clientId => _prefs?.getString(_kClientId) ?? '';
  String get clientSecret => _prefs?.getString(_kClientSecret) ?? '';
  String get refreshToken => _refreshToken;
  String get accountName => _prefs?.getString(_kAccountName) ?? '';
  String get accountChannelId => _prefs?.getString(_kAccountChannelId) ?? '';
  String get grantedScopes => _prefs?.getString(_kGrantedScopes) ?? '';
  bool get showShorts => _prefs?.getBool(_kShowShorts) ?? false;
  bool get showPremieres => _prefs?.getBool(_kShowPremieres) ?? false;
  int get refreshMinutes => _prefs?.getInt(_kRefreshMinutes) ?? 30;
  bool get hiddenBannerDismissed => _prefs?.getBool(_kBannerDismissed) ?? false;
  bool get sponsorBlockEnabled => _prefs?.getBool(_kSbEnabled) ?? true;
  bool get showSegmentsOnTimeline => _prefs?.getBool(_kSbShowSegments) ?? true;
  int get playerCacheLimitMb => _prefs?.getInt(_kCacheLimitMb) ?? defaultCacheLimitMb;
  /// YouTube quality id (hd1080, hd720, …) or 'auto'.
  String get preferredQuality => _prefs?.getString(_kQuality) ?? 'auto';
  /// Speed new videos start at; the last speed picked in the player.
  double get playbackSpeed => _prefs?.getDouble(_kSpeed) ?? 1.0;
  bool get captionsEnabled => _prefs?.getBool(_kCcEnabled) ?? false;

  /// Language code of the preferred captions, e.g. de or en.
  String get captionsLanguage => _prefs?.getString(_kCcLanguage) ?? 'en';

  /// Use auto-generated captions when there are no creator captions.
  bool get captionsAllowAuto => _prefs?.getBool(_kCcAuto) ?? true;

  /// Auto-translate other captions into [captionsLanguage] as a last resort.
  bool get captionsTranslate => _prefs?.getBool(_kCcTranslate) ?? false;

  /// 'original' (default: the creator's own audio, no AI dubs) or a language code.
  String get audioLanguage => _prefs?.getString(_kAudioLanguage) ?? 'original';

  int get playerVolume => _prefs?.getInt(_kVolume) ?? 100;

  SegmentMode segmentMode(String category) => _sbModes[category] ?? SegmentMode.off;

  bool get hasCredentials => clientId.isNotEmpty;
  bool get isSignedIn => _refreshToken.isNotEmpty;

  /// Whether the sign-in includes write access (rating, comments).
  bool get canWrite => grantedScopes.contains('youtube.force-ssl');

  Future<void> _setString(String key, String value) async {
    await load();
    if (value.isEmpty) {
      await _prefs!.remove(key);
    } else {
      await _prefs!.setString(key, value);
    }
    notifyListeners();
  }

  Future<void> _setBool(String key, bool value) async {
    await load();
    await _prefs!.setBool(key, value);
    notifyListeners();
  }

  Future<void> setClientId(String value) => _setString(_kClientId, value.trim());
  Future<void> setClientSecret(String value) => _setString(_kClientSecret, value.trim());
  Future<void> setAccountName(String value) => _setString(_kAccountName, value);
  Future<void> setAccountChannelId(String value) => _setString(_kAccountChannelId, value);
  Future<void> setGrantedScopes(String value) => _setString(_kGrantedScopes, value);

  Future<void> setRefreshToken(String value) async {
    await load();
    await _tokenStore.write(value);
    _refreshToken = value;
    notifyListeners();
  }

  Future<void> setShowShorts(bool value) => _setBool(_kShowShorts, value);
  Future<void> setShowPremieres(bool value) => _setBool(_kShowPremieres, value);
  Future<void> dismissHiddenBanner() => _setBool(_kBannerDismissed, true);
  Future<void> setSponsorBlockEnabled(bool value) => _setBool(_kSbEnabled, value);
  Future<void> setShowSegmentsOnTimeline(bool value) => _setBool(_kSbShowSegments, value);

  Future<void> setSegmentMode(String category, SegmentMode mode) async {
    await load();
    _sbModes[category] = mode;
    await _prefs!.setString(_kSbModes, jsonEncode({for (final e in _sbModes.entries) e.key: e.value.name}));
    notifyListeners();
  }

  Future<void> setPlayerCacheLimitMb(int value) async {
    await load();
    await _prefs!.setInt(_kCacheLimitMb, value.clamp(minCacheLimitMb, maxCacheLimitMb));
    notifyListeners();
  }

  Future<void> setPreferredQuality(String value) async {
    await load();
    await _prefs!.setString(_kQuality, value);
  }

  Future<void> setPlaybackSpeed(double value) async {
    await load();
    await _prefs!.setDouble(_kSpeed, value);
    notifyListeners();
  }

  Future<void> setCaptions({bool? enabled, String? language, bool? allowAuto, bool? translate}) async {
    await load();
    if (enabled != null) await _prefs!.setBool(_kCcEnabled, enabled);
    if (language != null) await _prefs!.setString(_kCcLanguage, language);
    if (allowAuto != null) await _prefs!.setBool(_kCcAuto, allowAuto);
    if (translate != null) await _prefs!.setBool(_kCcTranslate, translate);
    notifyListeners();
  }

  Future<void> setAudioLanguage(String value) async {
    await load();
    await _prefs!.setString(_kAudioLanguage, value);
    notifyListeners();
  }

  Future<void> setPlayerVolume(int value) async {
    await load();
    await _prefs!.setInt(_kVolume, value.clamp(0, 100));
  }

  Future<void> setRefreshMinutes(int value) async {
    await load();
    await _prefs!.setInt(_kRefreshMinutes, value);
    notifyListeners();
  }

  /// Where playback of [videoId] stopped, if it is worth resuming: more than
  /// 10 seconds in and not within the last 30 seconds.
  double? resumePosition(String videoId) {
    final p = _progress[videoId];
    if (p == null) return null;
    final position = p[0];
    final duration = p[1];
    if (position < 10) return null;
    if (duration > 0 && position > duration - 30) return null;
    return position;
  }

  /// Fraction of [videoId] watched, for the progress bar on its thumbnail.
  double? progressFraction(String videoId) {
    final p = _progress[videoId];
    if (p == null || p[1] <= 0) return null;
    return (p[0] / p[1]).clamp(0.0, 1.0);
  }

  /// Records where [videoId] is. Kept in memory and written to its own file
  /// at most every 30 s (or right away with [flush]: pause, video change,
  /// close), so playback does not rewrite the whole settings file every few
  /// seconds. Listeners hear about it when it is written, or at once when the
  /// video becomes watched.
  Future<void> saveProgress(String videoId, double position, double duration, {bool flush = false}) async {
    await load();
    final wasWatched = (progressFraction(videoId) ?? 0) >= 0.95;
    _progress.remove(videoId);
    if (duration > 0 && position >= duration * 0.95) {
      _progress[videoId] = [duration, duration];
    } else {
      _progress[videoId] = [position, duration];
    }
    while (_progress.length > _maxProgress) {
      _progress.remove(_progress.keys.first);
    }
    final nowWatched = (progressFraction(videoId) ?? 0) >= 0.95;
    _progressDirty = true;
    if (flush || nowWatched != wasWatched) {
      await flushProgress();
    } else {
      _progressTimer ??= Timer(const Duration(seconds: 30), () => unawaited(flushProgress()));
    }
  }

  bool _progressDirty = false;
  Timer? _progressTimer;

  /// Writes pending progress to disk and tells listeners.
  Future<void> flushProgress() async {
    _progressTimer?.cancel();
    _progressTimer = null;
    if (!_progressDirty) return;
    _progressDirty = false;
    notifyListeners();
    try {
      final file = await _progressFile();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_progress), flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      _progressDirty = true;
      debugPrint('YouTube progress not saved: $e');
    }
  }

  static Future<File> _progressFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(pathlib.join(dir.path, 'youtube_progress.json'));
  }

  static Map<String, List<double>> _decodeProgress(String? raw) {
    try {
      final decoded = raw == null ? const <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in decoded.entries)
          if (e.value is List && (e.value as List).length == 2)
            e.key: [((e.value as List)[0] as num).toDouble(), ((e.value as List)[1] as num).toDouble()],
      };
    } catch (_) {
      return {};
    }
  }

  /// From its own file; moves an older copy out of the settings file.
  static Future<Map<String, List<double>>> _readProgress(SharedPreferences prefs) async {
    try {
      final file = await _progressFile();
      if (await file.exists()) return _decodeProgress(await file.readAsString());
      final legacy = prefs.getString(_kProgress);
      if (legacy == null) return {};
      final progress = _decodeProgress(legacy);
      await file.writeAsString(jsonEncode(progress), flush: true);
      await prefs.remove(_kProgress);
      return progress;
    } catch (_) {
      return _decodeProgress(prefs.getString(_kProgress));
    }
  }

  bool isWatched(String videoId) => _watched?.contains(videoId) ?? false;

  int channelOpens(String channelId) => _channelOpens?[channelId] ?? 0;

  /// Records that [videoId] from [channelId] was opened.
  Future<void> markOpened(String videoId, String channelId) async {
    await load();
    final watched = _watched!;
    if (watched.add(videoId)) {
      if (watched.length > _maxWatched) {
        final trimmed = watched.toList().sublist(watched.length - _maxWatched);
        _watched = trimmed.toSet();
      }
      await _prefs!.setStringList(_kWatched, _watched!.toList());
      final opens = _channelOpens!;
      opens[channelId] = (opens[channelId] ?? 0) + 1;
      await _prefs!.setString(_kChannelOpens, jsonEncode(opens));
    }
    notifyListeners();
  }
}
