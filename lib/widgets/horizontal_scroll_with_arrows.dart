import 'package:flutter/material.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../theme/mono_tokens.dart';
import '../utils/platform_detector.dart';

/// A wrapper widget that adds hover-activated navigation arrows to horizontal scrolling content.
/// The arrows only appear on desktop/web platforms and hide at scroll boundaries.
///
/// This widget creates and manages its own ScrollController internally. Use the [builder]
/// constructor to access the ScrollController for the scrollable child widget.
class HorizontalScrollWithArrows extends StatefulWidget {
  final Widget Function(ScrollController) builder;
  final double scrollAmount;
  final ScrollController? controller;

  /// Fork: where the posters sit in the row (from its top) and their size;
  /// the scroll bars then cover the first and last poster's height and at
  /// most a quarter of a poster's width. Without these, round arrows show.
  final double? posterTop;
  final double? posterHeight;
  final double? posterWidth;

  const HorizontalScrollWithArrows({
    super.key,
    required this.builder,
    this.scrollAmount = 0.8, // Scroll by 80% of viewport width by default
    this.controller,
    this.posterTop,
    this.posterHeight,
    this.posterWidth,
  });

  @override
  State<HorizontalScrollWithArrows> createState() => _HorizontalScrollWithArrowsState();
}

class _HorizontalScrollWithArrowsState extends State<HorizontalScrollWithArrows> {
  late ScrollController _scrollController;
  late bool _ownsController;
  late final bool _listensForScrollState;
  bool _isHovering = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _scrollController = widget.controller ?? ScrollController();
    _listensForScrollState = PlatformDetector.isDesktopOS();
    if (_listensForScrollState) {
      _scrollController.addListener(_updateScrollState);
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
    }
  }

  @override
  void didUpdateWidget(covariant HorizontalScrollWithArrows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;

    if (_listensForScrollState) {
      _scrollController.removeListener(_updateScrollState);
    }
    if (_ownsController) {
      _scrollController.dispose();
    }
    _ownsController = widget.controller == null;
    _scrollController = widget.controller ?? ScrollController();
    if (_listensForScrollState) {
      _scrollController.addListener(_updateScrollState);
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
    }
  }

  @override
  void dispose() {
    if (_listensForScrollState) {
      _scrollController.removeListener(_updateScrollState);
    }
    if (_ownsController) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void _updateScrollState() {
    if (!mounted || _scrollController.positions.length != 1) {
      if (mounted && (_canScrollLeft || _canScrollRight)) {
        setState(() {
          _canScrollLeft = false;
          _canScrollRight = false;
        });
      }
      return;
    }

    final position = _scrollController.position;
    final isScrollable = position.maxScrollExtent > 0;
    final newLeft = isScrollable && position.pixels > 0;
    final newRight = isScrollable && position.pixels < position.maxScrollExtent;
    if (newLeft != _canScrollLeft || newRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = newLeft;
        _canScrollRight = newRight;
      });
    }
  }

  void _animateScroll(double direction) {
    if (_scrollController.positions.length != 1) return;
    final position = _scrollController.position;
    final delta = direction * position.viewportDimension * widget.scrollAmount;
    final targetScroll = (position.pixels + delta).clamp(0.0, position.maxScrollExtent);
    _scrollController.animateTo(targetScroll, duration: tokens(context).slow, curve: Curves.easeInOut);
  }

  void _scrollLeft() => _animateScroll(-1);

  void _scrollRight() => _animateScroll(1);

  Widget _buildArrowButton({
    required double position,
    required IconData icon,
    required VoidCallback onPressed,
    required bool canScroll,
  }) {
    final height = widget.posterHeight;
    if (height != null) {
      // A translucent bar along the row's edge, as tall as the posters.
      final width = ((widget.posterWidth ?? 160) / 4).clamp(24.0, 44.0);
      final left = position >= 0;
      return Positioned(
        left: left ? 0 : null,
        right: left ? null : 0,
        top: widget.posterTop ?? 0,
        height: height,
        width: width,
        child: AnimatedOpacity(
          opacity: (_isHovering && canScroll) ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: IgnorePointer(
            ignoring: !(_isHovering && canScroll),
            child: _ScrollBar(icon: icon, onPressed: onPressed, leftEdge: left),
          ),
        ),
      );
    }
    return Positioned(
      left: position < 0 ? null : position,
      right: position < 0 ? -position : null,
      top: 0,
      bottom: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: (_isHovering && canScroll) ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: IgnorePointer(
            ignoring: !(_isHovering && canScroll),
            child: _NavigationArrow(icon: icon, onPressed: onPressed),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(_scrollController);

    // Hover arrows need a mouse; isDesktop(context) is also true on TV where
    // the MouseRegion + scroll-notification machinery is dead weight per row.
    if (!PlatformDetector.isDesktopOS()) {
      return child;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _updateScrollState();
          return false;
        },
        child: Stack(
          children: [
            child,
            _buildArrowButton(
              position: 8,
              icon: Symbols.chevron_left_rounded,
              onPressed: _scrollLeft,
              canScroll: _canScrollLeft,
            ),
            _buildArrowButton(
              position: -8,
              icon: Symbols.chevron_right_rounded,
              onPressed: _scrollRight,
              canScroll: _canScrollRight,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationArrow extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _NavigationArrow({required this.icon, required this.onPressed});

  @override
  State<_NavigationArrow> createState() => _NavigationArrowState();
}

class _NavigationArrowState extends State<_NavigationArrow> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: _isPressed ? 0.9 : 0.7),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, spreadRadius: 0)],
          ),
          child: AppIcon(widget.icon, fill: 1, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}


/// Fork: the row's scroll control as a translucent bar along its edge.
class _ScrollBar extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool leftEdge;

  const _ScrollBar({required this.icon, required this.onPressed, required this.leftEdge});

  @override
  State<_ScrollBar> createState() => _ScrollBarState();
}

class _ScrollBarState extends State<_ScrollBar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final radius = Radius.circular(tokens(context).radiusSm);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: _hover ? 0.62 : 0.42),
            borderRadius: widget.leftEdge
                ? BorderRadius.horizontal(right: radius)
                : BorderRadius.horizontal(left: radius),
          ),
          alignment: Alignment.center,
          child: AppIcon(widget.icon, fill: 1, color: Colors.white.withValues(alpha: _hover ? 1 : 0.85), size: 28),
        ),
      ),
    );
  }
}
