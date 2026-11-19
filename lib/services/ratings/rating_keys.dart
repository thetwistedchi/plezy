import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../settings_service.dart';
import '../youtube/secure_token_store.dart';

/// Whether a stored API key is known to work.
enum RatingKeyStatus { unknown, working, rejected }

/// The rating providers' API keys (MDBList, OMDb), encrypted on Windows like
/// the YouTube sign-in. Keys from older versions, kept in plain settings, are
/// moved over on first load.
class RatingKeys extends ChangeNotifier {
  RatingKeys._();
  static final instance = RatingKeys._();

  static const mdblist = 'mdblist';
  static const omdb = 'omdb';

  final _stores = {mdblist: SecureTokenStore('rating_key_mdblist'), omdb: SecureTokenStore('rating_key_omdb')};
  final Map<String, String> _keys = {};
  final Map<String, RatingKeyStatus> _status = {};
  Future<void>? _loading;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final settings = SettingsService.instanceOrNull;
    for (final MapEntry(key: name, value: store) in _stores.entries) {
      var key = '';
      try {
        key = await store.read() ?? '';
      } catch (_) {}
      final legacyPref = name == mdblist ? SettingsService.mdblistApiKey : SettingsService.omdbApiKey;
      final legacy = settings?.read(legacyPref).trim() ?? '';
      if (legacy.isNotEmpty) {
        if (key.isEmpty) {
          key = legacy;
          try {
            await store.write(key);
          } catch (_) {}
        }
        await settings?.write(legacyPref, '');
      }
      _keys[name] = key;
    }
    notifyListeners();
  }

  String key(String name) => _keys[name] ?? '';

  RatingKeyStatus status(String name) =>
      key(name).isEmpty ? RatingKeyStatus.unknown : (_status[name] ?? RatingKeyStatus.unknown);

  /// Stores [value] (empty removes it) and tests it with one request.
  Future<RatingKeyStatus> save(String name, String value, {http.Client? client}) async {
    await load();
    final key = value.trim();
    await _stores[name]!.write(key);
    _keys[name] = key;
    _status.remove(name);
    notifyListeners();
    if (key.isEmpty) return RatingKeyStatus.unknown;
    final result = await test(name, key, client: client);
    _status[name] = result;
    notifyListeners();
    return result;
  }

  /// A provider turned the key down while in use.
  void markRejected(String name) {
    if (_status[name] == RatingKeyStatus.rejected) return;
    _status[name] = RatingKeyStatus.rejected;
    notifyListeners();
  }

  void markWorking(String name) {
    if (_status[name] == RatingKeyStatus.working) return;
    _status[name] = RatingKeyStatus.working;
    notifyListeners();
  }

  /// The provider's own reason for the last failed test (e.g. OMDb's
  /// "Invalid API key!" or "Request limit reached!"), for the settings message.
  static final Map<String, String> lastTestError = {};

  /// One request for a well-known title (The Shawshank Redemption).
  static Future<RatingKeyStatus> test(String name, String key, {http.Client? client}) async {
    lastTestError.remove(name);
    final http.Client c = client ?? http.Client();
    try {
      final uri = name == mdblist
          ? Uri.https('api.mdblist.com', '/imdb/movie/tt0111161', {'apikey': key})
          : Uri.https('www.omdbapi.com', '/', {'i': 'tt0111161', 'apikey': key});
      final response = await c.get(uri).timeout(const Duration(seconds: 8));
      final error = _errorText(response.body);
      if (error != null) lastTestError[name] = error;
      // OMDb's daily limit also comes as 401: the key itself is fine.
      if (error != null && error.toLowerCase().contains('limit')) return RatingKeyStatus.unknown;
      if (response.statusCode == 401 || response.statusCode == 403) return RatingKeyStatus.rejected;
      if (response.statusCode != 200) return RatingKeyStatus.unknown;
      if (name == omdb && response.body.contains('"Response":"False"')) return RatingKeyStatus.rejected;
      return RatingKeyStatus.working;
    } catch (e) {
      lastTestError[name] = '$e';
      return RatingKeyStatus.unknown;
    } finally {
      if (client == null) c.close();
    }
  }

  static String? _errorText(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final error = json['Error'] ?? json['error'] ?? json['message'];
        if (error is String && error.trim().isNotEmpty) return error.trim();
      }
    } catch (_) {}
    return null;
  }
}
