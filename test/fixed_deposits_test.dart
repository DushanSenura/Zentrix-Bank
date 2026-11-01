import 'package:bank_app/app/providers.dart';
import 'package:bank_app/app/router.dart';
import 'package:bank_app/features/fixed_deposits/domain/fixed_deposit.dart';
import 'package:bank_app/features/payments/data/mock_ledger.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:bank_app/shared/models/payment_models.dart';
import 'package:bank_app/shared/models/service_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

const _pin = '246813';

double bal(MockLedger l, String id) => l.accounts.firstWhere((a) => a.id == id).balance;

FixedDeposit openFd(MockLedger l, {double amount = 100000, int months = 12, FdRenewal renewal = FdRenewal.renewWithInterest}) =>
    l.openFixedDeposit(fromAccountId: 'a-sav', amount: amount, termMonths: months, renewal: renewal);

void main() {
  setUpAll(loadAppFont);

  group('terms, rates and dates', () {
    test('3, 6 and 12 months, or whole years from 24 to 120, are valid; nothing else is', () {
      for (final ok in [3, 6, 12, 24, 36, 48, 60, 120]) {
        expect(isValidFdTerm(ok), isTrue, reason: '$ok');
      }
      for (final bad in [0, 1, 2, 4, 9, 13, 18, 23, 25, 34, 47, 119, 132, 144, -12]) {
        expect(isValidFdTerm(bad), isFalse, reason: '$bad');
      }
    });

    test('the "more than 12 months" box explains what is wrong', () {
      expect(validateLongFdMonths(''), contains('Enter the number'));
      expect(validateLongFdMonths('abc'), contains('whole numbers'));
      expect(validateLongFdMonths('12'), contains('pick one of the choices'));
      expect(validateLongFdMonths('6'), contains('pick one of the choices'));
      expect(validateLongFdMonths('30'), contains('whole years'));
      expect(validateLongFdMonths('34'), contains('whole years'));
      expect(validateLongFdMonths('132'), contains('longest term'));
      for (final ok in ['24', '36', '48', ' 60 ', '120']) {
        expect(validateLongFdMonths(ok), isNull, reason: ok);
      }
    });

    test('longer terms never pay a lower rate', () {
      var last = 0.0;
      for (final m in [3, 6, 12, 24, 36, 48, 60, 72, 120]) {
        final r = fixedDepositRateFor(m);
        expect(r, greaterThanOrEqualTo(last), reason: '$m months');
        last = r;
      }
      expect(fixedDepositRateFor(3), 7.5);
      expect(fixedDepositRateFor(12), 9.5);
      expect(fixedDepositRateFor(24), 10.0);
    });

    test('interest is simple interest for the whole term, to the cent', () {
      expect(fixedDepositInterest(100000, 9.5, 12), 9500);
      expect(fixedDepositInterest(100000, 10.0, 24), 20000);
      expect(fixedDepositInterest(10000, 7.5, 3), 187.5);
      expect(fixedDepositInterest(33333, 8.5, 6), closeTo(1416.65, 0.005));
    });

    test('addMonths keeps the day, clamps to short months and crosses years', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29), reason: 'leap year');
      expect(addMonths(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
      expect(addMonths(DateTime(2026, 12, 1), 12), DateTime(2027, 12, 1));
      expect(addMonths(DateTime(2026, 5, 31), 6), DateTime(2026, 11, 30));
      expect(addMonths(DateTime(2026, 3, 10), -4), DateTime(2025, 11, 10));
    });

    test('labels', () {
      expect(fdTermLabel(6), '6 months');
      expect(fdTermLabel(36), '36 months (3 years)');
    });
  });

  group('MockLedger fixed deposits', () {
    test('opening moves the money, records both sides, and sets the rate, dates and instruction', () {
      final l = MockLedger();
      final before = bal(l, 'a-sav');
      final fd = openFd(l, months: 24, renewal: FdRenewal.payOut);
      expect(fd.rate, 10.0);
      expect(fd.principal, 100000);
      expect(fd.termMonths, 24);
      expect(fd.maturityDate, addMonths(fd.startDate, 24));
      expect(fd.renewal, FdRenewal.payOut);
      expect(fd.fundingAccountId, 'a-sav');
      expect(fd.interestAtMaturity, 20000);
      expect(fd.valueAtMaturity, 120000);

      expect(bal(l, 'a-sav'), before - 100000);
      final account = l.accounts.firstWhere((a) => a.id == fd.id);
      expect(account.type, AccountType.fixedDeposit);
      expect(account.balance, 100000);
      expect(l.canPayFrom(fd.id), isFalse, reason: 'money can’t be sent from a fixed deposit');
      expect(l.transactions.where((t) => t.id.startsWith('AO${fd.id}')).map((t) => t.internal), [true, true]);
      expect(l.fixedDeposits.where((d) => d.id == fd.id), hasLength(1));
    });

    test('refusals leave everything untouched', () {
      final l = MockLedger();
      final sav = bal(l, 'a-sav');
      void refused(void Function() f, Pattern message) => expect(f, throwsA(isA<PaymentException>().having((e) => e.message, 'message', contains(message))));

      refused(() => openFd(l, amount: 9999), 'minimum');
      refused(() => openFd(l, amount: sav + 1), 'too low');
      for (final badTerm in [0, 4, 13, 18, 34, 130]) {
        refused(() => openFd(l, months: badTerm), 'Choose 3, 6 or 12');
      }
      refused(() => l.openFixedDeposit(fromAccountId: 'a-fd', amount: 20000, termMonths: 12, renewal: FdRenewal.payOut), 'savings or current');
      refused(() => l.openFixedDeposit(fromAccountId: 'nope', amount: 20000, termMonths: 12, renewal: FdRenewal.payOut), 'savings or current');
      expect(l.accounts.length, 3);
      expect(bal(l, 'a-sav'), sav);
      expect(l.fixedDeposits.length, 1, reason: 'only the demo deposit');
    });

    test('the number of accounts is capped, deposits included', () {
      final l = MockLedger();
      for (var i = 0; i < maxAccountsPerCustomer - 3; i++) {
        openFd(l, amount: 10000);
      }
      expect(l.accounts.length, maxAccountsPerCustomer);
      expect(() => openFd(l, amount: 10000), throwsA(isA<PaymentException>()));
    });

    test('nothing happens before maturity', () {
      final l = MockLedger();
      final fd = openFd(l);
      final sav = bal(l, 'a-sav');
      l.runDue(fd.maturityDate.subtract(const Duration(days: 1)));
      expect(l.fixedDeposits.firstWhere((d) => d.id == fd.id).active, isTrue);
      expect(l.fixedDeposits.firstWhere((d) => d.id == fd.id).renewals, 0);
      expect(bal(l, 'a-sav'), sav);
    });

    test('pay out: principal and interest go to the funding account, and the deposit closes', () {
      final l = MockLedger();
      final fd = openFd(l, renewal: FdRenewal.payOut);
      final sav = bal(l, 'a-sav');
      l.runDue(fd.maturityDate.add(const Duration(hours: 1)));
      final done = l.fixedDeposits.firstWhere((d) => d.id == fd.id);
      expect(done.status, FdStatus.matured);
      expect(done.paidOut, 109500);
      expect(bal(l, 'a-sav'), sav + 109500);
      expect(bal(l, fd.id), 0);
      final interest = l.transactions.firstWhere((t) => t.merchant == 'Fixed deposit interest' && t.accountId == 'a-sav');
      expect(interest.amount, 9500);
      expect(interest.internal, isFalse, reason: 'interest is income');
      expect(interest.date, fd.maturityDate);
      final principalBack = l.transactions.firstWhere((t) => t.merchant == 'From fixed deposit');
      expect(principalBack.amount, 100000);
      expect(principalBack.internal, isTrue, reason: 'your own money coming back is not income');
    });

    test('renew with interest: interest joins the deposit and the next term earns on the total', () {
      final l = MockLedger();
      final fd = openFd(l, renewal: FdRenewal.renewWithInterest);
      final sav = bal(l, 'a-sav');
      l.runDue(fd.maturityDate.add(const Duration(hours: 1)));
      var d = l.fixedDeposits.firstWhere((x) => x.id == fd.id);
      expect(d.active, isTrue);
      expect(d.principal, 109500);
      expect(d.renewals, 1);
      expect(d.startDate, fd.maturityDate);
      expect(d.maturityDate, addMonths(fd.maturityDate, 12));
      expect(bal(l, fd.id), 109500);
      expect(bal(l, 'a-sav'), sav, reason: 'nothing was paid out');

      l.runDue(d.maturityDate.add(const Duration(hours: 1)));
      d = l.fixedDeposits.firstWhere((x) => x.id == fd.id);
      expect(d.renewals, 2);
      expect(d.principal, closeTo(109500 + 109500 * 0.095, 0.005));
    });

    test('renew the amount only: the interest is paid to the account and the principal stays', () {
      final l = MockLedger();
      final fd = openFd(l, renewal: FdRenewal.renewPrincipalOnly);
      final sav = bal(l, 'a-sav');
      l.runDue(fd.maturityDate.add(const Duration(hours: 1)));
      final d = l.fixedDeposits.firstWhere((x) => x.id == fd.id);
      expect(d.active, isTrue);
      expect(d.principal, 100000);
      expect(d.renewals, 1);
      expect(bal(l, 'a-sav'), sav + 9500);
      expect(bal(l, fd.id), 100000);
    });

    test('there is no way to change a deposit after it is opened', () {
      // The ledger and the repository expose no editing call at all: what was chosen on the day is what happens.
      final l = MockLedger();
      final fd = openFd(l, renewal: FdRenewal.renewWithInterest);
      final sav = bal(l, 'a-sav');
      l.runDue(fd.maturityDate.add(const Duration(hours: 1)));
      final after = l.fixedDeposits.firstWhere((d) => d.id == fd.id);
      expect(after.renewal, FdRenewal.renewWithInterest);
      expect(after.termMonths, fd.termMonths);
      expect(bal(l, 'a-sav'), sav, reason: 'it renewed with interest, as chosen');
    });

    test('a deposit left unattended for years keeps renewing, one term at a time', () {
      final l = MockLedger();
      final fd = openFd(l, months: 3, renewal: FdRenewal.renewWithInterest);
      l.runDue(addMonths(fd.startDate, 12).add(const Duration(days: 1)));
      final d = l.fixedDeposits.firstWhere((x) => x.id == fd.id);
      expect(d.renewals, 4);
      expect(d.maturityDate.isAfter(addMonths(fd.startDate, 12)), isTrue);
    });

    test('the demo customer has one existing deposit, running; a new customer has none', () {
      final demo = MockLedger();
      final d = demo.fixedDeposits.single;
      expect(d.principal, 1250000);
      expect(d.active, isTrue);
      expect(d.daysLeftAt(DateTime.now()), greaterThan(200));
      expect(d.progressAt(DateTime.now()), inExclusiveRange(0.2, 0.5));
      expect(MockLedger.fresh(openingDeposit: 5000, accountLast4: '1234').fixedDeposits, isEmpty);
    });
  });

  group('screens', () {
    Future<ProviderContainer> signedIn(WidgetTester tester) async {
      useScreen(tester, const Size(390, 2600));
      await openLogin(tester, TestEnv());
      await signInAsDemo(tester);
      return ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    }

    Future<void> go(WidgetTester tester, ProviderContainer c, String route) async {
      c.read(routerProvider).push(route);
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
    }

    testWidgets('Open: pick "more than 12 months", get told what is wrong, then open a 36-month deposit that renews with interest', (tester) async {
      final c = await signedIn(tester);
      final ledger = c.read(ledgerProvider);
      final sav = bal(ledger, 'a-sav');
      await go(tester, c, '/fixed-deposits/open');

      expect(find.text('3 months'), findsOneWidget);
      expect(find.text('6 months'), findsOneWidget);
      expect(find.text('12 months'), findsOneWidget);
      expect(find.text('More than 12 months'), findsOneWidget);
      expect(find.byKey(const ValueKey('fdMonths')), findsNothing);

      await tester.tap(find.text('More than 12 months'));
      await advance(tester, 400);
      await tester.enterText(find.byKey(const ValueKey('fdMonths')), '34');
      await advance(tester, 300);
      expect(find.textContaining('Use whole years in months'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('fdMonths')), '12');
      await advance(tester, 300);
      expect(find.textContaining('pick one of the choices above'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('fdMonths')), '36');
      await advance(tester, 300);
      expect(find.text('10.25% a year'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('fdAmount')), '5000');
      await tester.ensureVisible(find.text('Open fixed deposit'));
      await tester.tap(find.text('Open fixed deposit'));
      await advance(tester, 300);
      expect(find.text('The minimum is LKR 10,000.'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('fdAmount')), '200000');
      await advance(tester, 300);
      expect(find.text('LKR 61,500.00'), findsOneWidget, reason: '200,000 at 10.25% for 3 years');
      expect(find.text('LKR 261,500.00'), findsOneWidget);
      expect(find.text('Renew with interest'), findsOneWidget);

      await tester.ensureVisible(find.text('Open fixed deposit'));
      await tester.tap(find.text('Open fixed deposit'));
      await advance(tester, 100);
      await advance(tester, 700);
      await tapPin(tester, _pin);
      await advance(tester, 300);
      await tapPin(tester, _pin);
      await advance(tester, 500);
      await advance(tester, 700);
      await advance(tester, 1200);
      await advance(tester, 900);

      expect(find.text('Fixed deposit opened'), findsOneWidget);
      final fd = ledger.fixedDeposits.last;
      expect(fd.termMonths, 36);
      expect(fd.renewal, FdRenewal.renewWithInterest);
      expect(bal(ledger, 'a-sav'), sav - 200000);

      await tester.tap(find.text('View my fixed deposits'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.text('36 months (3 years) · 10.25%'), findsOneWidget);
      expect(find.text('12 months · 9.5%'), findsOneWidget, reason: 'the demo deposit is listed too');
      await advance(tester, 4500);
    });

    testWidgets('Open: a quick term with the payout choice, and a short-balance amount is caught before the PIN', (tester) async {
      final c = await signedIn(tester);
      await go(tester, c, '/fixed-deposits/open');
      await tester.enterText(find.byKey(const ValueKey('fdAmount')), '99999999');
      await tester.ensureVisible(find.text('Open fixed deposit'));
      await tester.tap(find.text('Open fixed deposit'));
      await advance(tester, 300);
      expect(find.textContaining('more than is in'), findsOneWidget);
      expect(find.text('Create a transaction PIN'), findsNothing);

      await tester.tap(find.text('6 months'));
      await advance(tester, 300);
      expect(find.text('8.5% a year'), findsOneWidget);
      await tester.tap(find.text('Renew without interest'));
      await advance(tester, 200);
      await tester.enterText(find.byKey(const ValueKey('fdAmount')), '50000');
      await advance(tester, 300);
      expect(find.text('LKR 2,125.00'), findsOneWidget, reason: '50,000 at 8.5% for 6 months');
    });

    testWidgets('Open: exactly two maturity options are offered, and nothing about paying everything out', (tester) async {
      final c = await signedIn(tester);
      await go(tester, c, '/fixed-deposits/open');
      expect(find.text('When it matures'), findsOneWidget);
      expect(find.text('Renew with interest'), findsOneWidget);
      expect(find.text('Renew without interest'), findsOneWidget);
      expect(find.byType(RadioListTile<FdRenewal>), findsNWidgets(2));
      expect(find.textContaining('Don’t renew'), findsNothing);
      expect(find.textContaining('pay everything'), findsNothing);
      expect(find.textContaining('can’t be changed after you open the deposit'), findsOneWidget);
      expect(find.textContaining('You can change this'), findsNothing);
      // "With interest" is ticked unless you choose otherwise.
      expect(tester.widget<RadioGroup<FdRenewal>>(find.byType(RadioGroup<FdRenewal>)).groupValue, FdRenewal.renewWithInterest);
      expect(find.textContaining('interest earns interest'), findsOneWidget);
      expect(find.textContaining('The interest is paid to your account'), findsOneWidget);
    });

    testWidgets('Open with "Renew without interest": that is what is saved, and shown on the success page and the list', (tester) async {
      final c = await signedIn(tester);
      final ledger = c.read(ledgerProvider);
      await go(tester, c, '/fixed-deposits/open');
      await tester.enterText(find.byKey(const ValueKey('fdAmount')), '40000');
      await tester.tap(find.text('Renew without interest'));
      await advance(tester, 200);
      await tester.ensureVisible(find.text('Open fixed deposit'));
      await tester.tap(find.text('Open fixed deposit'));
      await advance(tester, 100);
      await advance(tester, 700);
      await tapPin(tester, _pin);
      await advance(tester, 300);
      await tapPin(tester, _pin);
      await advance(tester, 500);
      await advance(tester, 700);
      await advance(tester, 1200);
      await advance(tester, 900);

      expect(ledger.fixedDeposits.last.renewal, FdRenewal.renewPrincipalOnly);
      expect(find.text('Fixed deposit opened'), findsOneWidget);
      expect(find.text('Renew without interest'), findsOneWidget, reason: 'the "Then" row on the confirmation');
      await tester.tap(find.text('View my fixed deposits'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.text('Renew without interest'), findsOneWidget, reason: 'the new deposit’s "At maturity" row');
      expect(find.text('Renew with interest'), findsOneWidget, reason: 'the demo deposit’s');
      await advance(tester, 4500);
    });

    testWidgets('Nothing on the list lets you edit a deposit, and a branch-arranged pay-out deposit still displays', (tester) async {
      final c = await signedIn(tester);
      final ledger = c.read(ledgerProvider);
      ledger.openFixedDeposit(fromAccountId: 'a-sav', amount: 30000, termMonths: 6, renewal: FdRenewal.payOut);
      await go(tester, c, '/fixed-deposits');
      expect(find.text('Paid out at maturity'), findsOneWidget, reason: 'shown as it was arranged');
      expect(find.textContaining('Change'), findsNothing);
      expect(find.byType(RadioListTile<FdRenewal>), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('List: the demo deposit with its progress, rate, maturity and what happens at maturity (read-only)', (tester) async {
      final c = await signedIn(tester);
      await go(tester, c, '/fixed-deposits');
      expect(find.text('Locked away'), findsOneWidget);
      expect(find.text('12 months · 9.5%'), findsOneWidget);
      expect(find.text('LKR 1,250,000.00'), findsWidgets);
      expect(find.text('Interest at maturity'), findsOneWidget);
      expect(find.text('LKR 118,750.00'), findsOneWidget, reason: '1,250,000 at 9.5% for a year');
      expect(find.text('Renew with interest'), findsOneWidget);
      expect(find.textContaining('days left'), findsOneWidget);

      expect(find.textContaining('Change'), findsNothing, reason: 'a deposit can’t be changed once it is open');
      await advance(tester, 300);
    });

    testWidgets('List: a matured deposit moves to "Matured" with what was paid', (tester) async {
      final c = await signedIn(tester);
      final ledger = c.read(ledgerProvider);
      final fd = ledger.openFixedDeposit(fromAccountId: 'a-sav', amount: 20000, termMonths: 3, renewal: FdRenewal.payOut);
      ledger.runDue(fd.maturityDate.add(const Duration(days: 1)));
      await go(tester, c, '/fixed-deposits');
      expect(find.text('Matured'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget, reason: 'the demo deposit is still running');
      expect(find.text('Paid out'), findsOneWidget);
      expect(find.text('LKR 20,375.00'), findsOneWidget, reason: '20,000 plus 375 interest at 7.5% for 3 months');
      expect(find.textContaining('Change'), findsNothing);
    });

    testWidgets('A fixed deposit’s account page links to the deposits screen and explains it cannot send money', (tester) async {
      final c = await signedIn(tester);
      await go(tester, c, '/accounts/a-fd');
      expect(find.text('Fixed deposit details'), findsOneWidget);
      expect(find.text('Send'), findsNothing);
      expect(find.textContaining('can’t be sent from a fixed deposit'), findsOneWidget);
    });

    testWidgets('Payments has a Fixed deposits entry, and a new customer sees an empty list', (tester) async {
      useScreen(tester, const Size(390, 2600));
      final env = TestEnv();
      await openLogin(tester, env);
      await tester.runAsync(() => env.repo.register(fullName: 'Nimal Fernando', username: 'nimal.f', password: 'Nimal@12345', initialDeposit: 25000, profile: const {'email': 'n@example.com'}));
      final c = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      final user = (await tester.runAsync(() => env.repo.signIn('nimal.f', 'Nimal@12345')))!;
      c.read(mockBankProvider).openAccount(user, deposit: 25000);
      await signIn(tester, user: 'nimal.f', password: 'Nimal@12345');
      await advance(tester, 1500);

      c.read(routerProvider).go('/payments');
      await advance(tester, 100);
      await advance(tester, 900);
      await tester.ensureVisible(find.text('Fixed deposits'));
      await tester.tap(find.text('Fixed deposits'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.text('No fixed deposits yet'), findsOneWidget);
      expect(find.text('Open a fixed deposit'), findsOneWidget);
    });
  });
}
