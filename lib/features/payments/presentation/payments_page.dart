import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/fade_slide_in.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/pressable_scale.dart';
import 'payment_widgets.dart';

class PaymentsPage extends ConsumerWidget {
  const PaymentsPage({super.key});

  static const _services = [
    (Icons.swap_horiz_rounded, 'Transfer', '/transfer'),
    (Icons.receipt_long_rounded, 'Pay bills', '/bills'),
    (Icons.credit_card_rounded, 'Card management', '/cards/manage'),
    (Icons.qr_code_scanner_rounded, 'Scan to pay', '/qr'),
    (Icons.qr_code_2_rounded, 'My QR', '/qr?mine=1'),
    (Icons.group_rounded, 'Beneficiaries', '/beneficiaries'),
    (Icons.event_repeat_rounded, 'Scheduled', '/scheduled'),
    (Icons.history_rounded, 'Transactions', '/transactions'),
    (Icons.savings_rounded, 'Savings goals', '/savings'),
    (Icons.donut_small_rounded, 'Budgets', '/budgets'),
    (Icons.account_balance_rounded, 'Loans', '/loans'),
    (Icons.add_business_rounded, 'Open account', '/accounts/open'),
    (Icons.lock_clock_rounded, 'Fixed deposits', '/fixed-deposits'),
    (Icons.description_rounded, 'Statements', '/statements'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final people = ref.watch(beneficiariesProvider).value ?? const [];
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.navClearance),
        children: [
          const Text(AppStrings.navPayments, style: AppTypography.h1),
          const SizedBox(height: AppSpacing.md),
          FadeSlideIn(
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.95 / MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
              children: [
                for (final (icon, label, route) in _services)
                  GlassCard(
                    radius: 22,
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    onTap: () => context.push(route),
                    semanticLabel: label,
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: c.accent, size: 30),
                          const SizedBox(height: 8),
                          Text(label, style: AppTypography.caption.copyWith(color: c.textPrimary), textAlign: TextAlign.center, maxLines: 2),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (people.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Semantics(header: true, child: const Text('Send again', style: AppTypography.h3)),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: people.take(6).length,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
                itemBuilder: (_, i) {
                  final b = people[i];
                  return PressableScale(
                    semanticLabel: 'Send money to ${b.displayName}',
                    onTap: () => context.push('/transfer', extra: b),
                    child: SizedBox(
                      width: 72,
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: c.primary.withAlpha(70),
                            child: Text(initialsOf(b.name), style: AppTypography.title.copyWith(color: c.textPrimary)),
                          ),
                          const SizedBox(height: 6),
                          ExcludeSemantics(
                            child: Text(b.displayName, style: AppTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
