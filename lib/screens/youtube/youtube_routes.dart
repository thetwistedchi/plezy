import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../widgets/app_icon.dart';
import 'youtube_strings.dart';

/// Every page the YouTube tab pushes is named with this prefix, so
/// [YouTubeHomeButton] can pop back to the tab in one step.
const String _ytRoutePrefix = 'yt/';

MaterialPageRoute<T> ytRoute<T>(String name, WidgetBuilder builder) =>
    MaterialPageRoute<T>(settings: RouteSettings(name: '$_ytRoutePrefix$name'), builder: builder);

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
