import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as pathlib;
import 'package:path_provider/path_provider.dart';

import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../media/media_stream.dart';
import '../utils/app_logger.dart';
import '../utils/codec_utils.dart';
import '../utils/platform_detector.dart';
import 'device_performance.dart';
import 'plex_client.dart';

/// Quality, audio format and audio languages of a title, for the pills
/// under a poster.
@immutable
class PosterInfo {
  const PosterInfo({
    this.quality,
    this.hdr = false,
    this.languages = const [],
    this.audioCodec,
    this.audioChannels,
    this.audioKnown = true,
  });

  /// `4K`, `1080p`, `720p` or `SD`.
  final String? quality;
  final bool hdr;

  /// Audio languages as two-letter codes (`DE`, `EN`), in stream order.
  final List<String> languages;

  /// Fork: format of the default audio track, e.g. `TrueHD Atmos`,
  /// `DTS-HD MA`, `E-AC3`, and its layout (`7.1`, `5.1`, `Stereo`).
  final String? audioCodec;
  final String? audioChannels;

  /// False for entries cached before the audio format was stored: they are
  /// shown as they are and looked up again.
  final bool audioKnown;

  bool get isEmpty => quality == null && !hdr && languages.isEmpty && audioCodec == null;

  /// From an item with its versions (and, for languages, its streams).
  static PosterInfo of(MediaItem item) {
    final versions = item.mediaVersions ?? const [];
    if (versions.isEmpty) return const PosterInfo();
    final version = versions.first;
    final streams = [for (final part in version.parts) ...part.streams];
    final languages = <String>[];
    final audio = <MediaStream>[];
    for (final stream in streams) {
      if (stream.kind != MediaStreamKind.audio) continue;
      audio.add(stream);
      final code = shortLanguage(stream.languageCode ?? stream.language);
      if (code != null && !languages.contains(code)) languages.add(code);
    }
    // The track that plays by default: the server's pick, else the
    // container's default, else the first.
    final main = audio.where((s) => s.selected).firstOrNull ?? audio.where((s) => s.isDefault).firstOrNull ?? audio.firstOrNull;
    return PosterInfo(
      quality: _quality(version.videoResolution, version.height),
      hdr: streams.any((s) => s.kind == MediaStreamKind.video && s.hdr),
      languages: languages,
      audioCodec: main == null ? null : _audioCodec(main),
      audioChannels: CodecUtils.formatAudioChannels(main?.channels),
    );
  }

  /// `TrueHD Atmos`, `DTS-HD MA`, `DTS:X`, `E-AC3`, `AAC`. The DTS variant and
  /// Atmos only show in the track's names, not its codec.
  static String? _audioCodec(MediaStream stream) {
    final codec = stream.codec;
    if (codec == null || codec.isEmpty) return null;
    final names = '${stream.displayTitle ?? ''} ${stream.title ?? ''}'.toUpperCase();
    var name = CodecUtils.formatAudioCodec(codec);
    if (name.startsWith('DTS')) {
      for (final variant in const ['DTS:X', 'DTS-HD MA', 'DTS-HD HRA', 'DTS-ES']) {
        if (names.contains(variant)) {
          name = variant;
          break;
        }
      }
    }
    if (names.contains('ATMOS') && (name == 'TrueHD' || name == 'E-AC3')) name = '$name Atmos';
    return name;
  }

  static String? _quality(String? resolution, int? height) {
    switch (resolution?.toLowerCase()) {
      case '4k':
        return '4K';
      case '1080':
        return '1080p';
      case '720':
        return '720p';
      case 'sd' || '480' || '576':
        return 'SD';
    }
    if (height == null) return null;
    if (height >= 1600) return '4K';
    if (height >= 900) return '1080p';
    if (height >= 650) return '720p';
    return 'SD';
  }

  static const _iso3 = {
    'ger': 'DE', 'deu': 'DE', 'eng': 'EN', 'fre': 'FR', 'fra': 'FR', 'spa': 'ES', 'ita': 'IT',
    'jpn': 'JA', 'kor': 'KO', 'chi': 'ZH', 'zho': 'ZH', 'rus': 'RU', 'por': 'PT', 'dut': 'NL',
    'nld': 'NL', 'swe': 'SV', 'dan': 'DA', 'nor': 'NO', 'nob': 'NO', 'fin': 'FI', 'pol': 'PL',
    'tur': 'TR', 'cze': 'CS', 'ces': 'CS', 'hun': 'HU', 'gre': 'EL', 'ell': 'EL', 'hin': 'HI',
    'ara': 'AR', 'heb': 'HE', 'tha': 'TH', 'ukr': 'UK',
  };

  /// `ger` / `deu` / `de` / `German` → `DE`. Null for unknown or undefined.
  static String? shortLanguage(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty || value == 'und' || value == 'zxx' || value == 'mis') return null;
    if (_iso3[value] case final code?) return code;
    if (value.length == 2) return value.toUpperCase();
    if (value.length == 3) return value.substring(0, 2).toUpperCase();
    return switch (value) {
      'german' || 'deutsch' => 'DE',
      'english' => 'EN',
      'french' => 'FR',
      'spanish' => 'ES',
      'italian' => 'IT',
      'japanese' => 'JA',
      _ => value.substring(0, 2).toUpperCase(),
    };
  }

  List<Object?> toJson() => [quality, hdr ? 1 : 0, languages, audioCodec, audioChannels];

  static PosterInfo? fromJson(Object? json) {
    // Three fields: cached before the audio format was stored.
    if (json is! List || (json.length != 3 && json.length != 5)) return null;
    return PosterInfo(
      quality: json[0] as String?,
      hdr: json[1] == 1,
      languages: [for (final l in (json[2] as List? ?? const [])) '$l'],
      audioCodec: json.length == 5 ? json[3] as String? : null,
      audioChannels: json.length == 5 ? json[4] as String? : null,
      audioKnown: json.length == 5,
    );
  }
}

/// [PosterInfo] per title, kept on disk. Library lists carry the quality of
/// movies and episodes but not their languages, and nothing for series, so a
/// title is asked from its own Plex server once (a series through its first
/// episode): a few at a time, newest request first, kept for a month.
class PosterInfoCache extends ChangeNotifier {
  PosterInfoCache._();
  static final instance = PosterInfoCache._();

  static const _ttl = Duration(days: 30);
  static const _maxEntries = 8000;
  /// One at a time on TV boxes, whose CPU also decodes every response.
  static int get _maxConcurrent => PlatformDetector.isTV() ? 1 : 2;
  static const _maxQueued = 120;

  final Map<String, ({PosterInfo info, DateTime at})> _entries = {};
  final List<({String key, MediaItem item, MediaServerClient client})> _queue = [];
  final Set<String> _pending = {};
  int _running = 0;
  Future<void>? _loading;
  Timer? _saveTimer;
  Timer? _notifyTimer;

  Future<void> _load() => _loading ??= () async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return;
      final now = DateTime.now();
      for (final e in json.entries) {
        final v = e.value;
        if (v is! List || v.length != 2) continue;
        final info = PosterInfo.fromJson(v[0]);
        final at = DateTime.fromMillisecondsSinceEpoch((v[1] as num).toInt());
        if (info != null && now.difference(at) < _ttl) _entries['${e.key}'] = (info: info, at: at);
      }
      _notify();
    } catch (e) {
      appLogger.d('Poster info cache not loaded: $e');
    }
  }();

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(pathlib.join(dir.path, 'poster_info.json'));
  }

  /// What is known about [item]: the cached lookup, else what its listing
  /// carries. Asks the server in the background when languages are missing.
  PosterInfo infoFor(MediaItem item, MediaServerClient? client) {
    unawaited(_load());
    final key = item.globalKey;
    final cached = _entries[key];
    if (cached != null && DateTime.now().difference(cached.at) < _ttl) {
      // An older entry without the audio format: shown, and asked again.
      if (!cached.info.audioKnown && client != null) _request(key, item, client, refresh: true);
      return cached.info;
    }
    final listing = PosterInfo.of(item);
    if (client != null && listing.languages.isEmpty) _request(key, item, client);
    return listing;
  }

  void _request(String key, MediaItem item, MediaServerClient client, {bool refresh = false}) {
    // Reduced effects tier (weak TV sticks): no background lookups; the pills
    // show what the listing carries (quality, HDR).
    if (DevicePerformance.isReduced) return;
    if (_pending.contains(key)) return;
    unawaited(
      _load().then((_) {
        if ((!refresh && _entries.containsKey(key)) || _pending.contains(key)) return;
        _pending.add(key);
        _queue.add((key: key, item: item, client: client));
        while (_queue.length > _maxQueued) {
          _pending.remove(_queue.removeAt(0).key);
        }
        _pump();
      }),
    );
  }

  void _pump() {
    while (_running < _maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeLast();
      _running++;
      unawaited(
        _fetch(job.key, job.item, job.client).whenComplete(() {
          _running--;
          _pending.remove(job.key);
          _pump();
        }),
      );
    }
  }

  Future<void> _fetch(String key, MediaItem item, MediaServerClient client) async {
    try {
      var playableId = item.id;
      // A series or season: its first episode stands for it.
      if (item.kind == MediaKind.show || item.kind == MediaKind.season) {
        final page = await client
            .fetchPlayableDescendantsPage(item.id, start: 0, size: 1)
            .timeout(const Duration(seconds: 10));
        if (page.items.isEmpty) {
          _put(key, const PosterInfo());
          return;
        }
        playableId = page.items.first.id;
      }
      final full = await fetchItemLight(client, playableId).timeout(const Duration(seconds: 10));
      _put(key, full == null ? const PosterInfo() : PosterInfo.of(full));
    } catch (e) {
      appLogger.d('Poster info for ${item.id} unavailable: $e');
    }
  }

  void _put(String key, PosterInfo info) {
    _entries.remove(key);
    _entries[key] = (info: info, at: DateTime.now());
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _notify();
    _saveTimer ??= Timer(const Duration(seconds: 5), () => unawaited(_save()));
  }

  void _notify() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 300), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  Future<void> _save() async {
    _saveTimer = null;
    try {
      final file = await _file();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          for (final e in _entries.entries) e.key: [e.value.info.toJson(), e.value.at.millisecondsSinceEpoch],
        }),
        flush: true,
      );
      await tmp.rename(file.path);
    } catch (e) {
      appLogger.d('Poster info cache not saved: $e');
    }
  }
}

/// Item metadata for background lookups (poster pills, rating medians): on
/// Plex the plain metadata request, without chapters and markers and without
/// writing the offline API cache, which the details page's request does.
Future<MediaItem?> fetchItemLight(MediaServerClient client, String id) =>
    client is PlexClient ? client.fetchEditableItem(id) : client.fetchItem(id);
