import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/bank_dialog.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/payment_models.dart';
import '../domain/recurrence.dart';

/// Upcoming and repeating payments: see what is queued, when it runs next, and stop it.
class ScheduledPaymentsPage extends ConsumerWidget {
  const ScheduledPaymentsPage({super.key});

  Future<void> _cancel(BuildContext context, WidgetRef ref, ScheduledPayment p) async {
    final repeats = p.recurrence != Recurrence.once;
    final ok = await showBankDialog(
      context,
      title: repeats ? 'Stop this repeating payment?' : 'Cancel this payment?',
      message: repeats
          ? '${formatMoney(p.amount)} to ${p.payee} will no longer be sent ${recurrenceLabel(p.recurrence).toLowerCase()}. Payments already made are not affected.'
          : '${formatMoney(p.amount)} to ${p.payee} will not be sent.',
      confirmLabel: repeats ? 'Stop payments' : 'Cancel payment',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(scheduledPaymentRepositoryProvider).cancel(p.id);
      ref.invalidate(scheduledPaymentsProvider);
      ref.invalidate(transactionsProvider);
      if (context.mounted) BankSnackbar.show(context, repeats ? 'Repeating payment stopped.' : 'Payment cancelled.', kind: SnackKind.success);
    } on PaymentException catch (e) {
      ref.invalidate(scheduledPaymentsProvider);
      if (context.mounted) BankSnackbar.show(context, e.message, kind: SnackKind.error);
    } catch (_) {
      if (context.mounted) BankSnackbar.show(context, 'Couldn’t cancel it. Nothing was changed — please try again.', kind: SnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(scheduledPaymentsProvider);
    final accounts = ref.watch(accountsProvider).value ?? const <BankAccount>[];
    return FlowPage(
      title: 'Scheduled payments',
      child: RefreshIndicator(
        onRefresh: () async => ref.refresh(scheduledPaymentsProvider.future),
        child: list.when(
          loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 220, radius: 24)),
          error: (e, _) => ErrorView(error: e, what: 'scheduled payments', onRetry: () => ref.invalidate(scheduledPaymentsProvider)),
          data: (all) {
            if (all.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: AppSpacing.xl),
                  EmptyState(
                    icon: Icons.event_repeat_rounded,
                    title: 'Nothing scheduled',
                    message: 'When you schedule a transfer for later, or set it to repeat, it will appear here.',
                  ),
                ],
              );
            }
            final active = all.where((p) => p.active).toList();
            final done = all.where((p) => !p.active).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
              children: [
                if (active.isNotEmpty) ...[
                  Semantics(header: true, child: const Text('Upcoming', style: AppTypography.h3)),
                  const SizedBox(height: AppSpacing.xs),
                  for (final p in active) _Tile(payment: p, accounts: accounts, onCancel: () => _cancel(context, ref, p)),
                ],
                if (done.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Semantics(header: true, child: const Text('Finished', style: AppTypography.h3)),
                  const SizedBox(height: AppSpacing.xs),
                  for (final p in done) _Tile(payment: p, accounts: accounts),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.payment, required this.accounts, this.onCancel});
  final ScheduledPayment payment;
  final List<BankAccount> accounts;
  final VoidCallback? onCancel;

  String get _status => switch (payment.status) {
    ScheduleStatus.active => 'Next: ',
    ScheduleStatus.completed => 'Paid',
    ScheduleStatus.cancelled => 'Cancelled',
    ScheduleStatus.failed => 'Not paid',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = payment;
    final from = accounts.where((a) => a.id == p.fromAccountId).firstOrNull;
    final when = formatGroupDate(p.nextRun, DateTime.now());
    final failed = p.status == ScheduleStatus.failed || (p.active && p.lastMessage != null);
    final summary = '${formatMoney(p.amount)} to ${p.payee}, ${recurrenceLabel(p.recurrence).toLowerCase()}, '
        '${p.active ? 'next on $when' : _status.toLowerCase()}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: GlassCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        radius: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              label: summary,
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(p.recurrence == Recurrence.once ? Icons.event_rounded : Icons.event_repeat_rounded, color: c.accent),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.payee, style: AppTypography.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(
                            '${recurrenceLabel(p.recurrence)} · ${p.active ? 'Next $when' : _status}',
                            style: AppTypography.bodySmall.copyWith(color: c.textSecondary),
                          ),
                          if (from != null) Text('From ${from.name} ${from.maskedNumber}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                          if (p.runCount > 0) Text('Paid ${p.runCount} ${p.runCount == 1 ? 'time' : 'times'} so far', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(formatMoney(p.amount), style: AppTypography.amountSmall),
                  ],
                ),
              ),
            ),
            if (failed && p.lastMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Semantics(
                  liveRegion: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 18, color: c.error),
                      const SizedBox(width: 6),
                      Expanded(child: Text('Last run failed: ${p.lastMessage}', style: AppTypography.caption.copyWith(color: c.error))),
                    ],
                  ),
                ),
              ),
            if (onCancel != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
                  onPressed: onCancel,
                  child: Text(p.recurrence == Recurrence.once ? 'Cancel payment' : 'Stop repeating', style: TextStyle(color: c.error)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
