import 'package:flutter/material.dart';
import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_typography.dart';
import 'pressable_scale.dart';

/// Main call-to-action. While [loading] it compresses into a round spinner.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  static const _height = 56.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final width = loading ? _height : box.maxWidth;
        return Center(
          child: PressableScale(
            semanticLabel: loading ? '$label, in progress' : label,
            onTap: loading ? null : onPressed,
            child: AnimatedContainer(
              duration: AppAnimations.scaled(context, AppAnimations.normal),
              curve: AppAnimations.standard,
              width: width,
              height: _height,
              decoration: BoxDecoration(
                borderRadius: AppRadius.pillAll,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.secondary, c.primary],
                ),
                boxShadow: onPressed == null && !loading ? null : AppShadows.glow(c.primary),
              ),
              child: ClipRRect(
                borderRadius: AppRadius.pillAll,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: AppAnimations.scaled(context, AppAnimations.fast),
                    child: loading
                        ? SizedBox(
                            key: const ValueKey('spin'),
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: c.onPrimary),
                          )
                        : FittedBox(
                            key: const ValueKey('label'),
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(label, style: AppTypography.button.copyWith(color: c.onPrimary)),
                                  if (icon != null) ...[
                                    const SizedBox(width: 8),
                                    Icon(icon, size: 20, color: c.onPrimary),
                                  ],
                                ],
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
