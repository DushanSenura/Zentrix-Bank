import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Shared backdrop behind every route, so page transitions feel continuous
/// and glass surfaces always have something to blur.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: c.backgroundGradient,
            ),
          ),
        ),
        Positioned(top: -120, right: -80, child: _Orb(300, c.accent.withAlpha(70))),
        Positioned(bottom: 40, left: -120, child: _Orb(320, c.primary.withAlpha(70))),
        child,
      ],
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb(this.size, this.color);
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withAlpha(0)]),
        ),
      ),
    ),
  );
}
