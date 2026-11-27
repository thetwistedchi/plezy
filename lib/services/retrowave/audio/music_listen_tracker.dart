import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../media/media_item.dart';
import '../../../utils/app_logger.dart';
import '../../settings_service.dart';
import 'audio_settings.dart';

/// One listened track (for the music statistics and scrobbling).
class MusicListen {
  const MusicListen({
    required this.key,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.at,
    this.albumKey,
    this.artistKey,
    this.thumb,
    this.server,
  });

  final String key;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final DateTime at;
  final String? albumKey;
  final String? artistKey;
  final String? thumb;
  final String? server;

  Map<String, dynamic> toJson() => {
    'k': key,
    't': title,
    'ar': artist,
    'al': album,
    'ms': duration.inMilliseconds,
    'at': at.millisecondsSinceEpoch,
    'alk': ?albumKey,
    'ark': ?artistKey,
    'th': ?thumb,
    's': ?server,
  };

  static MusicListen fromJson(Map<String, dynamic> json) => MusicListen(
    key: json['k'] as String? ?? '',
    title: json['t'] as String? ?? '',
    artist: json['ar'] as String? ?? '',
    album: json['al'] as String? ?? '',
    duration: Duration(milliseconds: (json['ms'] as num?)?.toInt() ?? 0),
    at: DateTime.fromMillisecondsSinceEpoch((json['at'] as num?)?.toInt() ?? 0),
    albumKey: json['alk'] as String?,
    artistKey: json['ark'] as String?,
    thumb: json['th'] as String?,
    server: json['s'] as String?,
  );
}

/// Fork: counts a music track as listened once half of it (at most four
/// minutes) has played, like Last.fm. Each listen goes into a local log
/// for the music statistics and is scrobbled to ListenBrainz and Last.fm
/// when set up. Failed scrobbles are kept and sent again later.
class MusicListenTracker {
  MusicListenTracker._();
  static final instance = MusicListenTracker._();

  static const _maxLog = 20000;

  MediaItem? _track;
  bool _counted = false;
  Duration _played = Duration.zero;
  Duration? _last;
  DateTime _startedAt = DateTime.now();

  final List<MusicListen> _log = [];
  final List<MusicListen> _pending = [];
  Future<void>? _loaded;

  List<MusicListen> get log => List.unmodifiable(_log);

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}music_listens.json');
  }

  Future<void> load() => _loaded ??= _load();

  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _log.addAll([
        for (final e in ((json['log'] as List?) ?? const []).whereType<Map>())
          MusicListen.fromJson(Map<String, dynamic>.from(e)),
      ]);
      _pending.addAll([
        for (final e in ((json['pending'] as List?) ?? const []).whereType<Map>())
          MusicListen.fromJson(Map<String, dynamic>.from(e)),
      ]);
    } catch (e) {
      appLogger.d('Music listen log unreadable', error: e);
    }
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({
          'log': [for (final l in _log) l.toJson()],
          'pending': [for (final l in _pending) l.toJson()],
        }),
      );
    } catch (e) {
      appLogger.d('Saving the music listen log failed', error: e);
    }
  }

  void onTrackStarted(MediaItem track, AudioMode mode) {
    unawaited(load());
    _track = mode == AudioMode.music ? track : null;
    _counted = false;
    _played = Duration.zero;
    _last = null;
    _startedAt = DateTime.now();
    if (_track != null) unawaited(_nowPlaying(track));
  }

  void onPosition(MediaItem track, Duration position, Duration? duration) {
    if (_track == null || _track!.globalKey != track.globalKey || _counted) return;
    final last = _last;
    _last = position;
    if (last != null) {
      final step = position - last;
      if (step > Duration.zero && step < const Duration(seconds: 3)) _played += step;
    }
    final total = duration ?? (track.durationMs != null ? Duration(milliseconds: track.durationMs!) : null);
    if (total == null || total < const Duration(seconds: 30)) return;
    final needed = total ~/ 2 < const Duration(minutes: 4) ? total ~/ 2 : const Duration(minutes: 4);
    if (_played < needed) return;
    _counted = true;
    unawaited(_count(track, total));
  }

  Future<void> _count(MediaItem track, Duration duration) async {
    await load();
    final listen = MusicListen(
      key: '${track.serverId}:${track.id}',
      title: track.title ?? '',
      artist: track.trackArtistTitle ?? track.grandparentTitle ?? '',
      album: track.parentTitle ?? '',
      duration: duration,
      at: _startedAt,
      albumKey: track.parentId == null ? null : '${track.serverId}:${track.parentId}',
      artistKey: track.grandparentId == null ? null : '${track.serverId}:${track.grandparentId}',
      thumb: track.parentThumbPath ?? track.thumbPath,
      server: track.serverId,
    );
    _log.add(listen);
    if (_log.length > _maxLog) _log.removeRange(0, _log.length - _maxLog);
    if (_scrobblingOn) _pending.add(listen);
    await _save();
    await flush();
  }

  /// Removes every listen of the log (statistics), keeps pending scrobbles.
  Future<void> clearLog() async {
    _log.clear();
    await _save();
  }

  // ---------------------------------------------------------------------
  // Scrobbling
  // ---------------------------------------------------------------------

  static SettingsService get _s => SettingsService.instance;
  static String get _lbToken => _s.read(AudioSettings.listenBrainzToken).trim();
  static String get _lfKey => _s.read(AudioSettings.lastFmApiKey).trim();
  static String get _lfSecret => _s.read(AudioSettings.lastFmSecret).trim();
  static String get _lfSession => _s.read(AudioSettings.lastFmSession).trim();
  static bool get _lastFmOn => _lfKey.isNotEmpty && _lfSecret.isNotEmpty && _lfSession.isNotEmpty;
  static bool get _scrobblingOn => _lbToken.isNotEmpty || _lastFmOn;

  bool _flushing = false;

  /// Sends the pending scrobbles; failed ones stay for the next try.
  Future<void> flush() async {
    if (_flushing || _pending.isEmpty || !_scrobblingOn) return;
    _flushing = true;
    try {
      final batch = _pending.take(50).toList();
      var ok = true;
      if (_lbToken.isNotEmpty) ok = await _listenBrainz('import', batch) && ok;
      if (_lastFmOn) ok = await _lastFmScrobble(batch) && ok;
      if (ok) {
        _pending.removeRange(0, batch.length);
        await _save();
        if (_pending.isNotEmpty) unawaited(Future<void>.delayed(const Duration(seconds: 2), flush));
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _nowPlaying(MediaItem track) async {
    if (!_scrobblingOn) return;
    final listen = MusicListen(
      key: '',
      title: track.title ?? '',
      artist: track.trackArtistTitle ?? track.grandparentTitle ?? '',
      album: track.parentTitle ?? '',
      duration: Duration(milliseconds: track.durationMs ?? 0),
      at: DateTime.now(),
    );
    if (listen.title.isEmpty || listen.artist.isEmpty) return;
    if (_lbToken.isNotEmpty) await _listenBrainz('playing_now', [listen]);
    if (_lastFmOn) {
      await _lastFm({
        'method': 'track.updateNowPlaying',
        'artist': listen.artist,
        'track': listen.title,
        if (listen.album.isNotEmpty) 'album': listen.album,
        if (listen.duration > Duration.zero) 'duration': '${listen.duration.inSeconds}',
      });
    }
    unawaited(flush());
  }

  Future<bool> _listenBrainz(String type, List<MusicListen> listens) async {
    try {
      final body = {
        'listen_type': type == 'import' && listens.length == 1 ? 'single' : type,
        'payload': [
          for (final l in listens)
            if (l.title.isNotEmpty && l.artist.isNotEmpty)
              {
                if (type != 'playing_now') 'listened_at': l.at.millisecondsSinceEpoch ~/ 1000,
                'track_metadata': {
                  'artist_name': l.artist,
                  'track_name': l.title,
                  if (l.album.isNotEmpty) 'release_name': l.album,
                  'additional_info': {
                    if (l.duration > Duration.zero) 'duration_ms': l.duration.inMilliseconds,
                    'submission_client': 'Plezy Retrowave',
                  },
                },
              },
        ],
      };
      final response = await http
          .post(
            Uri.parse('https://api.listenbrainz.org/1/submit-listens'),
            headers: {'Authorization': 'Token $_lbToken', 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        appLogger.d('ListenBrainz: ${response.statusCode} ${response.body}');
      }
      // A bad request (4xx other than 429) will not get better by retrying.
      return response.statusCode == 200 ||
          (response.statusCode >= 400 && response.statusCode < 500 && response.statusCode != 429);
    } catch (e) {
      appLogger.d('ListenBrainz unreachable', error: e);
      return false;
    }
  }

  Future<bool> _lastFmScrobble(List<MusicListen> listens) async {
    final params = <String, String>{'method': 'track.scrobble'};
    var i = 0;
    for (final l in listens) {
      if (l.title.isEmpty || l.artist.isEmpty) continue;
      params['artist[$i]'] = l.artist;
      params['track[$i]'] = l.title;
      params['timestamp[$i]'] = '${l.at.millisecondsSinceEpoch ~/ 1000}';
      if (l.album.isNotEmpty) params['album[$i]'] = l.album;
      if (l.duration > Duration.zero) params['duration[$i]'] = '${l.duration.inSeconds}';
      if (++i >= 50) break;
    }
    if (i == 0) return true;
    return _lastFm(params);
  }

  static String _signature(Map<String, String> params, String secret) {
    final keys = params.keys.where((k) => k != 'format' && k != 'callback').toList()..sort();
    final raw = StringBuffer();
    for (final k in keys) {
      raw
        ..write(k)
        ..write(params[k]);
    }
    raw.write(secret);
    return md5.convert(utf8.encode(raw.toString())).toString();
  }

  Future<bool> _lastFm(Map<String, String> params) async {
    try {
      final all = {...params, 'api_key': _lfKey, 'sk': _lfSession};
      all['api_sig'] = _signature(all, _lfSecret);
      all['format'] = 'json';
      final response = await http
          .post(Uri.parse('https://ws.audioscrobbler.com/2.0/'), body: all)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) appLogger.d('Last.fm: ${response.statusCode} ${response.body}');
      return response.statusCode == 200 || (response.statusCode >= 400 && response.statusCode < 500);
    } catch (e) {
      appLogger.d('Last.fm unreachable', error: e);
      return false;
    }
  }

  /// Signs in to Last.fm with the user's API account; stores the session.
  /// Returns an error message, or null on success.
  static Future<String?> signInLastFm({
    required String apiKey,
    required String secret,
    required String user,
    required String password,
  }) async {
    final params = {'method': 'auth.getMobileSession', 'username': user, 'password': password, 'api_key': apiKey};
    params['api_sig'] = _signature(params, secret);
    params['format'] = 'json';
    try {
      final response = await http
          .post(Uri.parse('https://ws.audioscrobbler.com/2.0/'), body: params)
          .timeout(const Duration(seconds: 15));
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final key = (json['session'] as Map?)?['key'] as String?;
      if (key == null) return json['message'] as String? ?? 'HTTP ${response.statusCode}';
      await _s.write(AudioSettings.lastFmApiKey, apiKey);
      await _s.write(AudioSettings.lastFmSecret, secret);
      await _s.write(AudioSettings.lastFmUser, user);
      await _s.write(AudioSettings.lastFmSession, key);
      return null;
    } catch (e) {
      return '$e';
    }
  }

  static Future<void> signOutLastFm() async {
    await _s.write(AudioSettings.lastFmSession, '');
    await _s.write(AudioSettings.lastFmUser, '');
  }

  /// Checks a ListenBrainz token; returns the user name or null.
  static Future<String?> validateListenBrainz(String token) async {
    try {
      final response = await http
          .get(
            Uri.parse('https://api.listenbrainz.org/1/validate-token'),
            headers: {'Authorization': 'Token ${token.trim()}'},
          )
          .timeout(const Duration(seconds: 15));
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['valid'] == true ? json['user_name'] as String? : null;
    } catch (_) {
      return null;
    }
  }
}
