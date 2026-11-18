import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/page_backdrop.dart';
import '../../widgets/mini_player/video_mini_player.dart';
import '../../widgets/app_icon.dart';
import 'youtube_strings.dart';

/// Every page the YouTube tab pushes is named with this prefix, so
/// [YouTubeHomeButton] can pop back to the tab in one step.
const String _ytRoutePrefix = 'yt/';

/// The player route is [NoPageBackdropRoute]: its video is the native WebView
/// beneath the Flutter view, which a painted backdrop would cover.
MaterialPageRoute<T> ytRoute<T>(String name, WidgetBuilder builder) => name == 'player'
    ? YouTubePlayerRoute<T>(settings: RouteSettings(name: '$_ytRoutePrefix$name'), builder: builder)
    : MaterialPageRoute<T>(settings: RouteSettings(name: '$_ytRoutePrefix$name'), builder: builder);

/// The YouTube player's route: no page backdrop, and it can step aside for
/// the mini-player bar.
class YouTubePlayerRoute<T> extends NoPageBackdropRoute<T> with MinimizableRoute<T> {
  YouTubePlayerRoute({required super.builder, super.settings});
}

/// Back to the YouTube home (the subscriptions page) from any sub-page.
class YouTubeHomeButton extends StatelessWidget {
  const YouTubeHomeButton({super.key});

  static void goHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => !(route.settings.name?.startsWith(_ytRoutePrefix) ?? false));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: YtStrings.youtubeHome,
      onPressed: () => goHome(context),
      icon: const AppIcon(Symbols.home_rounded),
    );
  }
}
