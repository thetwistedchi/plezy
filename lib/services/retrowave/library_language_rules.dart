import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/global_key_utils.dart';
import '../../media/ids.dart';

/// Fork: audio and subtitle languages per library, e.g. Japanese audio with
/// German subtitles for an anime library. They take the place of the
/// profile's languages for titles from that library. Kept in memory after
/// [load] so track selection can read them synchronously.
class LibraryLanguageRules {
  LibraryLanguageRules._();

  static const _key = 'retrowave_library_languages';
  static Map<String, ({String? audio, String? subtitle})> _rules = {};
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _rules = _decode(prefs.getString(_key));
    _loaded = true;
  }

  static Map<String, ({String? audio, String? subtitle})> _decode(String? raw) {
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          if (e.value is Map)
            e.key: (
              audio: _clean((e.value as Map)['audio']),
              subtitle: _clean((e.value as Map)['subtitle']),
            ),
      };
    } catch (_) {
      return {};
    }
  }

  static String? _clean(Object? v) => v is String && v.trim().isNotEmpty ? v.trim().toLowerCase() : null;

  /// The rule of the library with [libraryGlobalKey], if any.
  static ({String? audio, String? subtitle})? forLibrary(String libraryGlobalKey) => _rules[libraryGlobalKey];

  /// The rule for an item's library, if any.
  static ({String? audio, String? subtitle})? forItem({String? serverId, String? libraryId}) {
    if (libraryId == null) return null;
    final key = serverId != null ? buildGlobalKey(ServerId(serverId), libraryId) : libraryId;
    return _rules[key];
  }

  static Future<void> set(String libraryGlobalKey, {String? audio, String? subtitle}) async {
    await load();
    final a = _clean(audio);
    final s = _clean(subtitle);
    if (a == null && s == null) {
      _rules.remove(libraryGlobalKey);
    } else {
      _rules[libraryGlobalKey] = (audio: a, subtitle: s);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        for (final e in _rules.entries) e.key: {'audio': e.value.audio, 'subtitle': e.value.subtitle},
      }),
    );
  }
}
