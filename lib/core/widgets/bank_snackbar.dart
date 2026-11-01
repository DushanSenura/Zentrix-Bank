import 'package:flutter/material.dart';
import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'glass_card.dart';

enum SnackKind { success, error, warning, info }

/// Floating glass toast: `BankSnackbar.show(context, 'Saved', kind: SnackKind.success)`.
class BankSnackbar {
  const BankSnackbar._();

  static void show(BuildContext context, String message, {SnackKind kind = SnackKind.info}) {
    final c = context.colors;
    final (icon, color) = switch (kind) {
      SnackKind.success => (Icons.check_circle_rounded, c.success),
      SnackKind.error => (Icons.error_rounded, c.error),
      SnackKind.warning => (Icons.warning_amber_rounded, c.warning),
      SnackKind.info => (Icons.info_rounded, c.accent),
    };
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 112),
          content: _Toast(icon: icon, color: color, message: message),
        ),
      );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.icon, required this.color, required this.message});
  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: AppAnimations.scaled(context, AppAnimations.normal),
    curve: AppAnimations.standard,
    builder: (_, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
    ),
    child: Semantics(
      liveRegion: true,
      child: GlassCard(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: AppTypography.body.copyWith(color: context.colors.textPrimary)),
            ),
          ],
        ),
      ),
    ),
  );
}
