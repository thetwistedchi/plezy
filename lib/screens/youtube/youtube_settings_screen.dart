import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/youtube/youtube_auth.dart';
import '../../services/youtube/youtube_service.dart';
import '../../services/youtube/youtube_settings.dart';
import '../../theme/mono_tokens.dart';
import '../../theme/player_style.dart';
import '../../utils/app_logger.dart';
import '../../widgets/app_icon.dart';
import 'youtube_strings.dart';

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
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(
      _settings.load().then((_) {
        if (!mounted) return;
        _clientId.text = _settings.clientId;
        _clientSecret.text = _settings.clientSecret;
        setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    _clientId.dispose();
    _clientSecret.dispose();
    super.dispose();
  }

  Future<void> _saveCredentials() async {
    await _settings.setClientId(_clientId.text);
    await _settings.setClientSecret(_clientSecret.text);
  }

  Future<void> _signIn() async {
    await _saveCredentials();
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
        final name = await YouTubeService.instance.fetchAccountName();
        if (name != null) await _settings.setAccountName(name);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final accent = playerActiveColor(context);

    return Scaffold(
      appBar: AppBar(title: Text(YtStrings.tab)),
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
