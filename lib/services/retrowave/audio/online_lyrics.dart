import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../media/lyrics.dart';
import '../../../media/media_item.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/lrc_parser.dart';
import '../../settings_service.dart';
import 'audio_settings.dart';

/// Fork: lyrics from LRCLIB (lrclib.net, free, no account) for tracks the
/// server has none for. Timed lyrics are preferred over plain text. Results
/// and misses are kept for the session.
class OnlineLyrics {
  OnlineLyrics._();
  static final instance = OnlineLyrics._();

  static const _userAgent = 'PlezyRetrowave (https://github.com/thetwistedchi/plezy)';
  final _cache = <String, Lyrics?>{};

  Future<Lyrics?> forTrack(MediaItem track) async {
    // Off in the settings, or spoken audio (no lyrics to find).
    if (!SettingsService.instance.read(AudioSettings.onlineLyrics)) return null;
    if (AudioSettings.modeFor(track).isSpoken) return null;
    final title = track.title?.trim() ?? '';
    final artist = (track.trackArtistTitle ?? track.grandparentTitle ?? '').trim();
    if (title.isEmpty || artist.isEmpty) return null;
    final key = '${artist.toLowerCase()}|${title.toLowerCase()}';
    if (_cache.containsKey(key)) return _cache[key];
    Lyrics? result;
    try {
      result = await _get(track, title, artist) ?? await _search(track, title, artist);
    } catch (e) {
      appLogger.d('LRCLIB lookup failed for $artist - $title', error: e);
      return null; // not cached: a network error may pass
    }
    _cache[key] = result;
    return result;
  }

  /// Exact match on artist, title, album and duration (±2 s on LRCLIB).
  Future<Lyrics?> _get(MediaItem track, String title, String artist) async {
    final params = {
      'artist_name': artist,
      'track_name': title,
      if ((track.parentTitle ?? '').isNotEmpty) 'album_name': track.parentTitle!,
      if (track.durationMs != null) 'duration': '${(track.durationMs! / 1000).round()}',
    };
    final response = await http
        .get(Uri.https('lrclib.net', '/api/get', params), headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    return _fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  /// Search by artist and title; the closest duration wins.
  Future<Lyrics?> _search(MediaItem track, String title, String artist) async {
    final response = await http
        .get(
          Uri.https('lrclib.net', '/api/search', {'artist_name': artist, 'track_name': title}),
          headers: {'User-Agent': _userAgent},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final list = jsonDecode(utf8.decode(response.bodyBytes));
    if (list is! List || list.isEmpty) return null;
    final want = (track.durationMs ?? 0) / 1000;
    final candidates = list.whereType<Map>().where((m) => m['instrumental'] != true).toList()
      ..sort((a, b) {
        double gap(Map m) => want <= 0 ? 0 : (((m['duration'] as num?) ?? 0) - want).abs().toDouble();
        final byGap = gap(a).compareTo(gap(b));
        if (byGap != 0) return byGap;
        // Timed lyrics first.
        return (b['syncedLyrics'] != null ? 1 : 0).compareTo(a['syncedLyrics'] != null ? 1 : 0);
      });
    for (final m in candidates) {
      if (want > 0 && (((m['duration'] as num?) ?? 0) - want).abs() > 10) break;
      final lyrics = _fromJson(m);
      if (lyrics != null) return lyrics;
    }
    return null;
  }

  Lyrics? _fromJson(Object? json) {
    if (json is! Map) return null;
    final synced = json['syncedLyrics'] as String?;
    if (synced != null && synced.trim().isNotEmpty) {
      final parsed = parseLrc(synced);
      if (parsed != null && !parsed.isEmpty) return parsed;
    }
    final plain = json['plainLyrics'] as String?;
    if (plain == null || plain.trim().isEmpty) return null;
    return Lyrics(synced: false, lines: [for (final line in plain.split('\n')) LyricLine(text: line.trimRight())]);
  }
}
