import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/animated_success_icon.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/payment_models.dart';
import '../domain/recurrence.dart';
import 'authorize_sheet.dart';
import 'payment_submission.dart';
import 'payment_widgets.dart';
import '../../../core/widgets/error_view.dart';

/// Review → authenticate → process → receipt, shared by every payment type.
class ConfirmPaymentPage extends ConsumerStatefulWidget {
  const ConfirmPaymentPage({super.key});

  @override
  ConsumerState<ConfirmPaymentPage> createState() => _ConfirmPaymentPageState();
}

class _ConfirmPaymentPageState extends ConsumerState<ConfirmPaymentPage> {
  late PaymentDraft? _draft = ref.read(paymentDraftProvider);

  Future<void> _confirm(PaymentDraft draft) async {
    final result = await authorizePayment(
      context,
      summary: 'Authorise ${formatMoney(draft.total)} to ${draft.payee}.',
    );
    if (!mounted) return;
    switch (result) {
      case AuthResult.approved:
        await ref.read(paymentSubmissionProvider.notifier).submit(draft);
        final ok = ref.read(paymentSubmissionProvider).phase == SubmitPhase.success;
        ok ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
      case AuthResult.locked:
        HapticFeedback.heavyImpact();
        BankSnackbar.show(context, 'Too many incorrect PINs. This payment was not made.', kind: SnackKind.error);
      case AuthResult.cancelled:
        break;
    }
  }

  void _close() {
    ref.read(paymentDraftProvider.notifier).set(null);
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final sub = ref.watch(paymentSubmissionProvider);
    if (draft == null) {
      return FlowPage(
        title: 'Review payment',
        child: EmptyState(
          icon: Icons.receipt_long_rounded,
          title: 'Nothing to review',
          message: 'Start a payment from the Payments tab.',
          action: TextButton(onPressed: () => context.go('/payments'), child: const Text('Go to Payments')),
        ),
      );
    }
    final processing = sub.phase == SubmitPhase.processing;
    final done = sub.phase == SubmitPhase.success;
    return PopScope(
      canPop: !processing && !done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && done) _close();
      },
      child: FlowPage(
        title: switch (sub.phase) {
          SubmitPhase.review => 'Review payment',
          SubmitPhase.processing => 'Processing',
          SubmitPhase.success => 'Receipt',
          SubmitPhase.failed => 'Payment failed',
        },
        showBack: sub.phase == SubmitPhase.review,
        child: AnimatedSwitcher(
          duration: AppAnimations.scaled(context, AppAnimations.slow),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: child),
          ),
          child: switch (sub.phase) {
            SubmitPhase.review => _Review(
              key: const ValueKey('review'),
              draft: draft,
              onChangeAccount: (id) => setState(() => _draft = draft.withAccount(id)),
              onConfirm: () => _confirm(draft),
            ),
            SubmitPhase.processing => const _Processing(key: ValueKey('processing')),
            SubmitPhase.success => ReceiptView(key: const ValueKey('success'), receipt: sub.receipt!, onDone: _close),
            SubmitPhase.failed => _Failed(
              key: const ValueKey('failed'),
              message: sub.message ?? 'Something went wrong.',
              onRetry: ref.read(paymentSubmissionProvider.notifier).reset,
              onClose: _close,
            ),
          },
        ),
      ),
    );
  }
}

class _Review extends ConsumerWidget {
  const _Review({super.key, required this.draft, required this.onChangeAccount, required this.onConfirm});
  final PaymentDraft draft;
  final ValueChanged<String> onChangeAccount;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final accounts = ref.watch(accountsProvider);
    final online = ref.watch(onlineProvider);
    return accounts.when(
      loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 320, radius: 28)),
      error: (e, _) => ErrorView(error: e, what: 'your accounts', onRetry: () => ref.invalidate(accountsProvider)),
      data: (all) {
        final payable = payableAccounts(all);
        final from = payable.firstWhere((a) => a.id == draft.fromAccountId, orElse: () => payable.first);
        final toOwn = draft.toAccountId == null ? null : all.firstWhere((a) => a.id == draft.toAccountId);
        final sameAccount = draft.toAccountId == from.id;
        final short = draft.total > from.balance;
        final problem = !online
            ? 'You’re offline. Reconnect to confirm this payment.'
            : sameAccount
            ? 'Choose a different account to send from.'
            : (short ? 'Your available balance is too low for this payment.' : null);
        return ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.lg),
          children: [
            AccountSelector(
              label: 'From',
              account: from,
              accounts: payable,
              onChanged: onChangeAccount,
            ),
            const SizedBox(height: AppSpacing.sm),
            GlassCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  Text('You’re paying', style: AppTypography.body.copyWith(color: c.textSecondary)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(formatMoney(draft.amount), style: AppTypography.amount),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Divider(color: c.divider),
                  SummaryRow('To', draft.payee),
                  SummaryRow(toOwn != null ? 'Account' : 'Details', draft.payeeDetail),
                  for (final (k, v) in draft.details) SummaryRow(k, v),
                  SummaryRow('Amount', formatMoney(draft.amount)),
                  SummaryRow('Fee', draft.fee == 0 ? 'Free' : formatMoney(draft.fee)),
                  SummaryRow('Total', formatMoney(draft.total), bold: true),
                  if (draft.reference.isNotEmpty) SummaryRow('Reference', draft.reference),
                  if (draft.isScheduled && draft.recurrence != Recurrence.once) SummaryRow('Repeats', recurrenceLabel(draft.recurrence).replaceFirst('Every', 'every')),
                  SummaryRow('When', draft.isScheduled ? formatGroupDate(draft.scheduledFor!, DateTime.now()) : 'Now'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: c.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You can cancel any time before you confirm. Once confirmed, payments can’t be undone.',
                    style: AppTypography.caption.copyWith(color: c.textSecondary),
                  ),
                ),
              ],
            ),
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      Icon(Icons.error_rounded, size: 18, color: c.error),
                      const SizedBox(width: 8),
                      Expanded(child: Text(problem, style: AppTypography.bodySmall.copyWith(color: c.error))),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: draft.isScheduled ? 'Confirm & schedule' : 'Confirm payment',
              icon: Icons.lock_rounded,
              onPressed: problem == null ? onConfirm : null,
            ),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.touchTarget)),
              onPressed: () => context.pop(),
              child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
            ),
          ],
        );
      },
    );
  }
}

class _Processing extends StatelessWidget {
  const _Processing({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Processing payment',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 88,
              height: 88,
              child: CircularProgressIndicator(strokeWidth: 5, color: c.accent, strokeCap: StrokeCap.round),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Processing your payment', style: AppTypography.h3),
            const SizedBox(height: 4),
            Text('Please keep the app open.', style: AppTypography.body.copyWith(color: c.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({super.key, required this.message, required this.onRetry, required this.onClose});
  final String message;
  final VoidCallback onRetry, onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cancel_rounded, size: 88, color: c.error),
          const SizedBox(height: AppSpacing.lg),
          Semantics(liveRegion: true, child: const Text('Payment unsuccessful', style: AppTypography.h2, textAlign: TextAlign.center)),
          const SizedBox(height: AppSpacing.xs),
          Text(message, style: AppTypography.bodyLarge.copyWith(color: c.textSecondary), textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs),
          Text('No money has left your account.', style: AppTypography.body.copyWith(color: c.textSecondary)),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(label: 'Review again', onPressed: onRetry),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.touchTarget)),
            onPressed: onClose,
            child: Text('Close', style: TextStyle(color: c.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// Success screen and receipt, with share and save.
class ReceiptView extends ConsumerWidget {
  const ReceiptView({super.key, required this.receipt, required this.onDone});
  final Receipt receipt;
  final VoidCallback onDone;

  String get _title {
    if (receipt.scheduled) return 'Payment Scheduled';
    return switch (receipt.kind) {
      PaymentKind.transfer => 'Transfer Successful',
      PaymentKind.bill => 'Bill Paid',
      PaymentKind.qr => 'Payment Successful',
      PaymentKind.loan => 'Loan Payment Successful',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final service = ref.read(receiptServiceProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.lg),
      children: [
        const Center(child: AnimatedSuccessIcon(size: 88)),
        const SizedBox(height: AppSpacing.md),
        Semantics(header: true, liveRegion: true, child: Text(_title, style: AppTypography.h1, textAlign: TextAlign.center)),
        const SizedBox(height: 4),
        Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(formatMoney(receipt.amount), style: AppTypography.amount))),
        const SizedBox(height: AppSpacing.md),
        GlassCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              SummaryRow('Recipient', receipt.payee),
              for (final (k, v) in receipt.details) SummaryRow(k, v),
              SummaryRow('Amount', formatMoney(receipt.amount)),
              SummaryRow('Fee', receipt.fee == 0 ? 'Free' : formatMoney(receipt.fee)),
              SummaryRow('Account used', '${receipt.fromName} ${receipt.fromMasked}'),
              if (receipt.reference.isNotEmpty) SummaryRow('Reference', receipt.reference),
              SummaryRow('Transaction ID', receipt.id),
              SummaryRow('Date & time', '${formatGroupDate(receipt.date, DateTime.now())}, ${TimeOfDay.fromDateTime(receipt.date).format(context)}'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.touchTarget), side: BorderSide(color: c.glassBorder), foregroundColor: c.textPrimary),
                onPressed: () => service.share(receipt),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.touchTarget), side: BorderSide(color: c.glassBorder), foregroundColor: c.textPrimary),
                onPressed: () async {
                  try {
                    await service.save(receipt);
                    if (context.mounted) BankSnackbar.show(context, 'Receipt saved to this device.', kind: SnackKind.success);
                  } catch (_) {
                    if (context.mounted) BankSnackbar.show(context, 'Couldn’t save the receipt.', kind: SnackKind.error);
                  }
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        PrimaryButton(label: 'Done', onPressed: onDone),
      ],
    );
  }
}
