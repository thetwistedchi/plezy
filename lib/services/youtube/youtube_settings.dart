import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted YouTube settings and the small amount of local watch history the
/// subscriptions screen uses (which videos were opened, how often each channel
/// was opened). Kept apart from [SettingsService] so the fork's YouTube
/// feature stays self-contained.
class YouTubeSettings extends ChangeNotifier {
  YouTubeSettings._();

  static final YouTubeSettings instance = YouTubeSettings._();

  static const _kClientId = 'youtube_client_id';
  static const _kClientSecret = 'youtube_client_secret';
  static const _kRefreshToken = 'youtube_refresh_token';
  static const _kAccountName = 'youtube_account_name';
  static const _kShowShorts = 'youtube_show_shorts';
  static const _kShowPremieres = 'youtube_show_premieres';
  static const _kRefreshMinutes = 'youtube_refresh_minutes';
  static const _kWatched = 'youtube_watched_ids';
  static const _kChannelOpens = 'youtube_channel_opens';

  static const int _maxWatched = 3000;
  static const List<int> refreshChoices = [15, 30, 60];

  SharedPreferences? _prefs;
  Set<String>? _watched;
  Map<String, int>? _channelOpens;

  bool get isLoaded => _prefs != null;

  Future<void> load() async {
    if (_prefs != null) return;
    _prefs = await SharedPreferences.getInstance();
    _watched = (_prefs!.getStringList(_kWatched) ?? const <String>[]).toSet();
    try {
      final raw = _prefs!.getString(_kChannelOpens);
      final decoded = raw == null ? const <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
      _channelOpens = {for (final e in decoded.entries) e.key: (e.value as num).toInt()};
    } catch (_) {
      _channelOpens = {};
    }
    notifyListeners();
  }

  String get clientId => _prefs?.getString(_kClientId) ?? '';
  String get clientSecret => _prefs?.getString(_kClientSecret) ?? '';
  String get refreshToken => _prefs?.getString(_kRefreshToken) ?? '';
  String get accountName => _prefs?.getString(_kAccountName) ?? '';
  bool get showShorts => _prefs?.getBool(_kShowShorts) ?? false;
  bool get showPremieres => _prefs?.getBool(_kShowPremieres) ?? false;
  int get refreshMinutes => _prefs?.getInt(_kRefreshMinutes) ?? 30;

  bool get hasCredentials => clientId.isNotEmpty;
  bool get isSignedIn => refreshToken.isNotEmpty;

  Future<void> _setString(String key, String value) async {
    await load();
    if (value.isEmpty) {
      await _prefs!.remove(key);
    } else {
      await _prefs!.setString(key, value);
    }
    notifyListeners();
  }

  Future<void> setClientId(String value) => _setString(_kClientId, value.trim());
  Future<void> setClientSecret(String value) => _setString(_kClientSecret, value.trim());
  Future<void> setRefreshToken(String value) => _setString(_kRefreshToken, value);
  Future<void> setAccountName(String value) => _setString(_kAccountName, value);

  Future<void> setShowShorts(bool value) async {
    await load();
    await _prefs!.setBool(_kShowShorts, value);
    notifyListeners();
  }

  Future<void> setShowPremieres(bool value) async {
    await load();
    await _prefs!.setBool(_kShowPremieres, value);
    notifyListeners();
  }

  Future<void> setRefreshMinutes(int value) async {
    await load();
    await _prefs!.setInt(_kRefreshMinutes, value);
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
