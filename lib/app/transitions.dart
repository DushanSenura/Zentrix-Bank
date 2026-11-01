import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_animations.dart';

/// Named motion styles so every route transition comes from one place.
enum PageMotion {
  /// Fade + slight horizontal slide + tiny scale.
  forward,

  /// Fade + gentle scale; used between top-level flows (splash → login).
  fadeScale,

  /// Longer fade + scale-up; login → dashboard over the shared background.
  reveal,
}

CustomTransitionPage<void> appPage(GoRouterState state, Widget child, {PageMotion motion = PageMotion.forward}) {
  final duration = switch (motion) {
    PageMotion.forward => const Duration(milliseconds: 300),
    PageMotion.fadeScale => const Duration(milliseconds: 350),
    PageMotion.reveal => const Duration(milliseconds: 500),
  };
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppAnimations.standard);
      if (AppAnimations.reduced(context)) return FadeTransition(opacity: curved, child: child);
      return switch (motion) {
        PageMotion.forward => FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(curved),
            child: ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(curved), child: child),
          ),
        ),
        PageMotion.fadeScale => FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
        ),
        PageMotion.reveal => FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curved), child: child),
        ),
      };
    },
  );
}
