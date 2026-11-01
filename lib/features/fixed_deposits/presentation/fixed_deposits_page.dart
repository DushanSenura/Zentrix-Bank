import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/models.dart';
import '../../payments/presentation/payment_widgets.dart';
import '../domain/fixed_deposit.dart';

/// Every fixed deposit you have opened: what's locked away, what it will earn, when it matures and what happens then.
class FixedDepositsPage extends ConsumerWidget {
  const FixedDepositsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final list = ref.watch(fixedDepositsProvider);
    final accounts = ref.watch(accountsProvider).value ?? const <BankAccount>[];
    return FlowPage(
      title: 'Fixed deposits',
      child: RefreshIndicator(
        onRefresh: () async => ref.refresh(fixedDepositsProvider.future),
        child: list.when(
          loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 240, radius: 24)),
          error: (e, _) => ErrorView(error: e, what: 'your fixed deposits', onRetry: () => ref.invalidate(fixedDepositsProvider)),
          data: (all) {
            final active = all.where((d) => d.active).toList();
            final matured = all.where((d) => !d.active).toList();
            final invested = active.fold(0.0, (s, d) => s + d.principal);
            final interest = active.fold(0.0, (s, d) => s + d.interestAtMaturity);
            return ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
              children: [
                if (all.isEmpty)
                  const EmptyState(
                    icon: Icons.lock_clock_rounded,
                    title: 'No fixed deposits yet',
                    message: 'Lock money away for 3 months or longer and earn a set rate. It will show up here.',
                  )
                else ...[
                  if (active.isNotEmpty)
                    GlassCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Locked away', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                          Semantics(
                            label: '${formatMoney(invested)} in ${active.length} ${active.length == 1 ? 'deposit' : 'deposits'}, earning ${formatMoney(interest)}',
                            child: ExcludeSemantics(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(formatMoney(invested), style: AppTypography.amount))),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${active.length} ${active.length == 1 ? 'deposit' : 'deposits'} · ${formatMoney(interest)} interest still to come',
                            style: AppTypography.bodySmall.copyWith(color: c.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  if (active.isNotEmpty) ...[
                    Semantics(header: true, child: const Text('Active', style: AppTypography.h3)),
                    const SizedBox(height: AppSpacing.xs),
                    for (final d in active) _DepositCard(deposit: d, accounts: accounts),
                  ],
                  if (matured.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Semantics(header: true, child: const Text('Matured', style: AppTypography.h3)),
                    const SizedBox(height: AppSpacing.xs),
                    for (final d in matured) _DepositCard(deposit: d, accounts: accounts),
                  ],
                ],
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(label: 'Open a fixed deposit', icon: Icons.add_rounded, onPressed: () => context.push('/fixed-deposits/open')),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DepositCard extends ConsumerWidget {
  const _DepositCard({required this.deposit, required this.accounts});
  final FixedDeposit deposit;
  final List<BankAccount> accounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final d = deposit;
    final now = DateTime.now();
    final days = d.daysLeftAt(now);
    final funding = accounts.where((a) => a.id == d.fundingAccountId).firstOrNull;
    final when = formatGroupDate(d.maturityDate, now);
    final timeLeft = d.active ? (days == 0 ? 'Matures today' : '$days ${days == 1 ? 'day' : 'days'} left') : 'Matured';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: GlassCard(
        radius: 22,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              label: '${d.name} ${d.maskedNumber}. ${formatMoney(d.principal)} for ${fdTermLabel(d.termMonths)} at ${d.rate} percent. '
                  '${d.active ? 'Matures on $when, $timeLeft.' : 'Matured on $when.'} '
                  '${d.active ? 'Interest at maturity ${formatMoney(d.interestAtMaturity)}.' : 'Paid out ${formatMoney(d.paidOut)}.'} At maturity: ${fdRenewalLabel(d.renewal)}.',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(d.active ? Icons.lock_clock_rounded : Icons.event_available_rounded, color: d.active ? c.accent : c.success),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${fdTermLabel(d.termMonths)} · ${d.rate}%', style: AppTypography.title),
                              Text(d.maskedNumber, style: AppTypography.caption.copyWith(color: c.textSecondary)),
                            ],
                          ),
                        ),
                        Text(formatMoney(d.principal), style: AppTypography.amountSmall),
                      ],
                    ),
                    if (d.active) ...[
                      const SizedBox(height: AppSpacing.sm),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: d.progressAt(now)),
                          duration: AppAnimations.scaled(context, AppAnimations.number),
                          curve: AppAnimations.standard,
                          builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: c.divider, color: c.accent),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('$timeLeft · matures $when', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    SummaryRow(d.active ? 'Interest at maturity' : 'Paid out', formatMoney(d.active ? d.interestAtMaturity : d.paidOut)),
                    if (d.active) SummaryRow('Total at maturity', formatMoney(d.valueAtMaturity), bold: true) else SummaryRow('Matured on', when),
                    SummaryRow('Started', formatGroupDate(d.startDate, now)),
                    if (funding != null) SummaryRow('Funded from', '${funding.name} ${funding.maskedNumber}'),
                    if (d.renewals > 0) SummaryRow('Renewed', '${d.renewals} ${d.renewals == 1 ? 'time' : 'times'}'),
                    SummaryRow('At maturity', fdRenewalLabel(d.renewal)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
