import 'package:bank_app/app/providers.dart';
import 'package:bank_app/app/router.dart';
import 'package:bank_app/features/loans/presentation/loan_application_page.dart';
import 'package:bank_app/features/payments/data/mock_ledger.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:bank_app/shared/models/payment_models.dart';
import 'package:bank_app/shared/models/service_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

const _pin = '246813';

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

Future<ProviderContainer> signedIn(WidgetTester tester, {Size size = const Size(390, 2400)}) async {
  useScreen(tester, size);
  await openLogin(tester, TestEnv());
  await signInAsDemo(tester);
  return containerOf(tester);
}

/// The first authorisation of a demo session creates the PIN.
Future<void> createPin(WidgetTester tester) async {
  await tapPin(tester, _pin);
  await advance(tester, 300);
  await tapPin(tester, _pin);
  await advance(tester, 500);
  await advance(tester, 700);
}

Future<void> open(WidgetTester tester, ProviderContainer c, String route) async {
  c.read(routerProvider).push(route);
  await advance(tester, 100);
  await advance(tester, 900);
  await advance(tester, 700);
}

Transaction paid(MockLedger l, String merchant) => l.transactions.firstWhere((t) => t.merchant == merchant);

void main() {
  setUpAll(loadAppFont);

  group('disputes (ledger rules)', () {
    test('a settled payment out can be disputed and then appears once, newest first', () {
      final l = MockLedger();
      final t = paid(l, 'Keells Supermarket');
      final d = l.raiseDispute(t, DisputeReason.duplicate, '  charged twice  ');
      expect(d.transactionId, t.id);
      expect(d.amount, t.amount.abs());
      expect(d.details, 'charged twice', reason: 'trimmed');
      expect(d.id, startsWith('DSP'));
      expect(l.disputes.first.id, d.id);
      expect(d.statusAt(d.createdAt), DisputeStatus.received);
      expect(d.statusAt(d.createdAt.add(const Duration(days: 2))), DisputeStatus.inReview);
    });

    test('the same payment cannot be disputed twice', () {
      final l = MockLedger();
      final t = paid(l, 'Starbucks');
      l.raiseDispute(t, DisputeReason.notMine, '');
      expect(() => l.raiseDispute(t, DisputeReason.other, 'again'), throwsA(isA<DisputeException>().having((e) => e.message, 'message', contains('already raised'))));
      expect(l.disputes, hasLength(1));
    });

    test('income, pending, failed and own-account moves are not disputable, and say why', () {
      final l = MockLedger();
      final income = l.transactions.firstWhere((t) => t.amount > 0);
      expect(disputeBlockReason(income), contains('payments you made'));
      final pending = l.transactions.firstWhere((t) => t.status == TxStatus.pending);
      expect(disputeBlockReason(pending), contains('pending'));
      final failed = Transaction(id: 'f', merchant: 'x', category: TxCategory.bills, amount: -5, date: _d, status: TxStatus.failed);
      expect(disputeBlockReason(failed), contains('didn’t go through'));
      final own = Transaction(id: 'o', merchant: 'x', category: TxCategory.transfer, amount: -5, date: _d, internal: true);
      expect(disputeBlockReason(own), contains('your own accounts'));
      expect(() => l.raiseDispute(income, DisputeReason.other, 'x'), throwsA(isA<DisputeException>()));
    });

    test('a transaction that is not in this customer’s history is refused', () {
      final l = MockLedger();
      final stranger = Transaction(id: 'ZZ-not-mine', merchant: 'x', category: TxCategory.bills, amount: -100, date: _d);
      expect(() => l.raiseDispute(stranger, DisputeReason.notMine, ''), throwsA(isA<DisputeException>().having((e) => e.message, 'message', contains('couldn’t find'))));
    });
  });

  group('opening accounts (ledger rules)', () {
    test('a savings account is funded from an existing one, and both sides are recorded', () {
      final l = MockLedger();
      final before = l.accounts.firstWhere((a) => a.id == 'a-sav').balance;
      final a = l.openAccount(type: AccountType.savings, name: 'Holiday fund', fromAccountId: 'a-sav', amount: 5000);
      expect(a.name, 'Holiday fund');
      expect(a.balance, 5000);
      expect(a.maskedNumber, matches(RegExp(r'^•••• \d{4}$')));
      expect(l.accounts.firstWhere((x) => x.id == 'a-sav').balance, before - 5000);
      expect(l.accounts.length, 4);
      expect(l.transactions.where((t) => t.id.startsWith('AO')).map((t) => t.internal), [true, true]);
      expect(l.canPayFrom(a.id), isTrue, reason: 'a new savings account can send money');
    });

    test('fixed deposits are not opened here: they have their own section', () {
      final l = MockLedger();
      expect(
        () => l.openAccount(type: AccountType.fixedDeposit, name: '', fromAccountId: 'a-sav', amount: 50000),
        throwsA(isA<PaymentException>().having((e) => e.message, 'message', contains('Fixed deposits section'))),
      );
      expect(l.accounts.length, 3);
    });

    test('refusals leave everything untouched', () {
      final l = MockLedger();
      final sav = l.accounts.firstWhere((a) => a.id == 'a-sav').balance;
      void refused(void Function() f, Pattern message) =>
          expect(f, throwsA(isA<PaymentException>().having((e) => e.message, 'message', contains(message))));
      refused(() => l.openAccount(type: AccountType.savings, name: '', fromAccountId: 'a-sav', amount: 500), 'minimum');
      refused(() => l.openAccount(type: AccountType.savings, name: '', fromAccountId: 'a-sav', amount: sav + 1), 'too low');
      refused(() => l.openAccount(type: AccountType.savings, name: '', fromAccountId: 'a-fd', amount: 5000), 'savings or current');
      refused(() => l.openAccount(type: AccountType.foreignCurrency, name: '', fromAccountId: 'a-sav', amount: 5000), 'branch');
      expect(l.accounts.length, 3);
      expect(l.accounts.firstWhere((a) => a.id == 'a-sav').balance, sav);
    });

    test('there is a ceiling on how many accounts one customer can hold', () {
      final l = MockLedger();
      for (var i = 0; i < maxAccountsPerCustomer - 3; i++) {
        l.openAccount(type: AccountType.savings, name: 'S$i', fromAccountId: 'a-sav', amount: 1000);
      }
      expect(l.accounts.length, maxAccountsPerCustomer);
      expect(() => l.openAccount(type: AccountType.savings, name: 'one too many', fromAccountId: 'a-sav', amount: 1000), throwsA(isA<PaymentException>()));
    });
  });

  group('loan applications (ledger rules)', () {
    LoanApplicationRequest req({LoanType type = LoanType.personal, double amount = 500000, int months = 36, double income = 200000}) =>
        LoanApplicationRequest(type: type, amount: amount, termMonths: months, monthlyIncome: income, employment: 'Employed');

    test('a valid application is recorded as received, never approved', () {
      final l = MockLedger();
      final app = l.applyForLoan(req());
      expect(app.id, startsWith('LA'));
      expect(app.indicativeMonthly, greaterThan(0));
      expect(app.statusAt(app.createdAt), LoanApplicationStatus.received);
      expect(app.statusAt(app.createdAt.add(const Duration(days: 3))), LoanApplicationStatus.underReview);
      expect(LoanApplicationStatus.values.map((s) => s.name), ['received', 'underReview'], reason: 'there is no "approved" state to show');
      expect(l.loans.length, 2, reason: 'no loan was created, and no money moved');
    });

    test('amounts and terms outside the loan type are refused', () {
      final l = MockLedger();
      for (final bad in [req(amount: 1000), req(amount: 999999999), req(months: 1), req(months: 500), req(income: 0), req(type: LoanType.home, amount: 500000)]) {
        expect(() => l.applyForLoan(bad), throwsA(isA<LoanApplicationException>()));
      }
      expect(l.loanApplications, isEmpty);
    });

    test('at most two applications per loan type are held at once', () {
      final l = MockLedger()
        ..applyForLoan(req())
        ..applyForLoan(req());
      expect(() => l.applyForLoan(req()), throwsA(isA<LoanApplicationException>().having((e) => e.message, 'message', contains('two applications'))));
      l.applyForLoan(req(type: LoanType.education, amount: 200000, months: 24));
    });

    test('affordability hint thresholds', () {
      expect(affordabilityOf(30000, 100000), Affordability.comfortable);
      expect(affordabilityOf(45000, 100000), Affordability.stretched);
      expect(affordabilityOf(60000, 100000), Affordability.unlikely);
      expect(affordabilityOf(1000, 0), Affordability.unlikely);
    });
  });

  group('screens', () {
    testWidgets('Dispute: choose a reason, submit, get a reference, and see it listed and on the transaction', (tester) async {
      final c = await signedIn(tester);
      final tx = paid(c.read(ledgerProvider), 'Keells Supermarket');
      await open(tester, c, '/disputes/new?tx=${tx.id}');
      expect(find.text('What went wrong?'), findsOneWidget);
      expect(find.text('Keells Supermarket'), findsOneWidget);

      await tester.tap(find.text('Something else'));
      await advance(tester, 300);
      await tester.tap(find.text('Submit dispute'));
      await advance(tester, 300);
      expect(find.text('Please give a little more detail (at least 10 characters).'), findsOneWidget, reason: '"Something else" needs an explanation');

      await tester.enterText(find.byKey(const ValueKey('disputeDetails')), 'The shop charged my card but I paid cash.');
      await tester.tap(find.text('Submit dispute'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.text('Dispute received'), findsOneWidget);
      final ref = c.read(ledgerProvider).disputes.single.id;
      expect(find.text(ref), findsOneWidget);

      await tester.tap(find.text('View my disputes'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.text('My disputes'), findsOneWidget);
      expect(find.textContaining(ref), findsWidgets);
      expect(find.text('Received'), findsOneWidget);
      await advance(tester, 4500);
    });

    testWidgets('Dispute: "I don’t recognise this" points to protecting the account, and a repeat attempt is refused', (tester) async {
      final c = await signedIn(tester);
      final tx = paid(c.read(ledgerProvider), 'Starbucks');
      await open(tester, c, '/disputes/new?tx=${tx.id}');
      expect(find.textContaining('protect it now'), findsOneWidget);
      expect(find.text('Go to my cards'), findsOneWidget);
      await tester.tap(find.text('Submit dispute'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.text('Dispute received'), findsOneWidget);

      // Opening the form again for the same payment shows the refusal when submitting.
      c.read(routerProvider).pop();
      await advance(tester, 100);
      await advance(tester, 700);
      await open(tester, c, '/disputes/new?tx=${tx.id}');
      await tester.tap(find.text('Submit dispute'));
      await advance(tester, 100);
      await advance(tester, 900);
      expect(find.textContaining('already raised a dispute'), findsOneWidget);
      await advance(tester, 4500);
    });

    testWidgets('Dispute: a payment that cannot be disputed explains why instead of showing a form', (tester) async {
      final c = await signedIn(tester);
      final income = c.read(ledgerProvider).transactions.firstWhere((t) => t.amount > 0);
      await open(tester, c, '/disputes/new?tx=${income.id}');
      expect(find.text('This can’t be disputed'), findsOneWidget);
      expect(find.text('Submit dispute'), findsNothing);
    });

    testWidgets('Disputes list starts empty, and Help & support links to it', (tester) async {
      final c = await signedIn(tester);
      await open(tester, c, '/disputes');
      expect(find.text('No disputes'), findsOneWidget);
      c.read(routerProvider).pop();
      await advance(tester, 100);
      await advance(tester, 700);
      await open(tester, c, '/support');
      expect(find.text('My disputes'), findsOneWidget);
    });

    testWidgets('Open account: savings account is funded from another account, and fixed deposits point to their own section', (tester) async {
      final c = await signedIn(tester);
      final ledger = c.read(ledgerProvider);
      final before = ledger.accounts.firstWhere((a) => a.id == 'a-sav').balance;
      await open(tester, c, '/accounts/open');
      expect(find.text('Fixed'), findsNothing, reason: 'fixed deposits are no longer a choice on this screen');
      expect(find.text('Want to lock money away? Open a fixed deposit'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('openAmount')), '25000');
      await tester.ensureVisible(find.text('Open account'));
      await tester.tap(find.text('Open account'));
      await advance(tester, 100);
      await advance(tester, 700);
      await createPin(tester);
      await advance(tester, 1200);
      await advance(tester, 900);

      expect(find.text('Account opened'), findsOneWidget);
      expect(ledger.accounts.last.type, AccountType.savings);
      expect(ledger.accounts.last.balance, 25000);
      expect(ledger.accounts.firstWhere((a) => a.id == 'a-sav').balance, before - 25000);
      await advance(tester, 4500);
    });

    testWidgets('Open account: too much for the chosen account is caught before any PIN prompt', (tester) async {
      final c = await signedIn(tester);
      await open(tester, c, '/accounts/open');
      await tester.enterText(find.byKey(const ValueKey('openAmount')), '99999999');
      await tester.tap(find.text('Open account'));
      await advance(tester, 300);
      expect(find.textContaining('more than is in'), findsOneWidget);
      expect(find.text('Create a transaction PIN'), findsNothing);
    });

    testWidgets('Loan application: validation, live estimate and affordability, then it is sent and listed', (tester) async {
      final c = await signedIn(tester);
      await open(tester, c, '/loans');
      await tester.ensureVisible(find.text('Apply for a loan'));
      await tester.tap(find.text('Apply for a loan'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.text('Send application'), findsOneWidget);

      await tester.ensureVisible(find.text('Send application'));
      await tester.tap(find.text('Send application'));
      await advance(tester, 300);
      expect(find.text('Enter a valid amount.'), findsWidgets);
      expect(find.text('Please confirm to continue.'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('loanApplyAmount')), '500000');
      await tester.enterText(find.byKey(const ValueKey('loanApplyIncome')), '250000');
      await advance(tester, 300);
      expect(find.text('Estimated monthly'), findsOneWidget);
      expect(find.textContaining('usually comfortable'), findsOneWidget);
      expect(find.textContaining('not an offer or a decision'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('loanApplyIncome')), '40000');
      await advance(tester, 300);
      expect(find.textContaining('may be a stretch'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('loanApplyIncome')), '20000');
      await advance(tester, 300);
      expect(find.textContaining('smaller amount or longer term'), findsOneWidget);

      await tester.ensureVisible(find.text('Employment'));
      await tester.tap(find.text('Employment'));
      await advance(tester, 400);
      await tester.tap(find.text('Employed').last);
      await advance(tester, 400);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await advance(tester, 200);
      await tester.ensureVisible(find.text('Send application'));
      await tester.tap(find.text('Send application'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);

      expect(find.text('Application received'), findsOneWidget);
      expect(find.textContaining('isn’t an approval'), findsOneWidget);
      final saved = c.read(ledgerProvider).loanApplications.single;
      expect(saved.amount, 500000);
      expect(saved.employment, 'Employed');
      expect(find.text(saved.id), findsOneWidget);
      expect(employmentOptions, contains(saved.employment));

      await tester.tap(find.text('Back to loans'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.text('Your applications'), findsOneWidget);
      expect(find.textContaining(saved.id), findsWidgets);
      await advance(tester, 4500);
    });
  });
}

final _d = DateTime(2026, 11, 1);
