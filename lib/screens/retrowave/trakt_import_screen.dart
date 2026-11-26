import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/retro_strings.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/trackers/trakt/trakt_tracker.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import '../../utils/provider_extensions.dart';
import '../../widgets/desktop_app_bar.dart';

/// Fork: marks everything watched on Trakt as watched on the connected
/// servers. Titles are matched by their IMDb, TMDB and TVDB ids; only
/// unwatched items are changed, nothing is ever marked unwatched.
class TraktImportScreen extends StatefulWidget {
  const TraktImportScreen({super.key});

  @override
  State<TraktImportScreen> createState() => _TraktImportScreenState();
}

class _TraktImportScreenState extends State<TraktImportScreen> {
  bool _running = false;
  bool _done = false;
  bool _failed = false;
  String _status = '';
  int _movies = 0;
  int _episodes = 0;
  int _missing = 0;

  ExternalIds _ids(Map? ids) => ExternalIds(
    imdb: ids?['imdb'] as String?,
    tmdb: (ids?['tmdb'] as num?)?.toInt(),
    tvdb: (ids?['tvdb'] as num?)?.toInt(),
  );

  Future<void> _run() async {
    final client = TraktTracker.instance.client;
    if (client == null) return;
    final servers = [
      for (final id in context.read<MultiServerProvider>().onlineServerIds)
        ?context.tryGetMediaClientForServer(ServerId(id)),
    ];
    setState(() {
      _running = true;
      _done = false;
      _failed = false;
      _movies = 0;
      _episodes = 0;
      _missing = 0;
      _status = RetroStrings.traktReading;
    });
    try {
      final movies = await client.getWatchedMovies();
      final shows = await client.getWatchedShows();
      var n = 0;
      for (final raw in movies.whereType<Map>()) {
        final movie = raw['movie'] as Map?;
        if (movie == null) continue;
        n++;
        if (n % 10 == 0 && mounted) setState(() => _status = RetroStrings.traktProgress(n, movies.length + shows.length));
        final found = await _find(servers, _ids(movie['ids'] as Map?), MediaKind.movie, movie);
        if (found.isEmpty) _missing++;
        for (final (server, item) in found) {
          if (item.isWatched) continue;
          await server.markWatched(item);
          _movies++;
        }
        if (!mounted) return;
      }
      for (final raw in shows.whereType<Map>()) {
        final show = raw['show'] as Map?;
        if (show == null) continue;
        n++;
        if (mounted) setState(() => _status = RetroStrings.traktProgress(n, movies.length + shows.length));
        final watched = <String>{
          for (final season in (raw['seasons'] as List? ?? const []).whereType<Map>())
            for (final ep in (season['episodes'] as List? ?? const []).whereType<Map>())
              '${season['number']}x${ep['number']}',
        };
        final found = await _find(servers, _ids(show['ids'] as Map?), MediaKind.show, show);
        if (found.isEmpty) _missing++;
        for (final (server, item) in found) {
          final episodes = await server.fetchPlayableDescendants(item.id);
          for (final ep in episodes) {
            if (ep.isWatched) continue;
            if (!watched.contains('${ep.parentIndex}x${ep.index}')) continue;
            await server.markWatched(ep);
            _episodes++;
          }
        }
        if (!mounted) return;
      }
    } catch (e, st) {
      appLogger.w('Trakt import failed', error: e, stackTrace: st);
      _failed = true;
    }
    if (mounted) {
      setState(() {
        _running = false;
        _done = true;
      });
    }
  }

  Future<List<(MediaServerClient, MediaItem)>> _find(
    List<MediaServerClient> servers,
    ExternalIds ids,
    MediaKind kind,
    Map title,
  ) async {
    final out = <(MediaServerClient, MediaItem)>[];
    for (final server in servers) {
      try {
        final items = await server.findByExternalIds(
          ids,
          kind: kind,
          titles: [?title['title'] as String?],
          year: (title['year'] as num?)?.toInt(),
        );
        if (items != null && items.isNotEmpty) out.add((server, items.first));
      } catch (_) {}
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final theme = Theme.of(context);
    final connected = TraktTracker.instance.client != null;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          CustomAppBar(title: Text(RetroStrings.traktImport)),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList.list(
              children: [
                Text(RetroStrings.traktImportHelp, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 20),
                if (!connected)
                  Text(RetroStrings.traktNotConnected, style: TextStyle(color: mono.textMuted))
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      autofocus: true,
                      onPressed: _running ? null : () => unawaited(_run()),
                      child: Text(RetroStrings.traktImportStart),
                    ),
                  ),
                const SizedBox(height: 20),
                if (_running) ...[const LinearProgressIndicator(), const SizedBox(height: 8)],
                if (_status.isNotEmpty && !_done) Text(_status, style: TextStyle(color: mono.textMuted)),
                if (_done && _failed) Text(RetroStrings.traktFailed, style: theme.textTheme.titleMedium),
                if (_done) Text(RetroStrings.traktImportDone(_movies, _episodes, _missing), style: theme.textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
