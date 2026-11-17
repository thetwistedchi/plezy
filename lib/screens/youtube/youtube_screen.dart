import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/youtube/youtube_auth.dart';
import '../../services/youtube/youtube_service.dart';
import '../../services/youtube/youtube_settings.dart';
import '../../theme/mono_tokens.dart';
import '../../theme/player_style.dart';
import '../../widgets/app_icon.dart';
import 'youtube_settings_screen.dart';
import 'youtube_strings.dart';

/// The YouTube tab: newest uploads of the signed-in user's subscriptions.
class YouTubeScreen extends StatefulWidget {
  const YouTubeScreen({super.key});

  @override
  State<YouTubeScreen> createState() => _YouTubeScreenState();
}

class _YouTubeScreenState extends State<YouTubeScreen> {
  final _settings = YouTubeSettings.instance;
  final _service = YouTubeService.instance;
  YouTubeSort _sort = YouTubeSort.newest;
  bool _unwatchedOnly = false;
  bool _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    unawaited(_settings.load().then((_) => _onSettingsChanged()));
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    final signedIn = _settings.isSignedIn;
    if (signedIn && !_wasSignedIn) _service.ensureStarted();
    if (!signedIn && _wasSignedIn) _service.clear();
    _wasSignedIn = signedIn;
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const YouTubeSettingsScreen()));
  }

  Future<void> _open(YouTubeVideo video) async {
    unawaited(_settings.markOpened(video.id, video.channelId));
    await launchUrl(video.watchUrl, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListenableBuilder(
        listenable: Listenable.merge([_settings, _service]),
        builder: (context, _) {
          if (!_settings.isLoaded) return const Center(child: CircularProgressIndicator());
          if (!_settings.isSignedIn) return _ConnectPrompt(onSetUp: _openSettings);
          return _buildFeed(context);
        },
      ),
    );
  }

  Widget _buildFeed(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final videos = _service.visibleVideos(sort: _sort, unwatchedOnly: _unwatchedOnly);
    final error = _service.error;
    final updated = _service.lastUpdated;
    final subtitle = _sort == YouTubeSort.relevant ? YtStrings.relevantSubtitle : YtStrings.newestSubtitle;
    final banner = !_settings.showShorts && !_settings.showPremieres
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
                      SegmentedButton<YouTubeSort>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: YouTubeSort.newest, label: Text(YtStrings.newest)),
                          ButtonSegment(value: YouTubeSort.relevant, label: Text(YtStrings.mostRelevant)),
                        ],
                        selected: {_sort},
                        onSelectionChanged: (s) => setState(() => _sort = s.first),
                      ),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: false, label: Text(YtStrings.all)),
                          ButtonSegment(value: true, label: Text(YtStrings.unwatched)),
                        ],
                        selected: {_unwatchedOnly},
                        onSelectionChanged: (s) => setState(() => _unwatchedOnly = s.first),
                      ),
                      IconButton(
                        tooltip: YtStrings.refresh,
                        onPressed: _service.isLoading ? null : () => unawaited(_service.refresh(reloadSubscriptions: true)),
                        icon: _service.isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const AppIcon(Symbols.refresh_rounded),
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
                    reason: _sort == YouTubeSort.relevant ? _service.relevanceReason(videos[i]) : null,
                    trendFactor: _service.trendFactor(videos[i]),
                    onTap: () => unawaited(_open(videos[i])),
                  ),
                  childCount: videos.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoCard extends StatefulWidget {
  const _VideoCard({
    required this.video,
    required this.watched,
    required this.reason,
    required this.trendFactor,
    required this.onTap,
  });

  final YouTubeVideo video;
  final bool watched;
  final YouTubeRelevanceReason? reason;
  final double trendFactor;
  final VoidCallback onTap;

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
                    color: const Color(0xFF1B1240),
                    borderRadius: BorderRadius.circular(mono.radiusMd),
                    border: Border.all(color: _highlighted ? accent : mono.outline, width: _highlighted ? 2 : 1),
                    boxShadow: _highlighted ? [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 16)] : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (video.thumbnailUrl != null)
                        CachedNetworkImage(
                          imageUrl: video.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                      if (widget.watched)
                        Positioned(left: 8, top: 8, child: _Chip(text: YtStrings.watched)),
                      if (badge != null) Positioned(right: 8, bottom: 8, child: _Chip(text: badge)),
                      if (widget.watched)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: gradient != null && gradient.length >= 2 ? LinearGradient(colors: gradient) : null,
                              color: gradient == null || gradient.length < 2 ? accent : null,
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
                '${video.channelTitle} · ${YtStrings.age(video.publishedAt)}',
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
  const _ConnectPrompt({required this.onSetUp});

  final VoidCallback onSetUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
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
              FilledButton(onPressed: onSetUp, child: Text(YtStrings.openSettings)),
            ],
          ),
        ),
      ),
    );
  }
}
