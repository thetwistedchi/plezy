import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../media/media_backend.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../mpv/player/player.dart';
import '../../../utils/app_logger.dart';
import '../../music/music_playback_service.dart';
import '../../settings_service.dart';
import 'audio_settings.dart';
import 'music_listen_tracker.dart';

/// A chapter of the playing file.
class AudioChapter {
  const AudioChapter(this.title, this.start);
  final String title;
  final Duration start;
}

/// A remembered position in a track.
class AudioBookmark {
  const AudioBookmark({required this.position, required this.note, required this.createdAt});
  final Duration position;
  final String note;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {'p': position.inMilliseconds, 'n': note, 'at': createdAt.millisecondsSinceEpoch};

  static AudioBookmark fromJson(Map<String, dynamic> json) => AudioBookmark(
    position: Duration(milliseconds: (json['p'] as num?)?.toInt() ?? 0),
    note: json['n'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch((json['at'] as num?)?.toInt() ?? 0),
  );
}

/// Where a book (an album in an audiobook or audio drama library) stopped.
class BookResume {
  const BookResume({required this.trackId, required this.position, required this.updatedAt});
  final String trackId;
  final Duration position;
  final DateTime updatedAt;
}

/// Fork: what the music player does on top of plain playback: library modes
/// (music, audiobooks, audio dramas, podcasts), speed and resume per book,
/// chapters, bookmarks, played podcast episodes, equalizer, volume levelling,
/// night mode and fading between albums. The playback service calls
/// [onTrackStarted] and [onPosition]; everything else reads state from here.
class AudioExtras extends ChangeNotifier {
  AudioExtras._();
  static final instance = AudioExtras._();

  static const _rewindOnResume = Duration(seconds: 5);

  MusicPlaybackService? _service;
  Player? _player;
  MediaItem? _track;
  AudioMode _mode = AudioMode.music;

  /// Chapters of the playing file (empty when it has none).
  final chapters = ValueNotifier<List<AudioChapter>>(const []);

  Map<String, double> _speeds = {};

  /// Podcasts: seconds to skip at the start and end, per podcast.
  Map<String, List<int>> _trims = {};
  Map<String, Map<String, dynamic>> _resume = {};
  Map<String, List<AudioBookmark>> _bookmarks = {};
  Set<String> _played = {};

  /// Books played to the end: `server:album` → album info and time.
  Map<String, Map<String, dynamic>> _finished = {};
  Future<void>? _loaded;
  Timer? _saveTimer;

  double _appliedRate = 1;
  DateTime _lastResumeSave = DateTime.fromMillisecondsSinceEpoch(0);
  double _fadeFactor = 1;
  DateTime _lastFadeStep = DateTime.fromMillisecondsSinceEpoch(0);
  int? _sleepAfterChapter;

  /// Sleep when the current album (folder) ends.
  bool _sleepAtAlbumEnd = false;

  /// Sleep after this many more tracks (the current one counts).
  int? _sleepTracksLeft;

  AudioMode get mode => _mode;
  MediaItem? get track => _track;

  // ---------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}audio_extras.json');
  }

  Future<void> load() => _loaded ??= _load();

  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _speeds = {
        for (final e in ((json['speeds'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toDouble(),
      };
      _trims = {
        for (final e in ((json['trims'] as Map?) ?? const {}).entries)
          e.key as String: [for (final n in (e.value as List)) (n as num).toInt()],
      };
      _resume = {
        for (final e in ((json['resume'] as Map?) ?? const {}).entries)
          e.key as String: Map<String, dynamic>.from(e.value as Map),
      };
      _bookmarks = {
        for (final e in ((json['bookmarks'] as Map?) ?? const {}).entries)
          e.key as String: [
            for (final b in (e.value as List).whereType<Map>()) AudioBookmark.fromJson(Map<String, dynamic>.from(b)),
          ],
      };
      _played = {...((json['played'] as List?) ?? const []).whereType<String>()};
      _finished = {
        for (final e in ((json['finished'] as Map?) ?? const {}).entries)
          e.key as String: Map<String, dynamic>.from(e.value as Map),
      };
      notifyListeners();
    } catch (e) {
      appLogger.d('Audio extras unreadable', error: e);
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () => unawaited(_save()));
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({
          'speeds': _speeds,
          'trims': _trims,
          'resume': _resume,
          'bookmarks': {
            for (final e in _bookmarks.entries)
              if (e.value.isNotEmpty) e.key: [for (final b in e.value) b.toJson()],
          },
          'played': _played.toList(),
          'finished': _finished,
        }),
      );
    } catch (e) {
      appLogger.d('Saving audio extras failed', error: e);
    }
  }

  // ---------------------------------------------------------------------
  // Keys
  // ---------------------------------------------------------------------

  static String? bookKeyOf(MediaItem? track) {
    if (track == null || track.serverId == null) return null;
    final parent = track.parentId;
    return parent == null ? null : '${track.serverId}:$parent';
  }

  static String trackKeyOf(MediaItem track) => '${track.serverId}:${track.id}';

  // ---------------------------------------------------------------------
  // Speed
  // ---------------------------------------------------------------------

  /// Speed of the playing book or podcast (always 1 for music).
  double get speed => _mode.isSpoken ? (_speeds[bookKeyOf(_track)] ?? 1) : 1;

  Future<void> setSpeed(double rate) async {
    final key = bookKeyOf(_track);
    if (key == null || !_mode.isSpoken) return;
    if (rate == 1) {
      _speeds.remove(key);
    } else {
      _speeds[key] = rate;
    }
    _scheduleSave();
    notifyListeners();
    await _applyRate();
  }

  Future<void> _applyRate() async {
    final player = _player;
    if (player == null || player.disposed) return;
    final rate = speed;
    if (rate == _appliedRate) return;
    _appliedRate = rate;
    try {
      await player.setRate(rate);
    } catch (e) {
      appLogger.d('Setting the audio speed failed', error: e);
    }
  }

  // ---------------------------------------------------------------------
  // Podcast intro / outro skipping and ad chapters
  // ---------------------------------------------------------------------

  /// Seconds skipped at the start and at the end of each episode of the
  /// playing podcast.
  (int start, int end) get trim {
    final t = _trims[bookKeyOf(_track)];
    return t == null || t.length < 2 ? (0, 0) : (t[0], t[1]);
  }

  Future<void> setTrim(int start, int end) async {
    final key = bookKeyOf(_track);
    if (key == null) return;
    if (start == 0 && end == 0) {
      _trims.remove(key);
    } else {
      _trims[key] = [start, end];
    }
    _scheduleSave();
    notifyListeners();
  }

  bool _trimmedStart = false;
  bool _skippingEnd = false;
  int? _skippedChapter;

  /// Last ad chapter skipped, for a short notice (cleared when shown).
  final skippedAd = ValueNotifier<String?>(null);

  static bool _isAd(String title, String keywords) {
    final words = [for (final w in keywords.split(',')) if (w.trim().isNotEmpty) RegExp.escape(w.trim())];
    if (words.isEmpty) return false;
    return RegExp('\\b(${words.join('|')})\\b', caseSensitive: false).hasMatch(title);
  }

  void _podcastSkips(MusicPlaybackService service, MediaItem track, Duration position, Duration? duration) {
    if (_mode != AudioMode.podcast) return;
    final (start, end) = trim;
    // Intro: once per episode, only near its beginning.
    if (!_trimmedStart && start > 0) {
      _trimmedStart = true;
      if (position < Duration(seconds: start) && position < const Duration(seconds: 5)) {
        unawaited(service.seek(Duration(seconds: start)));
        return;
      }
    }
    // Outro: straight on to the next episode (or the end of the queue).
    if (end > 0 && duration != null && duration > Duration(seconds: end + 5) && !_skippingEnd) {
      if (duration - position <= Duration(seconds: end)) {
        _skippingEnd = true;
        unawaited(service.seek(duration - const Duration(milliseconds: 300)));
        return;
      }
    }
    // Chapters named like ads.
    final s = SettingsService.instance;
    final list = chapters.value;
    if (list.isEmpty || !s.read(AudioSettings.skipAdChapters)) return;
    final i = chapterIndexAt(position);
    if (i < 0 || i == _skippedChapter) return;
    if (_isAd(list[i].title, s.read(AudioSettings.adKeywords))) {
      _skippedChapter = i;
      final target = i + 1 < list.length ? list[i + 1].start : duration;
      if (target != null) {
        skippedAd.value = list[i].title;
        unawaited(service.seek(target));
      }
    }
  }

  // ---------------------------------------------------------------------
  // Resume per book
  // ---------------------------------------------------------------------

  BookResume? resumeOf(String? serverId, String? albumId) {
    if (serverId == null || albumId == null) return null;
    final hit = _resume['$serverId:$albumId'];
    if (hit == null) return null;
    return BookResume(
      trackId: hit['t'] as String,
      position: Duration(milliseconds: (hit['p'] as num?)?.toInt() ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch((hit['at'] as num?)?.toInt() ?? 0),
    );
  }

  Future<void> clearResume(String serverId, String albumId) async {
    if (_resume.remove('$serverId:$albumId') == null) return;
    _scheduleSave();
    notifyListeners();
  }

  /// Where a queue of [tracks] should start: a book started from its
  /// beginning continues where it stopped (a few seconds earlier).
  ({MediaItem? start, Duration? position}) startFor(
    List<MediaItem> tracks,
    MediaItem? startTrack,
    Duration? initialPosition,
  ) {
    if (tracks.isEmpty || initialPosition != null) return (start: startTrack, position: initialPosition);
    final first = tracks.first;
    if (!AudioSettings.modeFor(first).isBookLike) return (start: startTrack, position: initialPosition);
    if (startTrack != null && startTrack.globalKey != first.globalKey) {
      return (start: startTrack, position: initialPosition);
    }
    final saved = resumeOf(first.serverId, first.parentId);
    if (saved == null) return (start: startTrack, position: initialPosition);
    final track = tracks.where((t) => t.id == saved.trackId).firstOrNull;
    if (track == null) return (start: startTrack, position: initialPosition);
    final at = saved.position - _rewindOnResume;
    return (start: track, position: at.isNegative ? Duration.zero : at);
  }

  /// Albums of a library as [MediaItem]s, from stored info, newest first.
  List<MediaItem> _albums(Map<String, Map<String, dynamic>> source, String serverId, String libraryId) {
    final entries =
        source.entries
            .where((e) => e.key.startsWith('$serverId:') && (e.value['lib'] == null || e.value['lib'] == libraryId))
            .toList()
          ..sort((a, b) => ((b.value['at'] as num?) ?? 0).compareTo((a.value['at'] as num?) ?? 0));
    return [
      for (final e in entries.take(40))
        MediaItem(
          id: e.key.substring(serverId.length + 1),
          backend: MediaBackend.values.where((b) => b.name == e.value['be']).firstOrNull ?? MediaBackend.plex,
          kind: MediaKind.album,
          title: e.value['bt'] as String? ?? '',
          thumbPath: e.value['th'] as String?,
          parentTitle: e.value['ar'] as String?,
          serverId: serverId,
          libraryId: libraryId,
        ),
    ];
  }

  /// Keys (`server:album`) of started and of finished books.
  Set<String> get startedKeys => _resume.keys.toSet();
  Set<String> get finishedKeys => _finished.keys.toSet();

  /// Author (album artist) of the book listened to last in a library.
  String? lastAuthor(String serverId, String libraryId) {
    final all = [
      ..._resume.entries,
      ..._finished.entries,
    ].where((e) => e.key.startsWith('$serverId:') && (e.value['lib'] == null || e.value['lib'] == libraryId)).toList()
      ..sort((a, b) => ((b.value['at'] as num?) ?? 0).compareTo((a.value['at'] as num?) ?? 0));
    for (final e in all) {
      final author = e.value['ar'] as String?;
      if (author != null && author.isNotEmpty) return author;
    }
    return null;
  }

  /// Books of a library that were started and not finished.
  List<MediaItem> continueListening(String serverId, String libraryId) => _albums(_resume, serverId, libraryId);

  /// Books of a library played to the end.
  List<MediaItem> recentlyFinished(String serverId, String libraryId) => _albums(_finished, serverId, libraryId);

  // ---------------------------------------------------------------------
  // Played podcast episodes
  // ---------------------------------------------------------------------

  bool isPlayed(MediaItem track) => _played.contains(trackKeyOf(track));

  Future<void> setPlayed(MediaItem track, bool played) async {
    final key = trackKeyOf(track);
    final changed = played ? _played.add(key) : _played.remove(key);
    if (!changed) return;
    _scheduleSave();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Bookmarks
  // ---------------------------------------------------------------------

  List<AudioBookmark> bookmarksOf(MediaItem track) => List.unmodifiable(_bookmarks[trackKeyOf(track)] ?? const []);

  Future<void> addBookmark(MediaItem track, Duration position, String note) async {
    final list = _bookmarks.putIfAbsent(trackKeyOf(track), () => []);
    list
      ..add(AudioBookmark(position: position, note: note.trim(), createdAt: DateTime.now()))
      ..sort((a, b) => a.position.compareTo(b.position));
    _scheduleSave();
    notifyListeners();
  }

  Future<void> removeBookmark(MediaItem track, AudioBookmark bookmark) async {
    _bookmarks[trackKeyOf(track)]?.remove(bookmark);
    _scheduleSave();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Chapters
  // ---------------------------------------------------------------------

  int chapterIndexAt(Duration position) {
    final list = chapters.value;
    var index = -1;
    for (var i = 0; i < list.length; i++) {
      if (list[i].start <= position + const Duration(milliseconds: 300)) index = i;
    }
    return index;
  }

  /// Back to the chapter start, or the chapter before when just past it;
  /// without chapters the previous track.
  Future<void> previousChapter() async {
    final service = _service;
    if (service == null) return;
    final list = chapters.value;
    final pos = service.position;
    final i = chapterIndexAt(pos);
    if (list.isEmpty || i < 0) return service.previous();
    if (pos - list[i].start > const Duration(seconds: 3) || i == 0) {
      if (i == 0 && pos - list[i].start <= const Duration(seconds: 3)) return service.previous();
      return service.seek(list[i].start);
    }
    return service.seek(list[i - 1].start);
  }

  Future<void> nextChapter() async {
    final service = _service;
    if (service == null) return;
    final list = chapters.value;
    final i = chapterIndexAt(service.position);
    if (list.isEmpty || i + 1 >= list.length) return service.next();
    return service.seek(list[i + 1].start);
  }

  /// Sleep at the end of the current chapter (or cancel with false).
  bool get sleepAtChapterEnd => _sleepAfterChapter != null;

  void setSleepAtChapterEnd(bool on) {
    _sleepAfterChapter = on ? chapterIndexAt(_service?.position ?? Duration.zero) : null;
    notifyListeners();
  }

  bool get sleepAtAlbumEnd => _sleepAtAlbumEnd;
  int? get sleepTracksLeft => _sleepTracksLeft;

  /// Clears the fork's own sleep modes (chapter, album, track count).
  void clearSleep() {
    _sleepAfterChapter = null;
    _sleepAtAlbumEnd = false;
    _sleepTracksLeft = null;
    notifyListeners();
  }

  /// Pause when the current album (folder) has played to its end.
  void setSleepAtAlbumEnd() {
    clearSleep();
    _sleepAtAlbumEnd = true;
    _armEndOfTrack();
    notifyListeners();
  }

  /// Pause after [count] tracks, the current one included.
  void setSleepAfterTracks(int count) {
    clearSleep();
    _sleepTracksLeft = count;
    _armEndOfTrack();
    notifyListeners();
  }

  /// Books: play only the chosen track, then pause.
  bool get singleTrack => SettingsService.instance.read(AudioSettings.singleTrack);

  Future<void> setSingleTrack(bool on) async {
    await SettingsService.instance.write(AudioSettings.singleTrack, on);
    final service = _service;
    if (service != null && _mode.isSpoken) {
      if (on) {
        service.setSleepTimer(null, endOfTrack: true);
      } else if (service.sleepTimerEndOfTrack && !_sleepAtAlbumEnd && _sleepTracksLeft == null) {
        service.setSleepTimer(null);
      }
    }
    notifyListeners();
  }

  /// Re-applies "only this track" after the sleep timer was changed.
  void rearm() => _armEndOfTrack();

  /// Makes the service pause at the end of the current track when one of
  /// the modes above says this is the last one.
  void _armEndOfTrack() {
    final service = _service;
    final track = _track;
    if (service == null || track == null) return;
    final last =
        (_mode.isSpoken && singleTrack) ||
        (_sleepAtAlbumEnd && _isLastOfAlbum(service, track)) ||
        (_sleepTracksLeft != null && _sleepTracksLeft! <= 1);
    if (!last) return;
    if (_sleepAtAlbumEnd || (_sleepTracksLeft ?? 2) <= 1) {
      _sleepAtAlbumEnd = false;
      _sleepTracksLeft = null;
    }
    if (!service.sleepTimerEndOfTrack) service.setSleepTimer(null, endOfTrack: true);
  }

  Future<void> _readChapters(Player player) async {
    // The chapter list is known once the file is open; ask a moment later.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (_player != player || player.disposed) return;
    try {
      final count = int.tryParse(await player.getProperty('chapter-list/count') ?? '') ?? 0;
      final list = <AudioChapter>[];
      for (var i = 0; i < count && i < 500; i++) {
        final time = double.tryParse(await player.getProperty('chapter-list/$i/time') ?? '');
        if (time == null) continue;
        final title = (await player.getProperty('chapter-list/$i/title'))?.trim();
        list.add(
          AudioChapter(
            title == null || title.isEmpty ? '${i + 1}' : title,
            Duration(milliseconds: (time * 1000).round()),
          ),
        );
      }
      if (_player == player) chapters.value = list.length > 1 ? list : const [];
    } catch (e) {
      appLogger.d('Reading chapters failed', error: e);
    }
  }

  // ---------------------------------------------------------------------
  // Engine hooks
  // ---------------------------------------------------------------------

  /// Called by the playback service whenever a track starts (also gapless).
  Future<void> onTrackStarted(MusicPlaybackService service, Player player, MediaItem track) async {
    await load();
    _service = service;
    final playerChanged = _player != player;
    _player = player;
    final previous = _track?.globalKey;
    _track = track;
    _mode = AudioSettings.modeFor(track);
    _sleepAfterChapter = null;
    _trimmedStart = false;
    _skippingEnd = false;
    _skippedChapter = null;
    if (_sleepTracksLeft != null && previous != null && previous != track.globalKey) {
      _sleepTracksLeft = _sleepTracksLeft! - 1;
    }
    chapters.value = const [];
    if (playerChanged) _appliedRate = 1;
    notifyListeners();

    await _applyRate();
    await applyAudioSettings();
    _armEndOfTrack();
    unawaited(_readChapters(player));
    MusicListenTracker.instance.onTrackStarted(track, _mode);

    // Fade back in after a fade out at the end of the previous album.
    if (_fadeFactor < 1) {
      final steps = 10;
      final total = Duration(seconds: SettingsService.instance.read(AudioSettings.fadeSeconds).clamp(1, 12));
      for (var i = 1; i <= steps; i++) {
        await Future<void>.delayed(total ~/ (steps * 2));
        if (_player != player || _track != track) return;
        _fadeFactor = i / steps;
        await _setFadedVolume();
      }
    }
  }

  /// Applies equalizer, night mode and levelling to the current player.
  Future<void> applyAudioSettings() async {
    final player = _player;
    if (player == null || player.disposed) return;
    final s = SettingsService.instance;
    final eq = s.read(_mode.isSpoken ? AudioSettings.eqSpoken : AudioSettings.eqMusic);
    try {
      if (player is PlayerBase) {
        await player.setExtraAudioFilters([eq.filter]);
        await player.setNightMode(s.read(AudioSettings.musicNightMode));
      }
      final levelling = s.read(AudioSettings.levelling);
      final replayGain = switch (levelling) {
        AudioLevelling.track => 'track',
        AudioLevelling.album => 'album',
        _ => 'no',
      };
      await player.setProperty('replaygain', replayGain);
      await player.setProperty('replaygain-clip', 'no');
      await player.setAudioNormalization(
        levelling == AudioLevelling.automatic || s.read(SettingsService.audioNormalization),
      );
    } catch (e) {
      appLogger.d('Applying audio settings failed', error: e);
    }
  }

  /// Called by the playback service on every position update.
  void onPosition(Duration position) {
    final service = _service;
    final track = _track;
    if (service == null || track == null || service.currentTrack?.globalKey != track.globalKey) return;
    final duration = service.duration;

    // Resume point of a book, every few seconds.
    if (_mode.isBookLike && DateTime.now().difference(_lastResumeSave) > const Duration(seconds: 5)) {
      _lastResumeSave = DateTime.now();
      final key = bookKeyOf(track);
      if (key != null) {
        final finished =
            duration != null && duration - position < const Duration(seconds: 5) && _isLastOfAlbum(service, track);
        final info = {
          'bt': track.parentTitle,
          'th': track.parentThumbPath ?? track.thumbPath,
          'ar': track.grandparentTitle,
          'lib': track.libraryId,
          'be': track.backend.name,
          'at': DateTime.now().millisecondsSinceEpoch,
        };
        if (finished) {
          if (_resume.remove(key) != null) {
            _finished[key] = info;
            if (_finished.length > 200) _finished.remove(_finished.keys.first);
            notifyListeners();
          }
        } else {
          final isNew = !_resume.containsKey(key);
          _resume[key] = {...info, 't': track.id, 'p': position.inMilliseconds};
          _finished.remove(key);
          if (isNew) notifyListeners();
        }
        _scheduleSave();
      }
    }

    // A podcast episode counts as played at 95 %.
    if (_mode == AudioMode.podcast && duration != null && duration > Duration.zero) {
      if (position.inMilliseconds >= duration.inMilliseconds * 0.95 && !isPlayed(track)) {
        unawaited(setPlayed(track, true));
      }
    }

    // Sleep at the end of a chapter.
    final sleepChapter = _sleepAfterChapter;
    if (sleepChapter != null && chapters.value.isNotEmpty && chapterIndexAt(position) > sleepChapter) {
      _sleepAfterChapter = null;
      notifyListeners();
      unawaited(service.pause());
    }

    // Podcasts: intro, outro and ad chapters.
    _podcastSkips(service, track, position, duration);

    // Fade out before a track of another album.
    _fadeOut(service, track, position, duration);

    MusicListenTracker.instance.onPosition(track, position, duration);
  }

  bool _isLastOfAlbum(MusicPlaybackService service, MediaItem track) {
    final i = service.currentIndex;
    final queue = service.queue;
    return i < 0 || i + 1 >= queue.length || queue[i + 1].parentId != track.parentId;
  }

  void _fadeOut(MusicPlaybackService service, MediaItem track, Duration position, Duration? duration) {
    final seconds = SettingsService.instance.read(AudioSettings.fadeSeconds);
    if (seconds <= 0 || _mode != AudioMode.music || duration == null || duration <= Duration.zero) return;
    if (service.repeatMode == MusicRepeatMode.one) return;
    final i = service.currentIndex;
    final queue = service.queue;
    if (i < 0 || i + 1 >= queue.length || queue[i + 1].parentId == track.parentId) {
      // Same album (gapless) or nothing next: no fade.
      if (_fadeFactor < 1 && position < duration - Duration(seconds: seconds)) {
        _fadeFactor = 1;
        unawaited(_setFadedVolume());
      }
      return;
    }
    final remaining = duration - position;
    final window = Duration(seconds: seconds);
    final factor = remaining >= window ? 1.0 : (remaining.inMilliseconds / window.inMilliseconds).clamp(0.0, 1.0);
    if (factor == _fadeFactor) return;
    if ((factor - _fadeFactor).abs() < 0.05 && factor != 1) return;
    if (DateTime.now().difference(_lastFadeStep) < const Duration(milliseconds: 150) && factor != 1) return;
    _lastFadeStep = DateTime.now();
    _fadeFactor = factor;
    unawaited(_setFadedVolume());
  }

  Future<void> _setFadedVolume() async {
    final player = _player;
    final service = _service;
    if (player == null || player.disposed || service == null) return;
    try {
      await player.setVolume(service.volume * _fadeFactor);
    } catch (_) {}
  }

  /// The service stopped: forget the player.
  void onStopped() {
    _sleepAtAlbumEnd = false;
    _sleepTracksLeft = null;
    _player = null;
    _track = null;
    _fadeFactor = 1;
    chapters.value = const [];
    notifyListeners();
  }
}
