import 'package:flutter/material.dart';
import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Segmented progress bar: completed and current steps fill with the accent colour.
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.current, required this.total});
  final int current, total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Step ${current + 1} of $total',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Step ${current + 1} of $total', style: AppTypography.caption.copyWith(color: c.textSecondary)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < total; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: AppAnimations.scaled(context, AppAnimations.normal),
                      curve: AppAnimations.standard,
                      margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
                      height: 5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        color: i <= current ? c.accent : c.divider,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
