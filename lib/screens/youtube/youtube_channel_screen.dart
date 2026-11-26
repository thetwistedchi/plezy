import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/youtube/youtube_service.dart';
import '../../services/youtube/youtube_settings.dart';
import '../../services/youtube/youtube_watchlist.dart';
import '../../theme/mono_tokens.dart';
import '../../theme/player_style.dart';
import '../../widgets/app_icon.dart';
import 'youtube_player_screen.dart';
import 'youtube_playlist_screen.dart';
import 'youtube_strings.dart';
import 'youtube_routes.dart';
import '../../theme/retrowave_colors.dart';

/// A channel's page: banner, name and counts, and all uploads newest first,
/// loaded 50 at a time while scrolling.
///
/// Opened from the player, a picked video is returned with [Navigator.pop]
/// so the running player plays it; otherwise the video opens a new player.
class YouTubeChannelScreen extends StatefulWidget {
  const YouTubeChannelScreen({
    super.key,
    required this.channelId,
    required this.channelTitle,
    this.returnPickedVideo = false,
  });

  final String channelId;
  final String channelTitle;
  final bool returnPickedVideo;

  @override
  State<YouTubeChannelScreen> createState() => _YouTubeChannelScreenState();
}

class _YouTubeChannelScreenState extends State<YouTubeChannelScreen> {
  final _service = YouTubeService.instance;
  final _settings = YouTubeSettings.instance;
  final _scroll = ScrollController();

  YtChannelInfo? _info;
  // Fork: the channel's playlists (signed in only).
  List<({String id, String title, int count, String? thumbnail})> _playlists = const [];
  final List<YouTubeVideo> _videos = [];
  String? _nextPage;
  bool _loading = false;
  bool _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) unawaited(_loadMore());
    });
    unawaited(_loadInfo());
    unawaited(_loadMore());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    if (!_settings.isSignedIn) return;
    try {
      final info = await _service.channelInfo(widget.channelId);
      if (mounted) setState(() => _info = info);
    } catch (_) {}
    try {
      final lists = await _service.channelPlaylists(widget.channelId);
      if (mounted) setState(() => _playlists = lists.where((l) => l.count > 0).toList());
    } catch (_) {}
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!_settings.isSignedIn) {
        // Without the API only the feed's newest 15 videos are available.
        final feed = await _service.channelFeed(widget.channelId);
        if (!mounted) return;
        setState(() {
          _videos.addAll(feed);
          _done = true;
        });
        return;
      }
      final page = await _service.channelUploads(widget.channelId, pageToken: _nextPage);
      if (!mounted) return;
      setState(() {
        _videos.addAll(page.items);
        _nextPage = page.nextPageToken;
        _done = page.nextPageToken == null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fork: plays a whole playlist in a row, the next video lined up.
  void _open(YouTubeVideo video) {
    if (widget.returnPickedVideo) {
      Navigator.of(context).pop(video);
    } else {
      unawaited(YouTubePlayerScreen.open(context, [video]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final accent = playerActiveColor(context);
    final info = _info;
    final videos = _videos
        .where((v) => (_settings.showShorts || !v.isShort) && (_settings.showPremieres || !(v.isUpcoming || v.isLive)))
        .toList();
    final stats = [
      if (info?.handle != null) info!.handle!,
      if (info?.subscriberCount != null) YtStrings.subscribers(info!.subscriberCount!),
      if (info?.videoCount != null) YtStrings.videoCount(info!.videoCount!),
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: Text(info?.title ?? widget.channelTitle),
        actions: [
          const YouTubeHomeButton(),
          IconButton(
            tooltip: _settings.isFavorite(widget.channelId) ? YtStrings.unfavoriteChannel : YtStrings.favoriteChannelAction,
            onPressed: () async {
              await _settings.setFavorite(
                widget.channelId,
                info?.title ?? widget.channelTitle,
                !_settings.isFavorite(widget.channelId),
              );
              if (mounted) setState(() {});
            },
            icon: AppIcon(
              Symbols.star_rounded,
              fill: _settings.isFavorite(widget.channelId) ? 1 : 0,
              color: _settings.isFavorite(widget.channelId) ? accent : null,
            ),
          ),
          IconButton(
            tooltip: YtStrings.openOnYouTube,
            onPressed: () => unawaited(
              launchUrl(
                Uri.https('www.youtube.com', '/channel/${widget.channelId}'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            icon: const AppIcon(Symbols.open_in_new_rounded),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_settings, YouTubeWatchlist.instance]),
        builder: (context, _) => CustomScrollView(
          controller: _scroll,
          slivers: [
            if (info?.bannerUrl != null)
              SliverToBoxAdapter(
                child: AspectRatio(
                  aspectRatio: 6.2,
                  child: CachedNetworkImage(
                    imageUrl: info!.bannerUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: info?.avatarUrl == null
                            ? ColoredBox(color: mono.surface)
                            : CachedNetworkImage(imageUrl: info!.avatarUrl!, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info?.title ?? widget.channelTitle,
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (stats.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(stats, style: theme.textTheme.bodyMedium?.copyWith(color: mono.textMuted)),
                          ],
                          if (info != null && info.description.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              info.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_playlists.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  // Fork: collapsed by default, so the uploads stay in view.
                  child: Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      expandedAlignment: Alignment.centerLeft,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(mono.radiusMd)),
                      leading: const AppIcon.retro(Symbols.playlist_play_rounded),
                      title: Text('${YtStrings.playlists} (${_playlists.length})', style: theme.textTheme.titleMedium),
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final list in _playlists)
                              ActionChip(
                                avatar: const AppIcon.retro(Symbols.playlist_play_rounded, size: 18),
                                label: Text('${list.title} (${list.count})'),
                                onPressed: () => unawaited(
                                  YouTubePlaylistScreen.open(context, playlistId: list.id, title: list.title),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_error != null && _videos.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('$_error', style: TextStyle(color: mono.textMuted))),
              )
            else if (videos.isEmpty && !_loading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(YtStrings.channelEmpty, style: TextStyle(color: mono.textMuted))),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 340,
                    mainAxisSpacing: 24,
                    crossAxisSpacing: 20,
                    childAspectRatio: 1.15,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _ChannelCard(
                      video: videos[i],
                      accent: accent,
                      progress: _settings.progressFraction(videos[i].id),
                      inWatchlist: YouTubeWatchlist.instance.contains(videos[i].id),
                      onTap: () => _open(videos[i]),
                      onToggleWatchlist: () => unawaited(YouTubeWatchlist.instance.toggle(videos[i])),
                    ),
                    childCount: videos.length,
                  ),
                ),
              ),
            if (_loading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(color: accent)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.video,
    required this.accent,
    required this.progress,
    required this.inWatchlist,
    required this.onTap,
    required this.onToggleWatchlist,
  });

  final YouTubeVideo video;
  final Color accent;
  final double? progress;
  final bool inWatchlist;
  final VoidCallback onTap;
  final VoidCallback onToggleWatchlist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final gradient = PlayerStyle.of(context).progressGradient;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(mono.radiusMd),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(mono.radiusMd),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: RetroColors.isActive(context) ? RetroColors.dusk : tokens(context).surface),
                    if (video.thumbnailUrl != null)
                      CachedNetworkImage(
                        imageUrl: video.thumbnailUrl!,
                        fit: BoxFit.cover,
                          memCacheWidth: 480,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    if (video.duration > Duration.zero)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            YtStrings.duration(video.duration),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Tooltip(
                        message: inWatchlist ? YtStrings.removeFromWatchlist : YtStrings.addToWatchlist,
                        child: Material(
                          color: inWatchlist ? Color.lerp(accent, Colors.black, 0.55) : Colors.black.withValues(alpha: 0.7),
                          shape: CircleBorder(
                            side: BorderSide(color: inWatchlist ? accent : Colors.white.withValues(alpha: 0.35)),
                          ),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onToggleWatchlist,
                            child: SizedBox(
                              width: 34,
                              height: 34,
                              child: Center(
                                child: AppIcon(
                                  inWatchlist ? Symbols.check_rounded : Symbols.add_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if ((progress ?? 0) > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 4,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress!.clamp(0.02, 1.0),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: gradient != null && gradient.length >= 2 ? LinearGradient(colors: gradient) : null,
                              color: gradient == null || gradient.length < 2 ? accent : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (video.viewCount > 0) YtStrings.views(video.viewCount),
                YtStrings.age(video.publishedAt),
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
