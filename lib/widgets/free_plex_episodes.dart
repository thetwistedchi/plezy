import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/retro_strings.dart';

/// Fork: a show's seasons and episodes in Plex's free catalog, on its details
/// page. Seasons in a row (Left/Right); OK on one lists its episodes below
/// (Up/Down, OK plays), OK on it again hides them.
class FreePlexEpisodes extends StatefulWidget {
  const FreePlexEpisodes({
    super.key,
    required this.seasons,
    required this.loadEpisodes,
    required this.onPlay,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  final List<({String key, String title})> seasons;
  final Future<List<({String key, String title, int? index, String? summary, int? minutes})>> Function(String seasonKey)
  loadEpisodes;
  final ValueChanged<String> onPlay;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;

  @override
  State<FreePlexEpisodes> createState() => FreePlexEpisodesState();
}

class FreePlexEpisodesState extends State<FreePlexEpisodes> {
  /// The season whose episodes are listed, -1 for none (less clutter).
  int _season = -1;
  List<({String key, String title, int? index, String? summary, int? minutes})>? _episodes;
  bool _failed = false;
  int _load = 0;
  late List<FocusNode> _seasonNodes = _nodes(widget.seasons.length, 'season');
  List<FocusNode> _episodeNodes = const [];

  static List<FocusNode> _nodes(int n, String label) => [for (var i = 0; i < n; i++) FocusNode(debugLabel: 'free_plex_$label$i')];

  @override
  void didUpdateWidget(FreePlexEpisodes old) {
    super.didUpdateWidget(old);
    if (old.seasons.length != widget.seasons.length) {
      for (final n in _seasonNodes) {
        n.dispose();
      }
      _seasonNodes = _nodes(widget.seasons.length, 'season');
      if (_season >= widget.seasons.length) setState(() => _season = -1);
    }
  }

  @override
  void dispose() {
    for (final n in [..._seasonNodes, ..._episodeNodes]) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSeason(int index) async {
    if (widget.seasons.isEmpty) return;
    final run = ++_load;
    if (index == _season) {
      // Again: the list closes.
      for (final n in _episodeNodes) {
        n.dispose();
      }
      setState(() {
        _season = -1;
        _episodes = null;
        _episodeNodes = const [];
      });
      return;
    }
    setState(() {
      _season = index;
      _episodes = null;
      _failed = false;
    });
    try {
      final episodes = await widget.loadEpisodes(widget.seasons[index].key);
      if (!mounted || run != _load) return;
      for (final n in _episodeNodes) {
        n.dispose();
      }
      setState(() {
        _episodes = episodes;
        _episodeNodes = _nodes(episodes.length, 'episode');
      });
    } catch (_) {
      if (!mounted || run != _load) return;
      setState(() => _failed = true);
    }
  }

  /// Focus from above: the season row.
  void focusFirst() => _focus(_seasonNodes.isNotEmpty ? _seasonNodes[_season.clamp(0, _seasonNodes.length - 1)] : null);

  /// Focus from below: the last episode, else the season row.
  void focusLast() => _episodeNodes.isNotEmpty ? _focus(_episodeNodes.last) : focusFirst();

  void _focus(FocusNode? node) {
    if (node == null) return;
    node.requestFocus();
    final ctx = node.context;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.35, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  static bool _isSelect(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA;

  KeyEventResult _keys(KeyEvent e, {VoidCallback? up, VoidCallback? down, VoidCallback? left, VoidCallback? right, VoidCallback? ok}) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return _isSelect(e.logicalKey) ? KeyEventResult.handled : KeyEventResult.ignored;
    final k = e.logicalKey;
    VoidCallback? action;
    if (k == LogicalKeyboardKey.arrowUp) {
      action = up;
    } else if (k == LogicalKeyboardKey.arrowDown) {
      action = down;
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      action = left ?? () {};
    } else if (k == LogicalKeyboardKey.arrowRight) {
      action = right ?? () {};
    } else if (_isSelect(k)) {
      if (e is KeyRepeatEvent) return KeyEventResult.handled;
      action = ok;
    }
    if (action == null) return KeyEventResult.ignored;
    action();
    return KeyEventResult.handled;
  }

  Widget _tile({
    required FocusNode node,
    required Widget child,
    required VoidCallback onTap,
    required FocusOnKeyEventCallback onKey,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    bool selected = false,
  }) {
    final theme = Theme.of(context);
    return Focus(
      focusNode: node,
      onKeyEvent: onKey,
      onFocusChange: (_) => setState(() {}),
      child: Builder(
        builder: (context) {
          final focused = node.hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.22)
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              border: Border.all(
                color: focused ? theme.colorScheme.primary : Colors.white.withValues(alpha: 0.08),
                width: focused ? 2.5 : 1,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                canRequestFocus: false,
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final episodes = _episodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(RetroStrings.freeOnPlexEpisodes, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (widget.seasons.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final (i, season) in widget.seasons.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _tile(
                    node: _seasonNodes[i],
                    selected: i == _season,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    onTap: () => _loadSeason(i),
                    onKey: (_, e) => _keys(
                      e,
                      up: widget.onNavigateUp,
                      down: () => _episodeNodes.isNotEmpty ? _focus(_episodeNodes.first) : widget.onNavigateDown?.call(),
                      left: i > 0 ? () => _focus(_seasonNodes[i - 1]) : null,
                      right: i < _seasonNodes.length - 1 ? () => _focus(_seasonNodes[i + 1]) : null,
                      ok: () => _loadSeason(i),
                    ),
                    child: Text(season.title),
                  ),
                ],
              ],
            ),
          ),
        if (_season >= 0) const SizedBox(height: 10),
        if (_season < 0)
          const SizedBox.shrink()
        else if (_failed)
          Text(RetroStrings.freeOnPlexFailed, style: theme.textTheme.bodySmall)
        else if (episodes == null)
          const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(minHeight: 3))
        else
          for (final (i, episode) in episodes.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _tile(
                node: _episodeNodes[i],
                onTap: () => widget.onPlay(episode.key),
                onKey: (_, e) => _keys(
                  e,
                  up: () => i > 0 ? _focus(_episodeNodes[i - 1]) : focusFirst(),
                  down: () => i < _episodeNodes.length - 1 ? _focus(_episodeNodes[i + 1]) : widget.onNavigateDown?.call(),
                  ok: () => widget.onPlay(episode.key),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(episode.index?.toString() ?? '', style: theme.textTheme.titleSmall),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(episode.title, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (episode.summary?.trim().isNotEmpty ?? false)
                            Text(
                              episode.summary!.trim(),
                              style: theme.textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (episode.minutes != null) ...[
                      const SizedBox(width: 12),
                      Text('${episode.minutes} min', style: theme.textTheme.bodySmall),
                    ],
                    const SizedBox(width: 8),
                    const Icon(Icons.play_arrow_rounded, size: 20),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
