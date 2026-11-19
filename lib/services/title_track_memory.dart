import 'dart:async';
import 'dart:convert';

import '../media/ids.dart';
import '../media/media_item.dart';
import '../mpv/mpv.dart';
import '../utils/global_key_utils.dart';
import 'settings_service.dart';
import 'subtitle_preference.dart';

/// Per-title memory of the audio track, subtitle track and zoom mode the
/// viewer last picked. A series shares one entry across its episodes; a
/// movie has its own. Tracks are stored by their language/title/codec, so
/// they also match the matching track of another episode's file.
abstract final class TitleTrackMemory {
  static const _key = 'retro_title_track_memory';
  static const _maxEntries = 600;

  static Map<String, dynamic>? _cache;

  static bool get _enabled => SettingsService.instanceOrNull?.read(SettingsService.rememberTitleTracks) ?? false;

  static String? _titleKey(MediaItem? item) {
    if (item == null) return null;
    final serverId = serverIdOrNull(item.serverId);
    if (serverId == null) return null;
    return buildGlobalKey(serverId, item.grandparentId ?? item.id);
  }

  static Map<String, dynamic> _entries() {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = SettingsService.instanceOrNull?.prefs.getString(_key);
    Map<String, dynamic> parsed = {};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is Map<String, dynamic>) parsed = decoded;
      } catch (_) {}
    }
    return _cache = parsed;
  }

  static Map<String, dynamic>? _entryFor(MediaItem? item) {
    if (!_enabled) return null;
    final key = _titleKey(item);
    if (key == null) return null;
    final entry = _entries()[key];
    return entry is Map<String, dynamic> ? entry : null;
  }

  static void _update(MediaItem? item, void Function(Map<String, dynamic> entry) change) {
    if (!_enabled) return;
    final key = _titleKey(item);
    if (key == null) return;
    final entries = _entries();
    final entry = Map<String, dynamic>.from(entries[key] as Map? ?? const {});
    change(entry);
    entry['t'] = DateTime.now().millisecondsSinceEpoch;
    entries[key] = entry;
    if (entries.length > _maxEntries) {
      final sorted = entries.entries.toList()
        ..sort((a, b) => ((b.value as Map)['t'] as int? ?? 0).compareTo((a.value as Map)['t'] as int? ?? 0));
      entries
        ..clear()
        ..addEntries(sorted.take(_maxEntries));
    }
    unawaited(_save());
  }

  static Future<void> _save() async {
    final settings = await SettingsService.getInstance();
    await settings.prefs.setString(_key, json.encode(_entries()));
  }

  // ── Audio ──

  static AudioTrack? audioFor(MediaItem? item) {
    final a = _entryFor(item)?['audio'];
    if (a is! Map) return null;
    return AudioTrack(
      id: a['id'] as String? ?? '',
      title: a['title'] as String?,
      language: a['lang'] as String?,
      codec: a['codec'] as String?,
      channels: (a['ch'] as num?)?.toInt(),
    );
  }

  static void saveAudio(MediaItem? item, AudioTrack track) {
    if (track.id == AudioTrack.auto.id || track.id == AudioTrack.off.id) return;
    _update(item, (entry) {
      entry['audio'] = {
        'id': track.id,
        'title': ?track.title,
        'lang': ?track.language,
        'codec': ?track.codec,
        'ch': ?track.channels,
      };
    });
  }

  // ── Subtitles ──

  /// A semantic preference (or off), valid across episodes.
  static SubtitlePreference? subtitleFor(MediaItem? item) {
    final s = _entryFor(item)?['sub'];
    if (s == 'off') return const SubtitlePreference.off();
    if (s is! Map) return null;
    return SubtitlePreference.intent(
      SubtitleIntent(
        language: s['lang'] as String?,
        forced: s['forced'] == true,
        title: s['title'] as String?,
        codec: s['codec'] as String?,
        isExternal: s['ext'] == true,
      ),
    );
  }

  static void saveSubtitle(MediaItem? item, SubtitleTrack track) {
    if (track.id == SubtitleTrack.off.id) {
      _update(item, (entry) => entry['sub'] = 'off');
      return;
    }
    final intent = SubtitleIntent.fromTrack(track);
    if (intent == null) return;
    _update(item, (entry) {
      entry['sub'] = {
        'lang': ?intent.language,
        'forced': intent.forced,
        'title': ?intent.title,
        'codec': ?intent.codec,
        'ext': intent.isExternal,
      };
    });
  }

  // ── Zoom (box fit mode) ──

  static int? zoomFor(MediaItem? item) => (_entryFor(item)?['zoom'] as num?)?.toInt();

  static void saveZoom(MediaItem? item, int mode) => _update(item, (entry) => entry['zoom'] = mode);
}
