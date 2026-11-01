import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/payment_models.dart';
import '../../../shared/models/service_models.dart';
import 'dispute_pages.dart';
import '../../dashboard/presentation/widgets.dart';
import '../../payments/presentation/payment_widgets.dart';

/// A receipt view of a historical transaction, for sharing or saving.
Receipt receiptFromTransaction(Transaction t, BankAccount? account) => Receipt(
  id: t.id,
  kind: t.category == TxCategory.bills ? PaymentKind.bill : PaymentKind.transfer,
  status: t.status,
  payee: t.merchant,
  amount: t.amount.abs(),
  fee: 0,
  fromName: account?.name ?? 'Account',
  fromMasked: account?.maskedNumber ?? '',
  reference: t.reference,
  date: t.date,
  details: [('Category', categoryLabel(t.category)), if (t.method.isNotEmpty) ('Method', t.method)],
);

class TransactionDetailsPage extends ConsumerWidget {
  const TransactionDetailsPage({super.key, required this.id, this.initial});
  final String id;
  final Transaction? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final all = ref.watch(transactionsProvider).value ?? const <Transaction>[];
    final tx = initial ?? all.where((t) => t.id == id).firstOrNull;
    if (tx == null) {
      return const FlowPage(
        title: 'Transaction',
        child: EmptyState(icon: Icons.receipt_long_rounded, title: 'Transaction not found', message: 'It may have been removed.'),
      );
    }
    final accounts = ref.watch(accountsProvider).value ?? const <BankAccount>[];
    final account = accounts.where((a) => a.id == tx.accountId).firstOrNull;
    final income = tx.amount >= 0;
    final statusText = switch (tx.status) {
      TxStatus.completed => 'Completed',
      TxStatus.pending => 'Pending',
      TxStatus.failed => 'Failed',
    };
    final statusColor = switch (tx.status) {
      TxStatus.completed => c.success,
      TxStatus.pending => c.warning,
      TxStatus.failed => c.error,
    };
    final receipts = ref.read(receiptServiceProvider);
    final receipt = receiptFromTransaction(tx, account);

    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          side: BorderSide(color: c.glassBorder),
          foregroundColor: c.textPrimary,
        ),
        onPressed: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, size: 22), const SizedBox(height: 2), FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: AppTypography.caption))],
        ),
      ),
    );

    return FlowPage(
      title: 'Transaction',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(shape: BoxShape.circle, color: (income ? c.success : c.accent).withAlpha(36)),
              child: Icon(categoryIcon(tx.category), size: 30, color: income ? c.success : c.accent),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(tx.merchant, style: AppTypography.h3, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Semantics(
            label: '${income ? 'Received' : 'Paid'} ${formatMoney(tx.amount.abs())}',
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(formatMoney(tx.amount, signed: true), style: AppTypography.amount.copyWith(color: income ? c.success : c.textPrimary)),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: statusColor.withAlpha(36)),
              child: Text(statusText, style: AppTypography.caption.copyWith(color: statusColor, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          GlassCard(
            radius: 22,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                SummaryRow(income ? 'From' : 'To', tx.merchant),
                SummaryRow('Amount', formatMoney(tx.amount.abs())),
                SummaryRow('Date', formatGroupDate(tx.date, DateTime.now())),
                SummaryRow('Time', TimeOfDay.fromDateTime(tx.date).format(context)),
                SummaryRow('Category', categoryLabel(tx.category)),
                if (tx.method.isNotEmpty) SummaryRow('Payment method', tx.method),
                if (account != null) SummaryRow('Account', '${account.name} ${account.maskedNumber}'),
                if (tx.reference.isNotEmpty) SummaryRow('Reference', tx.reference),
                SummaryRow('Transaction ID', tx.id),
              ],
            ),
          ),
          if (ref.watch(disputesProvider).value?.where((d) => d.transactionId == tx.id).firstOrNull case final existing?) ...[
            const SizedBox(height: AppSpacing.sm),
            GlassCard(
              radius: 18,
              padding: const EdgeInsets.all(AppSpacing.sm),
              onTap: () => context.push('/disputes'),
              semanticLabel: 'Dispute ${existing.id}, ${disputeStatusLabel(existing.statusAt(DateTime.now()))}. Open my disputes',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Icon(Icons.fact_check_rounded, color: c.accent),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: Text('Dispute ${existing.id} · ${disputeStatusLabel(existing.statusAt(DateTime.now()))}', style: AppTypography.bodySmall)),
                    Icon(Icons.chevron_right_rounded, color: c.textSecondary),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (!income && tx.status == TxStatus.completed) ...[
                action(Icons.download_rounded, 'Receipt', () async {
                  try {
                    await receipts.save(receipt);
                    if (context.mounted) BankSnackbar.show(context, 'Receipt saved to this device.', kind: SnackKind.success);
                  } catch (_) {
                    if (context.mounted) BankSnackbar.show(context, 'Couldn’t save the receipt.', kind: SnackKind.error);
                  }
                }),
                const SizedBox(width: AppSpacing.xs),
                action(Icons.ios_share_rounded, 'Share', () => receipts.share(receipt)),
                const SizedBox(width: AppSpacing.xs),
                action(Icons.replay_rounded, 'Repeat', () async {
                  final draft = await ref.read(transactionRepositoryProvider).repeatDraft(tx.id);
                  if (!context.mounted) return;
                  if (draft == null) {
                    BankSnackbar.show(context, 'Only payments made in this app can be repeated.', kind: SnackKind.info);
                    return;
                  }
                  ref.read(paymentDraftProvider.notifier).set(draft);
                  context.push('/pay/confirm');
                }),
                const SizedBox(width: AppSpacing.xs),
              ],
              action(Icons.flag_rounded, 'Report', () {
                final blocked = disputeBlockReason(tx);
                if (blocked != null) {
                  BankSnackbar.show(context, blocked, kind: SnackKind.info);
                  return;
                }
                context.push('/disputes/new?tx=${Uri.encodeQueryComponent(tx.id)}');
              }),
            ],
          ),
        ],
      ),
    );
  }
}
