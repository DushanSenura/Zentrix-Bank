import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import 'pressable_scale.dart';

/// Liquid-glass surface: blur, translucent fill, soft rim and a top-left highlight.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = AppRadius.xl,
    this.blur = 18,
    this.onTap,
    this.semanticLabel,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius, blur;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shape = BorderRadius.circular(radius);
    final card = DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: AppShadows.soft),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: shape,
              border: Border.all(color: c.glassBorder),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.alphaBlend(c.glassHighlight.withAlpha(36), c.glassFill), c.glassFill],
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
    if (onTap == null) return card;
    return PressableScale(pressedScale: 0.985, onTap: onTap, semanticLabel: semanticLabel, child: card);
  }
}
