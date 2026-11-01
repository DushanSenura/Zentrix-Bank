import 'package:bank_app/app/providers.dart';
import 'package:bank_app/app/router.dart';
import 'package:bank_app/features/payments/data/mock_ledger.dart';
import 'package:bank_app/shared/models/payment_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

PaymentDraft pay(String loanId, double amount, {String from = 'a-sav'}) => PaymentDraft(
  kind: PaymentKind.loan,
  fromAccountId: from,
  payee: 'Loan instalment',
  payeeDetail: loanId,
  amount: amount,
  loanId: loanId,
);

void main() {
  setUpAll(loadAppFont);

  group('MockLedger loan payments', () {
    test('interest is paid first; the rest reduces the balance, and a full instalment advances the schedule', () {
      final ledger = MockLedger();
      final before = ledger.loans.firstWhere((l) => l.id == 'l-veh');
      final savingsBefore = ledger.accounts.firstWhere((a) => a.id == 'a-sav').balance;

      final receipt = ledger.post(pay('l-veh', before.monthlyPayment));

      final after = ledger.loans.firstWhere((l) => l.id == 'l-veh');
      final principalPaid = before.monthlyPayment - before.monthlyInterest;
      expect(after.outstanding, closeTo(before.outstanding - principalPaid, 0.001));
      expect(after.remainingMonths, before.remainingMonths - 1);
      expect(after.nextPaymentDate.isAfter(before.nextPaymentDate), isTrue);
      expect(after.history.first.amount, before.monthlyPayment);
      expect(ledger.accounts.firstWhere((a) => a.id == 'a-sav').balance, closeTo(savingsBefore - before.monthlyPayment, 0.001));
      expect(receipt.kind, PaymentKind.loan);
      expect(ledger.transactions.first.method, 'Loan instalment');
      // The other loan is untouched.
      expect(ledger.loans.firstWhere((l) => l.id == 'l-per').remainingMonths, 12);
    });

    test('a smaller or extra payment changes the balance but not the schedule counters wrongly', () {
      final ledger = MockLedger();
      final before = ledger.loans.firstWhere((l) => l.id == 'l-per');

      ledger.post(pay('l-per', before.monthlyInterest + 1000)); // less than an instalment
      final partial = ledger.loans.firstWhere((l) => l.id == 'l-per');
      expect(partial.outstanding, closeTo(before.outstanding - 1000, 0.001));
      expect(partial.remainingMonths, before.remainingMonths, reason: 'the instalment was not met');
      expect(partial.nextPaymentDate, before.nextPaymentDate);

      ledger.post(pay('l-per', partial.monthlyPayment + 20000)); // extra counts as the instalment
      expect(ledger.loans.firstWhere((l) => l.id == 'l-per').remainingMonths, before.remainingMonths - 1);
    });

    test('settling in full closes the loan, and a closed loan cannot be paid again', () {
      final ledger = MockLedger();
      final l = ledger.loans.firstWhere((x) => x.id == 'l-per');
      ledger.post(pay('l-per', (l.payoffAmount * 100).ceil() / 100));
      final closed = ledger.loans.firstWhere((x) => x.id == 'l-per');
      expect(closed.closed, isTrue);
      expect(closed.remainingMonths, 0);
      expect(
        () => ledger.post(pay('l-per', 100)),
        throwsA(isA<PaymentException>().having((e) => e.message, 'message', contains('fully repaid'))),
      );
    });

    test('refuses to take more than the loan needs, an unknown loan, or money the account does not have', () {
      final ledger = MockLedger();
      final l = ledger.loans.firstWhere((x) => x.id == 'l-veh');
      final savings = ledger.accounts.firstWhere((a) => a.id == 'a-sav').balance;

      expect(() => ledger.post(pay('l-veh', l.payoffAmount + 500)), throwsA(isA<PaymentException>()));
      expect(() => ledger.post(pay('l-nope', 100)), throwsA(isA<PaymentException>().having((e) => e.failure, 'failure', PaymentFailure.invalidRecipient)));
      expect(
        () => ledger.post(pay('l-veh', savings + 1)),
        throwsA(isA<PaymentException>().having((e) => e.failure, 'failure', PaymentFailure.insufficientFunds)),
      );
      // Nothing moved on any refusal.
      expect(ledger.accounts.firstWhere((a) => a.id == 'a-sav').balance, savings);
      expect(ledger.loans.firstWhere((x) => x.id == 'l-veh').outstanding, l.outstanding);
    });

    test('a scheduled loan payment is refused rather than silently applied now', () {
      final ledger = MockLedger();
      final d = PaymentDraft(
        kind: PaymentKind.loan,
        fromAccountId: 'a-sav',
        payee: 'x',
        payeeDetail: 'y',
        amount: 5000,
        loanId: 'l-per',
        scheduledFor: DateTime.now().add(const Duration(days: 3)),
      );
      expect(() => ledger.post(d), throwsA(isA<PaymentException>()));
    });
  });

  testWidgets('Pay instalment: choose, review, authorise, and the balance on the Loans screen drops', (tester) async {
    useScreen(tester, const Size(390, 2000));
    final env = TestEnv();
    await openLogin(tester, env);
    await signInAsDemo(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    c.read(routerProvider).push('/loans');
    await advance(tester, 100);
    await advance(tester, 900);
    await advance(tester, 700);

    final before = (await tester.runAsync(() => c.read(loansProvider.future)))!.first;
    await tester.tap(find.text('Pay instalment').first);
    await advance(tester, 100);
    await advance(tester, 700);
    expect(find.textContaining('Monthly instalment'), findsOneWidget);
    expect(find.textContaining('Settle in full'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await advance(tester, 100);
    await advance(tester, 800);
    expect(find.text('Review payment'), findsOneWidget);
    expect(find.text('Vehicle loan instalment'), findsOneWidget);

    await tester.ensureVisible(find.text('Confirm payment'));
    await tester.tap(find.text('Confirm payment'));
    await advance(tester, 100);
    await advance(tester, 700);
    await tapPin(tester, '246813');
    await advance(tester, 300);
    await tapPin(tester, '246813');
    await advance(tester, 500);
    await advance(tester, 700);
    await advance(tester, 1800);
    await advance(tester, 800);
    expect(find.text('Loan Payment Successful'), findsOneWidget);

    final after = (await tester.runAsync(() => c.read(loansProvider.future)))!.first;
    expect(after.outstanding, lessThan(before.outstanding));
    expect(after.remainingMonths, before.remainingMonths - 1);
    await advance(tester, 3000);
  });
}
