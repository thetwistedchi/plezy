import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/youtube/youtube_auth.dart';
import '../../services/youtube/youtube_service.dart';
import '../../services/youtube/youtube_settings.dart';
import '../../services/youtube/youtube_webview.dart';
import '../../services/youtube/youtube_watchlist.dart';
import '../../theme/mono_tokens.dart';
import '../../theme/player_style.dart';
import '../../utils/app_logger.dart';
import '../../widgets/app_icon.dart';
import 'youtube_channels_screen.dart';
import 'youtube_guide_screen.dart';
import 'youtube_strings.dart';
import 'youtube_web_sign_in_screen.dart';
import 'youtube_routes.dart';

/// Sign-in and library options for the YouTube tab.
class YouTubeSettingsScreen extends StatefulWidget {
  const YouTubeSettingsScreen({super.key});

  @override
  State<YouTubeSettingsScreen> createState() => _YouTubeSettingsScreenState();
}

class _YouTubeSettingsScreenState extends State<YouTubeSettingsScreen> {
  final _settings = YouTubeSettings.instance;
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  final _cacheLimit = TextEditingController();
  bool _busy = false;
  String? _message;
  int? _cacheBytes;
  bool _clearingCache = false;

  Future<void> _refreshCacheSize() async {
    if (!YouTubeWebView.isSupported) return;
    final size = await YouTubeWebView.cacheSize();
    if (mounted) setState(() => _cacheBytes = size);
  }

  Future<void> _saveCacheLimit() async {
    final value = int.tryParse(_cacheLimit.text.trim());
    if (value == null) {
      _cacheLimit.text = '${_settings.playerCacheLimitMb}';
      return;
    }
    await _settings.setPlayerCacheLimitMb(value);
    _cacheLimit.text = '${_settings.playerCacheLimitMb}';
  }

  Future<void> _clearCache() async {
    setState(() => _clearingCache = true);
    try {
      await YouTubeWebView.clearCache();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(YtStrings.cacheCleared)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _clearingCache = false);
      await _refreshCacheSize();
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refreshCacheSize());
    if (YouTubeWebView.isSupported && YouTubeWebView.playerSignedIn.value == null) {
      unawaited(YouTubeWebView.checkPlayerSignIn());
    }
    unawaited(
      _settings.load().then((_) {
        if (!mounted) return;
        _clientId.text = _settings.clientId;
        _clientSecret.text = _settings.clientSecret;
        _cacheLimit.text = '${_settings.playerCacheLimitMb}';
        setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    _clientId.dispose();
    _clientSecret.dispose();
    _cacheLimit.dispose();
    super.dispose();
  }

  Future<void> _saveCredentials() async {
    await _settings.setClientId(_clientId.text);
    await _settings.setClientSecret(_clientSecret.text);
  }

  Future<void> _signIn() async {
    await _saveCredentials();
    if (!mounted) return;
    if (!_settings.hasCredentials) {
      setState(() => _message = YtStrings.needClientId);
      return;
    }
    setState(() {
      _busy = true;
      _message = YtStrings.signingIn;
    });
    try {
      await YouTubeAuth.instance.signIn();
      try {
        final account = await YouTubeService.instance.fetchAccount();
        if (account.name != null) await _settings.setAccountName(account.name!);
        if (account.channelId != null) await _settings.setAccountChannelId(account.channelId!);
      } catch (e) {
        appLogger.w('YouTube: could not read the channel name', error: e);
      }
      YouTubeService.instance.ensureStarted();
      if (mounted) setState(() => _message = null);
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await YouTubeAuth.instance.signOut();
    YouTubeService.instance.clear();
    if (mounted) setState(() => _busy = false);
  }

  bool _importing = false;

  void _say(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  /// Fork: Watch later on youtube.com into the app's Watch later list.
  Future<void> _importWatchLater() async {
    if (_importing) return;
    _importing = true;
    _say(YtStrings.importRunning);
    try {
      final items = await YouTubeWebView.watchLater();
      if (!mounted) return;
      if (items == null) {
        _say(YtStrings.importFailed);
        return;
      }
      final watchlist = YouTubeWatchlist.instance;
      await watchlist.load();
      var added = 0;
      for (final i in items) {
        final id = i['id'] as String? ?? '';
        if (id.isEmpty || watchlist.contains(id)) continue;
        await watchlist.add(
          YouTubeVideo(
            id: id,
            title: i['t'] as String? ?? '',
            channelId: i['ci'] as String? ?? '',
            channelTitle: i['c'] as String? ?? '',
            thumbnailUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
            publishedAt: DateTime.now(),
            viewCount: 0,
            isShort: false,
            duration: Duration(seconds: (i['s'] as num?)?.toInt() ?? 0),
          ),
        );
        added++;
      }
      if (mounted) _say(YtStrings.importWatchLaterDone(added, items.length));
    } finally {
      _importing = false;
    }
  }

  /// Fork: channels with the bell on "All" become favourites.
  Future<void> _importBells() async {
    if (_importing) return;
    _importing = true;
    _say(YtStrings.importRunning);
    try {
      final channels = await YouTubeWebView.bellChannels();
      if (!mounted) return;
      if (channels == null) {
        _say(YtStrings.importFailed);
        return;
      }
      var added = 0;
      for (final c in channels) {
        if (_settings.isFavorite(c.id)) continue;
        await _settings.setFavorite(c.id, c.title, true);
        added++;
      }
      if (mounted) _say(YtStrings.importBellsDone(added, channels.length));
    } finally {
      _importing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final accent = playerActiveColor(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(YtStrings.tab),
        actions: [
          const YouTubeHomeButton(),
          IconButton(
            tooltip: YtStrings.channels,
            onPressed: () =>
                Navigator.of(context).push(ytRoute<void>('channels', (_) => const YouTubeChannelsScreen())),
            icon: const AppIcon(Symbols.subscriptions_rounded),
          ),
          IconButton(
            tooltip: YtStrings.guide,
            onPressed: () =>
                Navigator.of(context).push(ytRoute<void>('guide', (_) => const YouTubeGuideScreen())),
            icon: const AppIcon(Symbols.help_rounded),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) {
          if (!_settings.isLoaded) return const Center(child: CircularProgressIndicator());
          final signedIn = _settings.isSignedIn;
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionTitle(YtStrings.account),
                      _Card(
                        children: [
                          ListTile(
                            leading: AppIcon(Symbols.account_circle_rounded, color: signedIn ? accent : mono.textMuted),
                            title: Text(
                              signedIn
                                  ? (_settings.accountName.isEmpty
                                        ? YtStrings.signedIn
                                        : YtStrings.signedInAs(_settings.accountName))
                                  : YtStrings.notSignedIn,
                            ),
                            subtitle: Text(YtStrings.readOnly),
                            trailing: signedIn
                                ? OutlinedButton(onPressed: _busy ? null : _signOut, child: Text(YtStrings.signOut))
                                : FilledButton(onPressed: _busy ? null : _signIn, child: Text(YtStrings.signIn)),
                          ),
                          if (signedIn && !_settings.canWrite)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Text(
                                YtStrings.writeAccessMissing,
                                style: theme.textTheme.bodySmall?.copyWith(color: accent),
                              ),
                            ),
                          if (_message != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Text(_message!, style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(YtStrings.oauthClient),
                      _Card(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  YtStrings.oauthHelp,
                                  style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted, height: 1.45),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () => unawaited(
                                    launchUrl(
                                      Uri.parse('https://console.cloud.google.com/apis/credentials'),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                  ),
                                  icon: const AppIcon(Symbols.open_in_new_rounded, size: 18),
                                  label: Text(YtStrings.openConsole),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _clientId,
                                  enabled: !signedIn,
                                  decoration: InputDecoration(labelText: YtStrings.clientId),
                                  onSubmitted: (_) => unawaited(_saveCredentials()),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _clientSecret,
                                  enabled: !signedIn,
                                  obscureText: true,
                                  decoration: InputDecoration(labelText: YtStrings.clientSecret),
                                  onSubmitted: (_) => unawaited(_saveCredentials()),
                                ),
                                if (!signedIn) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton(
                                      onPressed: () => unawaited(_saveCredentials()),
                                      child: Text(YtStrings.save),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(YtStrings.library),
                      _Card(
                        children: [
                          SwitchListTile(
                            title: Text(YtStrings.showShorts),
                            subtitle: Text(YtStrings.hiddenByDefault),
                            value: _settings.showShorts,
                            onChanged: (v) => unawaited(_settings.setShowShorts(v)),
                          ),
                          SwitchListTile(
                            title: Text(YtStrings.showPremieres),
                            subtitle: Text(YtStrings.hiddenByDefault),
                            value: _settings.showPremieres,
                            onChanged: (v) => unawaited(_settings.setShowPremieres(v)),
                          ),
                          ListTile(
                            title: Text(YtStrings.minLength),
                            subtitle: Text(YtStrings.minLengthSub),
                            trailing: DropdownButton<int>(
                              value: YouTubeSettings.minMinutesChoices.contains(_settings.minMinutes)
                                  ? _settings.minMinutes
                                  : 0,
                              items: [
                                for (final m in YouTubeSettings.minMinutesChoices)
                                  DropdownMenuItem(value: m, child: Text(YtStrings.minLengthLabel(m))),
                              ],
                              onChanged: (v) {
                                if (v != null) unawaited(_settings.setMinMinutes(v));
                              },
                            ),
                          ),
                          ListTile(
                            title: Text(YtStrings.defaultSpeed),
                            subtitle: Text(YtStrings.defaultSpeedSub),
                            trailing: DropdownButton<double>(
                              value: YouTubeSettings.speedChoices.contains(_settings.playbackSpeed)
                                  ? _settings.playbackSpeed
                                  : 1.0,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final s in YouTubeSettings.speedChoices)
                                  DropdownMenuItem(value: s, child: Text(YtStrings.speedLabel(s))),
                              ],
                              onChanged: (v) {
                                if (v != null) unawaited(_settings.setPlaybackSpeed(v));
                              },
                            ),
                          ),
                          ListTile(
                            title: Text(YtStrings.refreshEvery),
                            trailing: DropdownButton<int>(
                              value: _settings.refreshMinutes,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final m in YouTubeSettings.refreshChoices)
                                  DropdownMenuItem(value: m, child: Text(YtStrings.minutes(m))),
                              ],
                              onChanged: (v) async {
                                if (v == null) return;
                                await _settings.setRefreshMinutes(v);
                                YouTubeService.instance.ensureStarted();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(YtStrings.playerButtons),
                      _Card(
                        children: [
                          SwitchListTile(
                            title: Text(YtStrings.showChannelStrip),
                            value: _settings.showChannelStrip,
                            onChanged: (v) => unawaited(_settings.setShowChannelStrip(v)),
                          ),
                          for (final id in YouTubeSettings.playerButtons)
                            SwitchListTile(
                              dense: true,
                              title: Text(YtStrings.buttonLabel(id)),
                              value: _settings.showButton(id),
                              onChanged: (v) => unawaited(_settings.setShowButton(id, v)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(YtStrings.communityFeatures),
                      _Card(
                        children: [
                          SwitchListTile(
                            title: Text(YtStrings.deArrowTitles),
                            subtitle: Text(YtStrings.deArrowSub),
                            value: _settings.deArrowTitles,
                            onChanged: (v) => unawaited(_settings.setDeArrowTitles(v)),
                          ),
                          SwitchListTile(
                            title: Text(YtStrings.deArrowThumbs),
                            subtitle: Text(YtStrings.deArrowSub),
                            value: _settings.deArrowThumbnails,
                            onChanged: (v) => unawaited(_settings.setDeArrowThumbnails(v)),
                          ),
                          SwitchListTile(
                            title: Text(YtStrings.returnDislikes),
                            subtitle: Text(YtStrings.returnDislikesSub),
                            value: _settings.returnDislikes,
                            onChanged: (v) => unawaited(_settings.setReturnDislikes(v)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(YtStrings.hiddenAndMuted),
                      _Card(
                        children: [
                          SwitchListTile(
                            title: Text(YtStrings.notifyFavorites),
                            subtitle: Text(YtStrings.notifyFavoritesSub),
                            value: _settings.notifyFavorites,
                            onChanged: (v) => unawaited(_settings.setNotifyFavorites(v)),
                          ),
                          ListTile(
                            title: Text(YtStrings.favoriteChannels),
                            subtitle: _settings.favoriteChannels.isEmpty ? Text(YtStrings.noneYet) : null,
                          ),
                          for (final e in _settings.favoriteChannels.entries)
                            ListTile(
                              dense: true,
                              leading: AppIcon(Symbols.star_rounded, fill: 1, color: accent),
                              title: Text(e.value),
                              trailing: IconButton(
                                tooltip: YtStrings.unfavoriteChannel,
                                onPressed: () => unawaited(_settings.setFavorite(e.key, e.value, false)),
                                icon: const AppIcon(Symbols.close_rounded),
                              ),
                            ),
                          ListTile(
                            title: Text(YtStrings.mutedChannels),
                            subtitle: _settings.mutedChannels.isEmpty ? Text(YtStrings.noneYet) : null,
                          ),
                          for (final e in _settings.mutedChannels.entries)
                            ListTile(
                              dense: true,
                              leading: AppIcon(Symbols.visibility_off_rounded, color: mono.textMuted),
                              title: Text(e.value),
                              trailing: TextButton(
                                onPressed: () => unawaited(_settings.setMuted(e.key, e.value, false)),
                                child: Text(YtStrings.showHiddenAgain),
                              ),
                            ),
                          ListTile(
                            title: Text(YtStrings.hiddenVideos(_settings.hiddenVideoCount)),
                            trailing: _settings.hiddenVideoCount == 0
                                ? null
                                : TextButton(
                                    onPressed: () => unawaited(_settings.unhideAllVideos()),
                                    child: Text(YtStrings.showHiddenAgain),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(YtStrings.captionsAndAudio),
                      _Card(
                        children: [
                          SwitchListTile(
                            title: Text(YtStrings.showCaptions),
                            subtitle: Text(YtStrings.showCaptionsSub),
                            value: _settings.captionsEnabled,
                            onChanged: (v) => unawaited(_settings.setCaptions(enabled: v)),
                          ),
                          ListTile(
                            title: Text(YtStrings.captionsLanguage),
                            trailing: DropdownButton<String>(
                              value: _languageChoices.containsKey(_settings.captionsLanguage)
                                  ? _settings.captionsLanguage
                                  : 'en',
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final e in _languageChoices.entries)
                                  DropdownMenuItem(value: e.key, child: Text(e.value)),
                              ],
                              onChanged: (v) {
                                if (v != null) unawaited(_settings.setCaptions(language: v));
                              },
                            ),
                          ),
                          SwitchListTile(
                            title: Text(YtStrings.allowAutoCaptions),
                            subtitle: Text(YtStrings.allowAutoCaptionsSub),
                            value: _settings.captionsAllowAuto,
                            onChanged: (v) => unawaited(_settings.setCaptions(allowAuto: v)),
                          ),
                          SwitchListTile(
                            title: Text(YtStrings.translateCaptions),
                            subtitle: Text(YtStrings.translateCaptionsSub),
                            value: _settings.captionsTranslate,
                            onChanged: (v) => unawaited(_settings.setCaptions(translate: v)),
                          ),
                          ListTile(
                            title: Text(YtStrings.audioPreference),
                            subtitle: Text(YtStrings.audioPreferenceSub),
                            trailing: DropdownButton<String>(
                              value: _settings.audioLanguage == 'original' ||
                                      _languageChoices.containsKey(_settings.audioLanguage)
                                  ? _settings.audioLanguage
                                  : 'original',
                              underline: const SizedBox.shrink(),
                              items: [
                                DropdownMenuItem(value: 'original', child: Text(YtStrings.audioOriginal)),
                                for (final e in _languageChoices.entries)
                                  DropdownMenuItem(value: e.key, child: Text(e.value)),
                              ],
                              onChanged: (v) {
                                if (v != null) unawaited(_settings.setAudioLanguage(v));
                              },
                            ),
                          ),
                        ],
                      ),
                      if (YouTubeWebView.isSupported) ...[
                        const SizedBox(height: 24),
                        _SectionTitle(YtStrings.playerAccount),
                        _Card(
                          children: [
                            ListTile(
                              leading: AppIcon(Symbols.workspace_premium_rounded, color: accent),
                              title: Text(YtStrings.playerAccount),
                              subtitle: Text(YtStrings.playerAccountSub),
                              // Fork: whether the player is signed in.
                              trailing: ValueListenableBuilder<bool?>(
                                valueListenable: YouTubeWebView.playerSignedIn,
                                builder: (context, signedIn, _) => Chip(
                                  avatar: AppIcon(
                                    signedIn == true
                                        ? Symbols.check_circle_rounded
                                        : signedIn == false
                                        ? Symbols.cancel_rounded
                                        : Symbols.hourglass_empty_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    signedIn == true
                                        ? YtStrings.playerSignedIn
                                        : signedIn == false
                                        ? YtStrings.playerSignedOut
                                        : YtStrings.playerChecking,
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  FilledButton(
                                    onPressed: () async {
                                      await Navigator.of(context).push(
                                        ytRoute<void>('signin', (_) => const YouTubeWebSignInScreen()),
                                      );
                                      unawaited(YouTubeWebView.checkPlayerSignIn());
                                    },
                                    child: Text(YtStrings.signInPlayer),
                                  ),
                                  OutlinedButton(
                                    onPressed: () async {
                                      await YouTubeWebSignInScreen.signOut();
                                      YouTubeWebView.playerSignedIn.value = false;
                                    },
                                    child: Text(YtStrings.signOutPlayer),
                                  ),
                                ],
                              ),
                            ),
                            SwitchListTile(
                              title: Text(YtStrings.historySync),
                              subtitle: Text(YtStrings.historySyncSub),
                              isThreeLine: true,
                              value: _settings.syncHistory,
                              onChanged: (v) async {
                                await _settings.setSyncHistory(v);
                                if (v) unawaited(YouTubeWebView.backfillHistory());
                              },
                            ),
                            if (_settings.syncHistory)
                              FutureBuilder<List<(String, double)>>(
                                future: _settings.historyBacklog(),
                                builder: (context, snapshot) {
                                  final count = snapshot.data?.length ?? 0;
                                  return ListTile(
                                    leading: AppIcon(Symbols.sync_rounded, color: mono.textMuted),
                                    title: Text(YtStrings.historySyncNow),
                                    subtitle: Text(YtStrings.historySyncNowSub(count)),
                                    enabled: count > 0,
                                    onTap: () async {
                                      final started = await YouTubeWebView.backfillHistory(now: true);
                                      if (!context.mounted || started == 0) return;
                                      ScaffoldMessenger.maybeOf(context)
                                          ?.showSnackBar(SnackBar(content: Text(YtStrings.historySyncStarted(started))));
                                    },
                                  );
                                },
                              ),
                            // Fork: imports from the signed-in YouTube account.
                            ListTile(
                              leading: AppIcon(Symbols.watch_later_rounded, color: mono.textMuted),
                              title: Text(YtStrings.importWatchLater),
                              subtitle: Text(YtStrings.importWatchLaterSub),
                              onTap: () => unawaited(_importWatchLater()),
                            ),
                            ListTile(
                              leading: AppIcon(Symbols.notifications_active_rounded, color: mono.textMuted),
                              title: Text(YtStrings.importBells),
                              subtitle: Text(YtStrings.importBellsSub),
                              onTap: () => unawaited(_importBells()),
                            ),
                            ListTile(
                              leading: AppIcon(Symbols.storage_rounded, color: mono.textMuted),
                              title: Text(YtStrings.cacheLimit),
                              subtitle: Text(YtStrings.cacheLimitSub),
                              trailing: SizedBox(
                                width: 140,
                                child: Focus(
                                  onFocusChange: (focused) {
                                    if (!focused) unawaited(_saveCacheLimit());
                                  },
                                  child: TextField(
                                    controller: _cacheLimit,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    textAlign: TextAlign.end,
                                    decoration: const InputDecoration(isDense: true, suffixText: 'MB'),
                                    onSubmitted: (_) => unawaited(_saveCacheLimit()),
                                  ),
                                ),
                              ),
                            ),
                            ListTile(
                              leading: AppIcon(Symbols.cleaning_services_rounded, color: mono.textMuted),
                              title: Text(YtStrings.playerCache),
                              subtitle: Text(YtStrings.playerCacheSub(YtStrings.fileSize(_cacheBytes ?? 0))),
                              trailing: OutlinedButton(
                                onPressed: _clearingCache ? null : () => unawaited(_clearCache()),
                                child: _clearingCache
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Text(YtStrings.clearPlayerCache),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      _SectionTitle(YtStrings.sponsorBlock),
                      _Card(
                        children: [
                          SwitchListTile(
                            title: Text(YtStrings.useSponsorBlock),
                            subtitle: Text(YtStrings.useSponsorBlockSub),
                            value: _settings.sponsorBlockEnabled,
                            onChanged: (v) => unawaited(_settings.setSponsorBlockEnabled(v)),
                          ),
                          for (final category in sponsorBlockDefaults.keys)
                            ListTile(
                              enabled: _settings.sponsorBlockEnabled,
                              title: Text(YtStrings.sbLabel(category)),
                              subtitle: Text(YtStrings.sbDescription(category)),
                              trailing: SegmentedButton<SegmentMode>(
                                showSelectedIcon: false,
                                style: _segmentStyle(context),
                                segments: [
                                  ButtonSegment(value: SegmentMode.auto, label: Text(YtStrings.modeAuto)),
                                  ButtonSegment(value: SegmentMode.button, label: Text(YtStrings.modeButton)),
                                  ButtonSegment(value: SegmentMode.off, label: Text(YtStrings.modeOff)),
                                ],
                                selected: {_settings.segmentMode(category)},
                                onSelectionChanged: _settings.sponsorBlockEnabled
                                    ? (s) => unawaited(_settings.setSegmentMode(category, s.first))
                                    : null,
                              ),
                            ),
                          SwitchListTile(
                            title: Text(YtStrings.showSegments),
                            subtitle: Text(YtStrings.showSegmentsSub),
                            value: _settings.showSegmentsOnTimeline,
                            onChanged: _settings.sponsorBlockEnabled
                                ? (v) => unawaited(_settings.setShowSegmentsOnTimeline(v))
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                            child: Text(
                              YtStrings.sbCredit,
                              style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted),
                            ),
                          ),
                        ],
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: playerActiveColor(context),
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return Container(
      decoration: BoxDecoration(
        color: mono.surface,
        borderRadius: BorderRadius.circular(mono.radiusLg),
        border: Border.all(color: mono.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

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
    visualDensity: VisualDensity.compact,
  );
}

const Map<String, String> _languageChoices = {
  'en': 'English',
  'de': 'Deutsch',
  'fr': 'Français',
  'es': 'Español',
  'it': 'Italiano',
  'nl': 'Nederlands',
  'pt': 'Português',
  'pl': 'Polski',
  'sv': 'Svenska',
  'da': 'Dansk',
  'nb': 'Norsk',
  'fi': 'Suomi',
  'tr': 'Türkçe',
  'ru': 'Русский',
  'uk': 'Українська',
  'ja': '日本語',
  'ko': '한국어',
  'zh': '中文',
  'hi': 'हिन्दी',
  'ar': 'العربية',
};
