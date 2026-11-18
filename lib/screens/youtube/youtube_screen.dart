import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/youtube/youtube_auth.dart';
import '../../services/youtube/youtube_channels.dart';
import '../../services/youtube/youtube_extras.dart';
import '../../services/youtube/youtube_service.dart';
import '../../services/youtube/youtube_settings.dart';
import '../../services/youtube/youtube_watchlist.dart';
import '../../theme/mono_tokens.dart';
import '../../theme/player_style.dart';
import '../../widgets/app_icon.dart';
import 'youtube_channel_screen.dart';
import 'youtube_channels_screen.dart';
import 'youtube_guide_screen.dart';
import 'youtube_player_screen.dart';
import 'youtube_settings_screen.dart';
import 'youtube_strings.dart';
import 'youtube_routes.dart';
import '../../theme/retrowave_colors.dart';

/// The YouTube tab: newest uploads of the signed-in user's subscriptions.
class YouTubeScreen extends StatefulWidget {
  const YouTubeScreen({super.key});

  @override
  State<YouTubeScreen> createState() => _YouTubeScreenState();
}

enum _YtView { subscriptions, watchlist }

class _YouTubeScreenState extends State<YouTubeScreen> {
  final _settings = YouTubeSettings.instance;
  final _service = YouTubeService.instance;
  final _watchlist = YouTubeWatchlist.instance;
  _YtView _view = _YtView.subscriptions;
  YouTubeSort _sort = YouTubeSort.newest;
  YouTubeFilter _filter = YouTubeFilter.all;
  bool _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    YouTubeChannels.instance.addListener(_onSettingsChanged);
    unawaited(
      Future.wait([_settings.load(), YouTubeChannels.instance.load()]).then((_) => _onSettingsChanged()),
    );
    unawaited(_watchlist.load());
    YouTubeNotifier.onOpen = (video) {
      if (mounted) unawaited(YouTubePlayerScreen.open(context, [video]));
    };
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    YouTubeChannels.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  int _channelCount = 0;

  void _onSettingsChanged() {
    if (!_settings.isLoaded || !YouTubeChannels.instance.isLoaded) return;
    final signedIn = _settings.isSignedIn;
    final channels = YouTubeChannels.instance.channels.length;
    final available = YouTubeService.isAvailable;
    if (available && (signedIn != _wasSignedIn || channels != _channelCount)) {
      _service.ensureStarted();
      if ((channels != _channelCount && _channelCount > 0) || (signedIn && !_wasSignedIn)) {
        unawaited(_service.refresh(reloadSubscriptions: true));
      }
    }
    if (!available) _service.clear();
    _wasSignedIn = signedIn;
    _channelCount = channels;
  }

  /// The most recent unfinished video that is not playing right now: the
  /// last opened one, else the latest saved position of a video still in
  /// the feed (covers videos watched before the card existed).
  ({YouTubeVideo video, ({double position, double duration}) progress})? _resumeVideo() {
    bool unfinished(({double position, double duration})? p) =>
        p != null && p.position >= 10 && p.position / p.duration < 0.95;

    final json = _settings.lastVideoJson;
    final last = json == null ? null : YouTubeVideo.fromJson(json);
    final candidates = <YouTubeVideo>[?last];
    final byId = {for (final video in _service.videos) video.id: video};
    for (final id in _settings.recentProgressIds.take(50)) {
      final video = byId[id];
      if (video != null && video.id != last?.id) candidates.add(video);
    }
    final dismissed = _settings.dismissedResumes.toSet();
    for (final video in candidates) {
      if (dismissed.contains(video.id) || YouTubePlayerScreen.isPlaying(video.id)) continue;
      final progress = _settings.progressOf(video.id);
      if (unfinished(progress)) return (video: video, progress: progress!);
    }
    return null;
  }

  void _openChannels() {
    Navigator.of(context).push(ytRoute<void>('channels', (_) => const YouTubeChannelsScreen()));
  }

  void _openGuide() {
    Navigator.of(context).push(ytRoute<void>('settings', (_) => const YouTubeGuideScreen()));
  }

  void _openSettings() {
    Navigator.of(context).push(ytRoute<void>('settings', (_) => const YouTubeSettingsScreen()));
  }

  Future<void> _open(YouTubeVideo video) => YouTubePlayerScreen.open(context, [video]);

  Future<void> _playWatchlist({int startIndex = 0}) =>
      YouTubePlayerScreen.open(context, _watchlist.items, startIndex: startIndex, fromWatchlist: true);

  /// Segmented buttons in the theme's highlight: the selected segment is a
  /// darker shade of it with light text, unselected ones stay light and muted.
  ButtonStyle _segmentStyle(BuildContext context) {
    final mono = tokens(context);
    final accent = playerActiveColor(context);
    final selectedBg = Color.lerp(accent, Colors.black, 0.55)!;
    final idleBg = Color.lerp(mono.surface, Colors.white, 0.07)!;
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? selectedBg : idleBg),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : mono.textMuted,
      ),
      side: WidgetStateProperty.resolveWith(
        (s) => BorderSide(color: s.contains(WidgetState.selected) ? accent : mono.outline),
      ),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListenableBuilder(
        listenable: Listenable.merge([_settings, _service, _watchlist, YouTubeChannels.instance, DeArrow.instance]),
        builder: (context, _) {
          if (!_settings.isLoaded || !YouTubeChannels.instance.isLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!YouTubeService.isAvailable) {
            return _ConnectPrompt(onAddChannels: _openChannels, onSignIn: _openSettings, onGuide: _openGuide);
          }
          return _view == _YtView.watchlist ? _buildWatchlist(context) : _buildFeed(context);
        },
      ),
    );
  }

  Widget _buildFeed(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final videos = _service.visibleVideos(sort: _sort, filter: _filter);
    final error = _service.error;
    final updated = _service.lastUpdated;
    final subtitle = _sort == YouTubeSort.relevant ? YtStrings.relevantSubtitle : YtStrings.newestSubtitle;
    final banner = _settings.hiddenBannerDismissed
        ? null
        : !_settings.showShorts && !_settings.showPremieres
        ? YtStrings.hiddenBanner
        : !_settings.showShorts
        ? YtStrings.shortsHiddenBanner
        : !_settings.showPremieres
        ? YtStrings.premieresHiddenBanner
        : null;

    return RefreshIndicator(
      onRefresh: () => _service.refresh(reloadSubscriptions: true),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.end,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        YtStrings.subscriptions,
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _service.isLoading && _service.channelCount > 0
                            ? YtStrings.loadingChannels(_service.channelsDone, _service.channelCount)
                            : updated == null
                            ? subtitle
                            : '$subtitle · ${YtStrings.updatedAgo(YtStrings.age(updated))}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: mono.textMuted),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _viewSwitch(context),
                      SegmentedButton<YouTubeSort>(
                        style: _segmentStyle(context),
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: YouTubeSort.newest, label: Text(YtStrings.newest)),
                          ButtonSegment(value: YouTubeSort.relevant, label: Text(YtStrings.mostRelevant)),
                        ],
                        selected: {_sort},
                        onSelectionChanged: (s) => setState(() => _sort = s.first),
                      ),
                      SegmentedButton<YouTubeFilter>(
                        style: _segmentStyle(context),
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: YouTubeFilter.all, label: Text(YtStrings.all)),
                          ButtonSegment(value: YouTubeFilter.unwatched, label: Text(YtStrings.unwatched)),
                          ButtonSegment(value: YouTubeFilter.continueWatching, label: Text(YtStrings.continueWatching)),
                        ],
                        selected: {_filter},
                        onSelectionChanged: (s) => setState(() => _filter = s.first),
                      ),
                      IconButton(
                        tooltip: YtStrings.refresh,
                        onPressed: _service.isLoading ? null : () => unawaited(_service.refresh(reloadSubscriptions: true)),
                        icon: _service.isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const AppIcon(Symbols.refresh_rounded),
                      ),
                      IconButton(
                        tooltip: YtStrings.channels,
                        onPressed: _openChannels,
                        icon: const AppIcon(Symbols.subscriptions_rounded),
                      ),
                      IconButton(
                        tooltip: YtStrings.guide,
                        onPressed: _openGuide,
                        icon: const AppIcon(Symbols.help_rounded),
                      ),
                      IconButton(
                        tooltip: YtStrings.settings,
                        onPressed: _openSettings,
                        icon: const AppIcon(Symbols.settings_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_resumeVideo() case final resume?)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
              sliver: SliverToBoxAdapter(child: _ResumeCard(video: resume.video, progress: resume.progress)),
            ),
          if (_service.isLoading)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
              sliver: SliverToBoxAdapter(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _service.progress,
                    minHeight: 3,
                    color: playerActiveColor(context),
                    backgroundColor: mono.outline,
                  ),
                ),
              ),
            ),
          if (banner != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
              sliver: SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: mono.surface,
                    borderRadius: BorderRadius.circular(mono.radiusMd),
                    border: Border.all(color: mono.outline),
                  ),
                  child: Row(
                    children: [
                      AppIcon(Symbols.filter_alt_rounded, size: 18, color: playerActiveColor(context)),
                      const SizedBox(width: 10),
                      Flexible(child: Text(banner)),
                      const SizedBox(width: 8),
                      TextButton(onPressed: _openSettings, child: Text(YtStrings.changeInSettings)),
                      const Spacer(),
                      IconButton(
                        tooltip: YtStrings.dismiss,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => unawaited(_settings.dismissHiddenBanner()),
                        icon: const AppIcon(Symbols.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (error != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
              sliver: SliverToBoxAdapter(
                child: _ErrorCard(
                  error: error,
                  onRetry: error is YouTubeAuthException && error.signedOut
                      ? _openSettings
                      : () => unawaited(_service.refresh()),
                ),
              ),
            ),
          if (videos.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  _service.isLoading ? YtStrings.loading : YtStrings.empty,
                  style: theme.textTheme.bodyLarge?.copyWith(color: mono.textMuted),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 360,
                  mainAxisSpacing: 28,
                  crossAxisSpacing: 24,
                  childAspectRatio: 1.05,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _VideoCard(
                    video: videos[i],
                    watched: _settings.isWatched(videos[i].id),
                    progress: _settings.progressFraction(videos[i].id),
                    reason: _sort == YouTubeSort.relevant ? _service.relevanceReason(videos[i]) : null,
                    trendFactor: _service.trendFactor(videos[i]),
                    onTap: () => unawaited(_open(videos[i])),
                    inWatchlist: _watchlist.contains(videos[i].id),
                    onToggleWatchlist: () => unawaited(_watchlist.toggle(videos[i])),
                    onMenu: (position) => unawaited(_showVideoMenu(videos[i], position)),
                  ),
                  childCount: videos.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showVideoMenu(YouTubeVideo video, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final favorite = _settings.isFavorite(video.channelId);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(
          value: 'watchlist',
          child: Text(_watchlist.contains(video.id) ? YtStrings.removeFromWatchlist : YtStrings.addToWatchlist),
        ),
        PopupMenuItem(value: 'channel', child: Text(YtStrings.openChannel)),
        PopupMenuItem(
          value: 'favorite',
          child: Text(favorite ? YtStrings.unfavoriteChannel : YtStrings.favoriteChannelAction),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'hide', child: Text(YtStrings.notInterested)),
        PopupMenuItem(value: 'mute', child: Text(YtStrings.muteChannel(video.channelTitle))),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'watchlist':
        await _watchlist.toggle(video);
      case 'channel':
        await Navigator.of(context).push(
          ytRoute<void>('channel', (_) => YouTubeChannelScreen(channelId: video.channelId, channelTitle: video.channelTitle),
          ),
        );
      case 'favorite':
        await _settings.setFavorite(video.channelId, video.channelTitle, !favorite);
      case 'hide':
        await _settings.hideVideo(video.id);
      case 'mute':
        await _settings.setMuted(video.channelId, video.channelTitle, true);
    }
  }

  Widget _viewSwitch(BuildContext context) {
    return SegmentedButton<_YtView>(
      style: _segmentStyle(context),
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: _YtView.subscriptions, label: Text(YtStrings.subscriptions)),
        ButtonSegment(value: _YtView.watchlist, label: Text(YtStrings.watchlistCount(_watchlist.length))),
      ],
      selected: {_view},
      onSelectionChanged: (s) => setState(() => _view = s.first),
    );
  }

  Widget _buildWatchlist(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final items = _watchlist.items;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.end,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: YtStrings.back,
                      onPressed: () => setState(() => _view = _YtView.subscriptions),
                      icon: const AppIcon(Symbols.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      YtStrings.watchlist,
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(YtStrings.watchlistSubtitle, style: theme.textTheme.bodyMedium?.copyWith(color: mono.textMuted)),
                  ],
                ),
                  ],
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _viewSwitch(context),
                    FilledButton.icon(
                      onPressed: items.isEmpty ? null : () => unawaited(_playWatchlist()),
                      icon: const AppIcon(Symbols.play_arrow_rounded, fill: 1),
                      label: Text(YtStrings.playAll),
                    ),
                    TextButton(
                      onPressed: items.isEmpty ? null : () => unawaited(_watchlist.clear()),
                      child: Text(YtStrings.clearWatchlist),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                YtStrings.watchlistEmpty,
                style: theme.textTheme.bodyLarge?.copyWith(color: mono.textMuted),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
            sliver: SliverReorderableList(
              itemCount: items.length,
              onReorder: (a, b) => unawaited(_watchlist.reorder(a, b)),
              itemBuilder: (context, i) => _WatchlistRow(
                key: ValueKey(items[i].id),
                index: i,
                video: items[i],
                onTap: () => unawaited(_playWatchlist(startIndex: i)),
                onRemove: () => unawaited(_watchlist.remove(items[i].id)),
              ),
            ),
          ),
      ],
    );
  }
}

class _VideoCard extends StatefulWidget {
  const _VideoCard({
    required this.video,
    required this.watched,
    required this.progress,
    required this.reason,
    required this.trendFactor,
    required this.onTap,
    required this.inWatchlist,
    required this.onToggleWatchlist,
    required this.onMenu,
  });

  final ValueChanged<Offset> onMenu;
  final YouTubeVideo video;
  final bool watched;

  /// Fraction watched, from the saved resume position.
  final double? progress;
  final YouTubeRelevanceReason? reason;
  final double trendFactor;
  final VoidCallback onTap;
  final bool inWatchlist;
  final VoidCallback onToggleWatchlist;

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  bool _highlighted = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final accent = playerActiveColor(context);
    final gradient = PlayerStyle.of(context).progressGradient;
    final video = widget.video;
    final badge = video.isLive
        ? YtStrings.live
        : video.isUpcoming
        ? YtStrings.upcoming
        : (video.duration > Duration.zero ? YtStrings.duration(video.duration) : null);

    String? reasonText;
    Color? reasonColor;
    switch (widget.reason) {
      case YouTubeRelevanceReason.trending:
        reasonText = YtStrings.trending(widget.trendFactor.toStringAsFixed(widget.trendFactor >= 10 ? 0 : 1));
        reasonColor = gradient?.last ?? accent;
      case YouTubeRelevanceReason.favoriteChannel:
        reasonText = YtStrings.favoriteChannel;
        reasonColor = gradient?.first ?? accent;
      case null:
        break;
    }

    return Semantics(
      button: true,
      label: '${video.title}, ${video.channelTitle}',
      excludeSemantics: true,
      child: GestureDetector(
        onSecondaryTapUp: (d) => widget.onMenu(d.globalPosition),
        onLongPressStart: (d) => widget.onMenu(d.globalPosition),
        child: InkWell(
        onTap: widget.onTap,
        onHover: (h) => setState(() => _highlighted = h),
        onFocusChange: (f) => setState(() => _highlighted = f),
        borderRadius: BorderRadius.circular(mono.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: AnimatedContainer(
                  duration: mono.fast,
                  decoration: BoxDecoration(
                    color: RetroColors.dusk,
                    borderRadius: BorderRadius.circular(mono.radiusMd),
                    border: Border.all(color: _highlighted ? accent : mono.outline, width: _highlighted ? 2 : 1),
                    boxShadow: _highlighted ? [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 16)] : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (DeArrow.instance.thumbnailFor(video) case final thumb?)
                        CachedNetworkImage(
                          imageUrl: thumb,
                          fit: BoxFit.cover,
                          memCacheWidth: 480,
                          errorWidget: (_, _, _) => video.thumbnailUrl == null || video.thumbnailUrl == thumb
                              ? const SizedBox.shrink()
                              : CachedNetworkImage(imageUrl: video.thumbnailUrl!, fit: BoxFit.cover),
                        ),
                      if (widget.watched)
                        Positioned(left: 8, bottom: 10, child: _Chip(text: YtStrings.watched)),
                      if (badge != null) Positioned(right: 8, bottom: 8, child: _Chip(text: badge)),
                      Positioned(
                        left: 6,
                        top: 6,
                        child: _WatchlistButton(active: widget.inWatchlist, onPressed: widget.onToggleWatchlist),
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Builder(
                          builder: (buttonContext) => Tooltip(
                            message: YtStrings.moreOptions,
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.7),
                              shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.35))),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  final box = buttonContext.findRenderObject() as RenderBox;
                                  widget.onMenu(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
                                },
                                child: const SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: Center(child: AppIcon(Symbols.more_vert_rounded, size: 20, color: Colors.white)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (widget.watched || (widget.progress ?? 0) > 0)
                        Positioned(
                          left: 0,
                          bottom: 0,
                          height: 4,
                          right: 0,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: (widget.progress ?? 1.0).clamp(0.02, 1.0),
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
                DeArrow.instance.titleFor(video),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
              ),
              const SizedBox(height: 4),
              Text(
                '${YouTubeSettings.instance.isFavorite(video.channelId) ? '★ ' : ''}${video.channelTitle} · ${YtStrings.age(video.publishedAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted),
              ),
              if (reasonText != null) ...[
                const SizedBox(height: 4),
                Text(
                  reasonText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: reasonColor, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(5)),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: mono.surface,
        borderRadius: BorderRadius.circular(mono.radiusMd),
        border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          AppIcon(Symbols.error_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(YtStrings.errorTitle, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(error.toString(), style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(onPressed: onRetry, child: Text(YtStrings.retry)),
        ],
      ),
    );
  }
}

class _ConnectPrompt extends StatelessWidget {
  const _ConnectPrompt({required this.onAddChannels, required this.onSignIn, required this.onGuide});

  final VoidCallback onAddChannels;
  final VoidCallback onSignIn;
  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(Symbols.smart_display_rounded, size: 56, color: playerActiveColor(context)),
              const SizedBox(height: 16),
              Text(YtStrings.connectTitle, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                YtStrings.connectBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: mono.textMuted),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: onAddChannels,
                    icon: const AppIcon(Symbols.subscriptions_rounded, size: 18),
                    label: Text(YtStrings.addChannelsNoAccount),
                  ),
                  OutlinedButton.icon(
                    onPressed: onSignIn,
                    icon: const AppIcon(Symbols.account_circle_rounded, size: 18),
                    label: Text(YtStrings.signInOptional),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onGuide,
                icon: const AppIcon(Symbols.help_rounded, size: 18),
                label: Text(YtStrings.guide),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WatchlistButton extends StatelessWidget {
  const _WatchlistButton({required this.active, required this.onPressed});

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = playerActiveColor(context);
    return Tooltip(
      message: active ? YtStrings.removeFromWatchlist : YtStrings.addToWatchlist,
      child: Material(
        color: active ? Color.lerp(accent, Colors.black, 0.55) : Colors.black.withValues(alpha: 0.7),
        shape: CircleBorder(side: BorderSide(color: active ? accent : Colors.white.withValues(alpha: 0.35))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: AppIcon(active ? Symbols.check_rounded : Symbols.add_rounded, size: 20, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _WatchlistRow extends StatelessWidget {
  const _WatchlistRow({
    super.key,
    required this.index,
    required this.video,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final YouTubeVideo video;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: mono.surface,
        borderRadius: BorderRadius.circular(mono.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(mono.radiusMd),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Tooltip(
                    message: YtStrings.dragToReorder,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: AppIcon(Symbols.drag_indicator_rounded, color: mono.textMuted),
                    ),
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(color: mono.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(mono.radiusSm),
                  child: SizedBox(
                    width: 160,
                    height: 90,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: RetroColors.dusk),
                        if (video.thumbnailUrl != null)
                          CachedNetworkImage(
                            imageUrl: video.thumbnailUrl!,
                            fit: BoxFit.cover,
                          memCacheWidth: 480,
                            errorWidget: (_, _, _) => const SizedBox.shrink(),
                          ),
                        if (video.duration > Duration.zero)
                          Positioned(right: 6, bottom: 6, child: _Chip(text: YtStrings.duration(video.duration))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${video.channelTitle} · ${YtStrings.age(video.publishedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: YtStrings.removeFromWatchlist,
                  onPressed: onRemove,
                  icon: const AppIcon(Symbols.close_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One click back into the last unfinished video, where it stopped.
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.video, required this.progress});

  final YouTubeVideo video;
  final ({double position, double duration}) progress;

  static String _clock(double seconds) {
    final d = Duration(seconds: seconds.round());
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final style = PlayerStyle.of(context);
    final fraction = (progress.position / progress.duration).clamp(0.0, 1.0);
    final title = YouTubeSettings.instance.deArrowTitles ? DeArrow.instance.titleFor(video) : video.title;
    void resume() => unawaited(YouTubePlayerScreen.open(context, [video]));

    return Material(
      color: mono.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(mono.radiusMd),
        side: BorderSide(color: playerActiveColor(context).withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: resume,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 160,
                  height: 90,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (video.thumbnailUrl != null)
                        CachedNetworkImage(imageUrl: video.thumbnailUrl!, fit: BoxFit.cover)
                      else
                        ColoredBox(color: mono.outline),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: FractionallySizedBox(
                          widthFactor: fraction,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: style.progressGradient ?? [playerActiveColor(context), playerActiveColor(context)],
                              ),
                            ),
                            child: const SizedBox(height: 4, width: double.infinity),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(YtStrings.resumeWatching, style: theme.textTheme.labelMedium?.copyWith(color: mono.textMuted)),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${video.channelTitle} · ${_clock(progress.position)} / ${_clock(progress.duration)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: resume,
                icon: const AppIcon(Symbols.play_arrow_rounded, fill: 1, size: 20),
                label: Text(YtStrings.resumeAt(_clock(progress.position))),
              ),
              IconButton(
                tooltip: YtStrings.dismiss,
                onPressed: () => unawaited(YouTubeSettings.instance.dismissResume(video.id)),
                icon: const AppIcon(Symbols.close_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
