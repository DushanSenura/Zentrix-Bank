import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../analytics/domain/budgets.dart';
import '../../dashboard/presentation/widgets.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/engagement_models.dart';
import '../../../shared/models/payment_models.dart';

enum SubmitPhase { review, processing, success, failed }

@immutable
class PaymentSubmission {
  const PaymentSubmission({this.phase = SubmitPhase.review, this.receipt, this.failure, this.message});
  final SubmitPhase phase;
  final Receipt? receipt;
  final PaymentFailure? failure;
  final String? message;
}

class PaymentSubmissionController extends Notifier<PaymentSubmission> {
  @override
  PaymentSubmission build() => const PaymentSubmission();

  void reset() => state = const PaymentSubmission();

  /// Raises a notification when this payment pushes a category past 80% or 100% of its budget.
  /// Runs after the receipt is shown and can never fail the payment.
  Future<void> _checkBudgets(List<Transaction>? beforeTxs, List<Budget>? budgets) async {
    try {
      final list = budgets ?? await ref.read(budgetRepositoryProvider).budgets();
      if (list.isEmpty) return;
      final now = DateTime.now();
      final after = await ref.read(transactionsProvider.future);
      final alerts = budgetAlerts(budgetProgress(list, beforeTxs ?? const [], now), budgetProgress(list, after, now));
      for (final a in alerts) {
        final name = categoryLabel(a.category).toLowerCase();
        final p = a.progress;
        await ref.read(notificationsProvider.notifier).post(
          NotifCategory.payments,
          a.kind == BudgetAlertKind.over ? 'Over your $name budget' : 'Nearly at your $name budget',
          a.kind == BudgetAlertKind.over
              ? 'You’ve spent ${formatMoney(p.spent)} on $name this month, ${formatMoney(-p.remaining)} over your ${formatMoney(p.budget.monthlyLimit)} budget.'
              : 'You’ve used ${(p.fraction * 100).round()}% of your ${formatMoney(p.budget.monthlyLimit)} $name budget. ${formatMoney(p.remaining)} left this month.',
          severity: a.kind == BudgetAlertKind.over ? Severity.warning : Severity.info,
        );
      }
    } catch (_) {
      // A missing alert is better than a payment screen that errors after the money has moved.
    }
  }

  Future<void> submit(PaymentDraft draft) async {
    if (state.phase == SubmitPhase.processing) return;
    if (!ref.read(onlineProvider)) {
      state = const PaymentSubmission(
        phase: SubmitPhase.failed,
        failure: PaymentFailure.unavailable,
        message: 'You’re offline, so nothing was sent. Reconnect and try again.',
      );
      return;
    }
    state = const PaymentSubmission(phase: SubmitPhase.processing);
    // Where each budget stands before this payment, to tell which thresholds it crosses.
    final beforeTxs = ref.read(transactionsProvider).value;
    final budgetsBefore = ref.read(budgetsProvider).value;
    try {
      final receipt = await ref.read(paymentRepositoryProvider).pay(draft);
      // Balances and history changed on the "server": refetch them.
      ref.invalidate(accountsProvider);
      ref.invalidate(transactionsProvider);
      if (draft.kind == PaymentKind.loan) ref.invalidate(loansProvider);
      if (draft.isScheduled) ref.invalidate(scheduledPaymentsProvider);
      final notifications = ref.read(notificationsProvider.notifier);
      await notifications.post(
        draft.kind == PaymentKind.transfer ? NotifCategory.transactions : NotifCategory.payments,
        draft.isScheduled ? 'Payment scheduled' : (draft.kind == PaymentKind.transfer ? 'Transfer sent' : 'Payment successful'),
        '${formatMoney(draft.amount)} ${draft.isScheduled ? 'will be sent' : 'was sent'} to ${draft.payee}.',
      );
      if (draft.kind == PaymentKind.transfer && draft.amount >= 100000) {
        await notifications.post(NotifCategory.security, 'Large transfer', 'A transfer of ${formatMoney(draft.amount)} was made from your account.', severity: Severity.warning);
      }
      final toSave = draft.beneficiaryToSave;
      if (toSave != null) {
        try {
          await ref.read(beneficiariesProvider.notifier).add(toSave);
        } on PaymentException {
          // Already saved: the payment itself succeeded, so don't fail it.
        }
      }
      state = PaymentSubmission(phase: SubmitPhase.success, receipt: receipt);
      if (!draft.isScheduled) _checkBudgets(beforeTxs, budgetsBefore);
    } on PaymentException catch (e) {
      state = PaymentSubmission(phase: SubmitPhase.failed, failure: e.failure, message: e.message);
    } catch (_) {
      // Anything unexpected must still end the "processing" state, and must not claim the money moved.
      state = const PaymentSubmission(
        phase: SubmitPhase.failed,
        failure: PaymentFailure.unavailable,
        message: 'We couldn’t confirm this payment. Check your recent transactions before trying again.',
      );
    }
  }
}

final paymentSubmissionProvider = NotifierProvider.autoDispose<PaymentSubmissionController, PaymentSubmission>(
  PaymentSubmissionController.new,
);
