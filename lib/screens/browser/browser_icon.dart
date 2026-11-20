import 'package:flutter/widgets.dart';

import '../../theme/retrowave_colors.dart';
import '../../widgets/app_icon.dart';

/// An icon of the browser: the AI-generated retrowave glyph on the retrowave
/// theme, the app's normal icon on every other theme. [opacity] dims it on
/// both (the plain icons ignore AppIcon's retro-only opacity), [fill] fills
/// the plain icon (e.g. a set bookmark).
class BrowserIcon extends StatelessWidget {
  const BrowserIcon(this.icon, {super.key, this.size, this.opacity = 1, this.fill});

  final IconData icon;
  final double? size;
  final double opacity;
  final double? fill;

  @override
  Widget build(BuildContext context) {
    final retro = RetroColors.isActive(context);
    Widget child = AppIcon.retro(icon, size: size, fill: fill, retroOpacity: opacity < 1 ? opacity : null);
    if (!retro && opacity < 1) child = Opacity(opacity: opacity, child: child);
    return child;
  }
}
