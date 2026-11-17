import 'dart:convert';

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

    try {
      final raw = prefs.getString(_kProgress);
      final decoded = raw == null ? const <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
      _progress = {
        for (final e in decoded.entries)
          if (e.value is List && (e.value as List).length == 2)
            e.key: [((e.value as List)[0] as num).toDouble(), ((e.value as List)[1] as num).toDouble()],
      };
    } catch (_) {
      _progress = {};
    }

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

  Future<void> saveProgress(String videoId, double position, double duration) async {
    await load();
    _progress.remove(videoId);
    if (duration > 0 && position >= duration * 0.95) {
      _progress[videoId] = [duration, duration];
    } else {
      _progress[videoId] = [position, duration];
    }
    while (_progress.length > _maxProgress) {
      _progress.remove(_progress.keys.first);
    }
    await _prefs!.setString(_kProgress, jsonEncode(_progress));
    notifyListeners();
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
