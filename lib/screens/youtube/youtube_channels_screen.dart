import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/file_picker_service.dart';
import '../../services/youtube/youtube_channels.dart';
import '../../services/youtube/youtube_service.dart';
import '../../services/youtube/youtube_settings.dart';
import '../../theme/mono_tokens.dart';
import '../../theme/player_style.dart';
import '../../widgets/app_icon.dart';
import 'youtube_channel_screen.dart';
import 'youtube_guide_screen.dart';
import 'youtube_strings.dart';
import 'youtube_routes.dart';

/// Manage the channels followed without a Google account.
class YouTubeChannelsScreen extends StatefulWidget {
  const YouTubeChannelsScreen({super.key});

  @override
  State<YouTubeChannelsScreen> createState() => _YouTubeChannelsScreenState();
}

class _YouTubeChannelsScreenState extends State<YouTubeChannelsScreen> {
  final _channels = YouTubeChannels.instance;
  final _input = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_channels.load());
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final channel = await _channels.resolve(text);
      if (channel == null) {
        _snack(YtStrings.channelNotFound);
        return;
      }
      final added = await _channels.add(channel);
      _snack(added ? YtStrings.added(channel.title) : YtStrings.alreadyFollowed);
      if (added) _input.clear();
    } catch (e) {
      _snack('${YtStrings.channelNotFound}\n$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final result = await FilePickerService.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) return;
    String text;
    if (file.bytes != null) {
      text = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null) {
      text = await File(file.path!).readAsString();
    } else {
      return;
    }
    final count = await _channels.importTakeoutCsv(text);
    _snack(YtStrings.imported(count));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final accent = playerActiveColor(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(YtStrings.channelsTitle),
        actions: [
          const YouTubeHomeButton(),
          IconButton(
            tooltip: YtStrings.guide,
            onPressed: () =>
                Navigator.of(context).push(ytRoute<void>('guide', (_) => const YouTubeGuideScreen())),
            icon: const AppIcon(Symbols.help_rounded),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _channels,
        builder: (context, _) {
          final channels = _channels.channels;
          final googleCount = YouTubeSettings.instance.isSignedIn ? YouTubeService.instance.channelCount : 0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        YtStrings.channelsSubtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(color: mono.textMuted),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _input,
                              enabled: !_busy,
                              decoration: InputDecoration(
                                hintText: YtStrings.addChannelHint,
                                prefixIcon: const AppIcon(Symbols.link_rounded),
                              ),
                              onSubmitted: (_) => unawaited(_add()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: _busy ? null : () => unawaited(_add()),
                            child: _busy
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(YtStrings.add),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => unawaited(_import()),
                            icon: const AppIcon(Symbols.upload_file_rounded, size: 18),
                            label: Text(YtStrings.importTakeout),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              YtStrings.importTakeoutHelp,
                              style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text(
                            '${YtStrings.channels.toUpperCase()}  ${channels.length}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const Spacer(),
                          if (channels.isNotEmpty)
                            TextButton(
                              onPressed: () => unawaited(_channels.clear()),
                              child: Text(YtStrings.removeAllChannels),
                            ),
                        ],
                      ),
                      if (googleCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            YtStrings.googleChannels(googleCount),
                            style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted),
                          ),
                        ),
                      const SizedBox(height: 4),
                      if (channels.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            YtStrings.noChannels,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: mono.textMuted),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: mono.surface,
                            borderRadius: BorderRadius.circular(mono.radiusLg),
                            border: Border.all(color: mono.outline),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (final channel in channels)
                                ListTile(
                                  leading: AppIcon(Symbols.account_box_rounded, color: mono.textMuted),
                                  title: Text(channel.title),
                                  subtitle: Text(channel.id, style: TextStyle(color: mono.textMuted, fontSize: 12)),
                                  onTap: () => Navigator.of(context).push(
                                    ytRoute<void>('channel', (_) =>
                                          YouTubeChannelScreen(channelId: channel.id, channelTitle: channel.title),
                                    ),
                                  ),
                                  trailing: IconButton(
                                    tooltip: YtStrings.removeChannel,
                                    onPressed: () => unawaited(_channels.remove(channel.id)),
                                    icon: const AppIcon(Symbols.close_rounded),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
