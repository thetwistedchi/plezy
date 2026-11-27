import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/retro_strings.dart';
import '../../services/retrowave/audio/audio_extras.dart';
import '../../services/retrowave/audio/audio_settings.dart';
import '../../services/retrowave/audio/music_listen_tracker.dart';
import '../../services/settings_service.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_builder.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';
import 'settings_utils.dart';

/// Fork: settings of the music, audiobook and podcast player.
class AudioPlayerSettingsScreen extends StatelessWidget {
  const AudioPlayerSettingsScreen({super.key});

  static Future<void> _apply(Object? _) => AudioExtras.instance.applyAudioSettings();

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: Text(RetroStrings.audioSettings),
      children: [
        SettingsGroup(
          title: RetroStrings.statsMusic,
          children: [
            SettingSelectionTile<AudioLevelling>(
              pref: AudioSettings.levelling,
              icon: Symbols.graphic_eq_rounded,
              title: RetroStrings.audioLevelling,
              subtitleBuilder: RetroStrings.audioLevellingOption,
              onAfterWrite: _apply,
              options: [
                for (final l in AudioLevelling.values)
                  DialogOption(
                    value: l,
                    title: RetroStrings.audioLevellingOption(l),
                    subtitle: l == AudioLevelling.off ? null : RetroStrings.audioLevellingHint,
                  ),
              ],
            ),
            SettingSelectionTile<int>(
              pref: AudioSettings.fadeSeconds,
              icon: Symbols.blur_linear_rounded,
              title: RetroStrings.audioFade,
              subtitleBuilder: RetroStrings.audioSeconds,
              options: [
                for (final n in const [0, 2, 4, 6, 8, 10, 12])
                  DialogOption(value: n, title: RetroStrings.audioSeconds(n), subtitle: n == 0 ? null : RetroStrings.audioFadeHint),
              ],
            ),
            SettingSelectionTile<AudioEqPreset>(
              pref: AudioSettings.eqMusic,
              icon: Symbols.equalizer_rounded,
              title: RetroStrings.audioEqMusic,
              subtitleBuilder: RetroStrings.audioEqPreset,
              onAfterWrite: _apply,
              options: [
                for (final p in AudioEqPreset.values) DialogOption(value: p, title: RetroStrings.audioEqPreset(p)),
              ],
            ),
            SettingSwitchTile(
              pref: AudioSettings.onlineLyrics,
              icon: Symbols.lyrics_rounded,
              title: RetroStrings.audioOnlineLyrics,
              subtitle: RetroStrings.audioOnlineLyricsHint,
            ),
            SettingSwitchTile(
              pref: AudioSettings.musicNightMode,
              icon: Symbols.bedtime_rounded,
              title: RetroStrings.audioNightMode,
              subtitle: RetroStrings.audioNightModeHint,
              onAfterWrite: _apply,
            ),
          ],
        ),
        SettingsGroup(
          title: '${RetroStrings.audioMode(AudioMode.audiobook)}, ${RetroStrings.audioMode(AudioMode.audioDrama)}, '
              '${RetroStrings.audioMode(AudioMode.podcast)}',
          children: [
            SettingSelectionTile<AudioEqPreset>(
              pref: AudioSettings.eqSpoken,
              icon: Symbols.record_voice_over_rounded,
              title: RetroStrings.audioEqSpoken,
              subtitleBuilder: RetroStrings.audioEqPreset,
              onAfterWrite: _apply,
              options: [
                for (final p in AudioEqPreset.values) DialogOption(value: p, title: RetroStrings.audioEqPreset(p)),
              ],
            ),
            SettingSwitchTile(
              pref: AudioSettings.skipAdChapters,
              icon: Symbols.content_cut_rounded,
              title: RetroStrings.audioSkipAdChapters,
              subtitle: RetroStrings.audioSkipAdChaptersHint,
            ),
            const _AdKeywordsTile(),
            SettingSelectionTile<int>(
              pref: AudioSettings.skipBack,
              icon: Symbols.replay_10_rounded,
              title: RetroStrings.audioSkipBackSetting,
              subtitleBuilder: (n) => '$n s',
              options: [for (final n in const [5, 10, 30]) DialogOption(value: n, title: '$n s')],
            ),
            SettingSelectionTile<int>(
              pref: AudioSettings.skipForward,
              icon: Symbols.forward_30_rounded,
              title: RetroStrings.audioSkipForwardSetting,
              subtitleBuilder: (n) => '$n s',
              options: [for (final n in const [5, 10, 30]) DialogOption(value: n, title: '$n s')],
            ),
          ],
        ),
        SettingsGroup(
          title: RetroStrings.audioScrobbling,
          children: const [_ListenBrainzTile(), _LastFmTile()],
        ),
      ],
    );
  }
}

class _AdKeywordsTile extends StatelessWidget {
  const _AdKeywordsTile();

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: SettingsService.instance.read(AudioSettings.adKeywords));
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(RetroStrings.audioAdKeywords),
        content: SizedBox(
          width: 420,
          child: TextField(controller: controller, autofocus: true, minLines: 2, maxLines: 4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(MaterialLocalizations.of(context).saveButtonLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await SettingsService.instance.write(AudioSettings.adKeywords, value.trim());
  }

  @override
  Widget build(BuildContext context) => SettingValueBuilder<String>(
    pref: AudioSettings.adKeywords,
    builder: (context, words, _) => ListTile(
      leading: const AppIcon(Symbols.label_rounded, fill: 1),
      title: Text(RetroStrings.audioAdKeywords),
      subtitle: Text(words, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
      onTap: () => unawaited(_edit(context)),
    ),
  );
}

class _ListenBrainzTile extends StatelessWidget {
  const _ListenBrainzTile();

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: SettingsService.instance.read(AudioSettings.listenBrainzToken));
    final token = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(RetroStrings.listenBrainz),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(RetroStrings.listenBrainzHint),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(labelText: RetroStrings.scrobbleToken),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(RetroStrings.scrobbleSignOut),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(MaterialLocalizations.of(context).saveButtonLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    if (token == null) return;
    if (token.isNotEmpty && await MusicListenTracker.validateListenBrainz(token) == null) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(RetroStrings.scrobbleInvalid)));
      }
      return;
    }
    await SettingsService.instance.write(AudioSettings.listenBrainzToken, token);
    unawaited(MusicListenTracker.instance.flush());
  }

  @override
  Widget build(BuildContext context) => SettingValueBuilder<String>(
    pref: AudioSettings.listenBrainzToken,
    builder: (context, token, _) => ListTile(
      leading: const AppIcon(Symbols.podcasts_rounded, fill: 1),
      title: Text(RetroStrings.listenBrainz),
      subtitle: Text(token.isEmpty ? RetroStrings.scrobbleNotSet : '••••${token.substring(token.length > 4 ? token.length - 4 : 0)}'),
      trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
      onTap: () => unawaited(_edit(context)),
    ),
  );
}

class _LastFmTile extends StatelessWidget {
  const _LastFmTile();

  Future<void> _edit(BuildContext context) async {
    final s = SettingsService.instance;
    if (s.read(AudioSettings.lastFmSession).isNotEmpty) {
      await MusicListenTracker.signOutLastFm();
      return;
    }
    final key = TextEditingController(text: s.read(AudioSettings.lastFmApiKey));
    final secret = TextEditingController(text: s.read(AudioSettings.lastFmSecret));
    final user = TextEditingController(text: s.read(AudioSettings.lastFmUser));
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(RetroStrings.lastFm),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(RetroStrings.lastFmHint),
              const SizedBox(height: 12),
              TextField(controller: key, decoration: InputDecoration(labelText: RetroStrings.scrobbleApiKey)),
              TextField(controller: secret, decoration: InputDecoration(labelText: RetroStrings.scrobbleSecret)),
              TextField(controller: user, decoration: InputDecoration(labelText: RetroStrings.scrobbleUser)),
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(labelText: RetroStrings.scrobblePassword),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(RetroStrings.scrobbleSignIn)),
        ],
      ),
    );
    final values = (key.text.trim(), secret.text.trim(), user.text.trim(), password.text);
    for (final c in [key, secret, user, password]) {
      c.dispose();
    }
    if (ok != true) return;
    final error = await MusicListenTracker.signInLastFm(
      apiKey: values.$1,
      secret: values.$2,
      user: values.$3,
      password: values.$4,
    );
    if (error != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(error)));
    } else {
      unawaited(MusicListenTracker.instance.flush());
    }
  }

  @override
  Widget build(BuildContext context) => SettingValueBuilder<String>(
    pref: AudioSettings.lastFmSession,
    builder: (context, session, _) {
      final user = SettingsService.instance.read(AudioSettings.lastFmUser);
      return ListTile(
        leading: const AppIcon(Symbols.radio_rounded, fill: 1),
        title: Text(RetroStrings.lastFm),
        subtitle: Text(session.isEmpty ? RetroStrings.scrobbleNotSet : RetroStrings.scrobbleSignedIn(user)),
        trailing: session.isEmpty
            ? const AppIcon(Symbols.chevron_right_rounded, fill: 1)
            : Text(RetroStrings.scrobbleSignOut),
        onTap: () => unawaited(_edit(context)),
      );
    },
  );
}
