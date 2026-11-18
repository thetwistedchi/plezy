import 'package:flutter/foundation.dart';

import '../../services/youtube/youtube_service.dart';
import '../../services/youtube/youtube_settings.dart';
import 'youtube_player_screen.dart';

/// The YouTube video to offer for resuming: the last opened one, else the
/// latest saved position of a video still in the feed, while unfinished
/// (past 10 s, under 95 %), not dismissed and not playing right now.
({YouTubeVideo video, ({double position, double duration}) progress})? youTubeResumeCandidate() {
  final settings = YouTubeSettings.instance;
  if (!settings.isLoaded) return null;
  bool unfinished(({double position, double duration})? p) =>
      p != null && p.position >= 10 && p.position / p.duration < 0.95;

  final json = settings.lastVideoJson;
  final last = json == null ? null : YouTubeVideo.fromJson(json);
  final candidates = <YouTubeVideo>[?last];
  final byId = {for (final video in YouTubeService.instance.videos) video.id: video};
  for (final id in settings.recentProgressIds.take(50)) {
    final video = byId[id];
    if (video != null && video.id != last?.id) candidates.add(video);
  }
  final dismissed = settings.dismissedResumes.toSet();
  for (final video in candidates) {
    if (dismissed.contains(video.id) || YouTubePlayerScreen.isPlaying(video.id)) continue;
    final progress = settings.progressOf(video.id);
    if (unfinished(progress)) return (video: video, progress: progress!);
  }
  return null;
}

/// Listenable for anything that changes [youTubeResumeCandidate].
Listenable get youTubeResumeChanges => Listenable.merge([YouTubeSettings.instance, YouTubeService.instance]);
