import 'package:flutter/material.dart';
import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/validators.dart';

/// Live checklist of [PasswordRule]s plus a strength bar, driven by [controller].
class PasswordRules extends StatelessWidget {
  const PasswordRules({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final duration = AppAnimations.scaled(context, AppAnimations.fast);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (_, value, _) {
        final passed = PasswordRule.all.where((r) => r.test(value.text)).length;
        final total = PasswordRule.all.length;
        final strength = passed / total;
        final color = passed <= 2 ? c.error : (passed < total ? c.warning : c.success);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: value.text.isEmpty ? 0 : strength),
                duration: duration,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 5,
                  backgroundColor: c.divider,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (final rule in PasswordRule.all)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Semantics(
                  label: '${rule.label}, ${rule.test(value.text) ? 'met' : 'not met'}',
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        AnimatedSwitcher(
                          duration: duration,
                          child: Icon(
                            rule.test(value.text) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            key: ValueKey(rule.test(value.text)),
                            size: 18,
                            color: rule.test(value.text) ? c.success : c.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(rule.label, style: AppTypography.bodySmall.copyWith(color: c.textSecondary)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
