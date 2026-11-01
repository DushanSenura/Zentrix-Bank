import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

const _pin = '246813';

Future<TestEnv> dashboard(WidgetTester tester, {Size size = const Size(390, 1600)}) async {
  useScreen(tester, size);
  final env = TestEnv();
  await openLogin(tester, env);
  await signInAsDemo(tester);
  return env;
}

Future<void> go(WidgetTester tester, String label, {bool last = false}) async {
  final f = last ? find.text(label).last : find.text(label).first;
  await tester.ensureVisible(f);
  await tester.tap(f);
  await advance(tester, 100);
  await advance(tester, 700);
}

Future<void> openFromPayments(WidgetTester tester, String service) async {
  await go(tester, 'Payments');
  await go(tester, service);
  await advance(tester, 800); // data
}

void main() {
  setUpAll(loadAppFont);

  testWidgets('Transactions: grouped history, search, filters, empty state', (tester) async {
    await dashboard(tester);
    await openFromPayments(tester, 'Transactions');
    expect(find.text('Transactions'), findsWidgets);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Dialog Axiata'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'uber');
    await advance(tester, 300);
    expect(find.text('Uber'), findsWidgets);
    expect(find.text('Keells Supermarket'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await advance(tester, 300);
    expect(find.text('No matching transactions'), findsOneWidget);
    await tester.tap(find.text('Clear all'));
    await advance(tester, 300);
    expect(find.text('Dialog Axiata'), findsOneWidget);

    // Income only, via the filter sheet.
    await tester.tap(find.byTooltip('Filters'));
    await advance(tester, 100);
    await advance(tester, 700);
    await tester.tap(find.text('Income').last);
    await advance(tester, 200);
    await tester.ensureVisible(find.text('Apply filters'));
    await tester.tap(find.text('Apply filters'));
    await advance(tester, 100);
    await advance(tester, 700);
    expect(find.text('Salary — NovaCore Techs'), findsWidgets);
    expect(find.text('Dialog Axiata'), findsNothing);
    expect(find.text('1 filter applied'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await advance(tester, 300);
    expect(find.text('Dialog Axiata'), findsOneWidget);
  });

  testWidgets('Transaction details: facts, receipt actions, repeat guard, report', (tester) async {
    final env = await dashboard(tester);
    await tester.ensureVisible(find.text('Uber'));
    await tester.tap(find.text('Uber'));
    await advance(tester, 100);
    await advance(tester, 700);
    expect(find.text('Transaction ID'), findsOneWidget);
    expect(find.text('Debit card •••• 4821'), findsOneWidget);
    expect(find.text('Savings Account •••• 3021'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);

    await tester.tap(find.text('Receipt'));
    await advance(tester, 200);
    expect(env.receipts.saved, hasLength(1));
    await tester.tap(find.text('Share'));
    await advance(tester, 100);
    expect(env.receipts.shared, hasLength(1));

    await tester.tap(find.text('Repeat'));
    await advance(tester, 100);
    await advance(tester, 700); // the earlier toast leaves first
    expect(find.text('Only payments made in this app can be repeated.'), findsOneWidget);

    await tester.tap(find.text('Report'));
    await advance(tester, 100);
    await advance(tester, 900);
    expect(find.text('What went wrong?'), findsOneWidget, reason: 'Report now opens the real dispute form');
    await advance(tester, 3500);
  });

  testWidgets('Income details offer no payment actions', (tester) async {
    await dashboard(tester);
    await tester.ensureVisible(find.text('Salary — NovaCore Techs'));
    await tester.tap(find.text('Salary — NovaCore Techs'));
    await advance(tester, 100);
    await advance(tester, 700);
    expect(find.text('Bank credit'), findsOneWidget);
    expect(find.text('Repeat'), findsNothing);
    expect(find.text('Report'), findsOneWidget);
  });

  testWidgets('Analytics: totals, charts, category breakdown, insights, period switch', (tester) async {
    await dashboard(tester);
    await go(tester, 'Analytics');
    await advance(tester, 800);
    await advance(tester, 1200); // chart reveal
    expect(find.text('Income'), findsWidgets);
    expect(find.text('Spending by category'), findsOneWidget);
    await tester.ensureVisible(find.text('Income vs expenses'));
    expect(find.text('Income vs expenses'), findsOneWidget);
    expect(find.text('Net each month'), findsNothing); // one month → no line

    await tester.tap(find.text('6 months'));
    await advance(tester, 100);
    await advance(tester, 900);
    await tester.ensureVisible(find.text('Net each month'));
    expect(find.text('Net each month'), findsOneWidget);
    expect(find.textContaining('not financial advice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Balance privacy hides analytics amounts', (tester) async {
    await dashboard(tester);
    await tester.tap(find.byTooltip('Hide balances'));
    await advance(tester, 100);
    await advance(tester, 600);
    await go(tester, 'Analytics');
    await advance(tester, 800);
    expect(find.text('LKR ••••••'), findsWidgets);
  });

  testWidgets('Savings: progress, add money with PIN, create a goal, guard rails', (tester) async {
    await dashboard(tester);
    await openFromPayments(tester, 'Savings goals');
    expect(find.text('New Car'), findsOneWidget);
    expect(find.text('Holiday'), findsOneWidget);
    await advance(tester, 1000);
    expect(find.text('34%'), findsOneWidget); // 850,000 / 2,500,000
    expect(find.text('LKR 120,000.00 / LKR 300,000.00'), findsOneWidget);

    // Withdrawing more than saved is blocked.
    await tester.tap(find.text('Withdraw').at(1));
    await advance(tester, 100);
    await advance(tester, 700);
    await tester.enterText(find.byKey(const ValueKey('goalAmount')), '999999');
    await tester.tap(find.text('Withdraw').last);
    await advance(tester, 300);
    expect(find.text('Amount exceeds your available balance.'), findsOneWidget);
    await tester.tapAt(const Offset(195, 20)); // tap the barrier to dismiss
    await advance(tester, 100);
    await advance(tester, 700);
    expect(find.text('Withdraw from Holiday'), findsNothing);

    // Deposit, authorised with a freshly created PIN.
    await tester.tap(find.text('Add money').at(1));
    await advance(tester, 100);
    await advance(tester, 700);
    await tester.enterText(find.byKey(const ValueKey('goalAmount')), '5000');
    await tester.tap(find.text('Add money').last);
    await advance(tester, 100);
    await advance(tester, 700);
    expect(find.text('Create a transaction PIN'), findsOneWidget);
    await tapPin(tester, _pin);
    await advance(tester, 300);
    await tapPin(tester, _pin);
    await advance(tester, 600);
    await advance(tester, 700);
    await advance(tester, 1200);
    await advance(tester, 800);
    expect(find.text('Added LKR 5,000.00 to Holiday.'), findsOneWidget);
    await advance(tester, 4500);
    expect(find.text('LKR 125,000.00 / LKR 300,000.00'), findsOneWidget);

    // New goal.
    await tester.tap(find.byTooltip('New goal'));
    await advance(tester, 100);
    await advance(tester, 700);
    await tester.tap(find.text('Create goal'));
    await advance(tester, 300);
    expect(find.text('Goal name is required.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('goalName')), 'Laptop');
    await tester.enterText(find.byKey(const ValueKey('goalTarget')), '150000');
    await tester.tap(find.byKey(const ValueKey('goalDate')));
    await advance(tester, 100);
    await advance(tester, 500);
    await tester.tap(find.text('OK'));
    await advance(tester, 100);
    await advance(tester, 400);
    await tester.tap(find.text('Create goal'));
    await advance(tester, 100);
    await advance(tester, 600);
    await advance(tester, 800);
    expect(find.text('Laptop'), findsOneWidget);
  });

  testWidgets('Loans: summary, payment history, calculator with estimate disclaimer', (tester) async {
    await dashboard(tester);
    await openFromPayments(tester, 'Loans');
    expect(find.text('Vehicle loan'), findsOneWidget);
    expect(find.text('Personal loan'), findsOneWidget);
    expect(find.text('36 of 60 months'), findsOneWidget);

    await tester.tap(find.text('Payment history').first);
    await advance(tester, 100);
    await advance(tester, 500);
    expect(find.text('Hide payment history'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);

    await go(tester, 'Loan calculator');
    expect(find.text('Estimated monthly payment'), findsOneWidget);
    expect(find.textContaining('Estimate only'), findsOneWidget);
    expect(find.text('15.0% p.a.'), findsOneWidget);
    await go(tester, 'Home loan');
    expect(find.text('11.0% p.a.'), findsOneWidget);
  });

  testWidgets('Statements: per-account month summary, CSV and PDF share/save', (tester) async {
    final env = await dashboard(tester);
    await openFromPayments(tester, 'Statements');
    expect(find.text('Money in'), findsOneWidget);
    expect(find.text('Transactions'), findsWidgets);

    await tester.tap(find.text('Share CSV'));
    await advance(tester, 200);
    expect(env.statements.shared, hasLength(1));
    final (name, csv) = env.statements.shared.single;
    expect(name, matches(RegExp(r'^statement_3021_\d{4}-\d{2}\.csv$')));
    expect(csv.split('\r\n').first, startsWith('Date,Time,Description'));
    expect(csv, contains('Starbucks'));
    expect(csv, isNot(contains('Netflix'))); // Netflix is on the Current Account

    await tester.tap(find.byTooltip('Save CSV'));
    await advance(tester, 200);
    expect(env.statements.saved, hasLength(1));
    expect(find.textContaining('Saved statement_3021_'), findsOneWidget);

    await tester.tap(find.byTooltip('PDF statement'));
    await advance(tester, 100);
    await advance(tester, 500); // the menu animates in and ignores taps until it settles
    await tester.tap(find.text('Share PDF'));
    await advance(tester, 500);
    await advance(tester, 300);
    expect(env.statements.pdfShared, hasLength(1));
    expect(env.statements.pdfShared.single.$1, matches(RegExp(r'^statement_3021_\d{4}-\d{2}\.pdf$')));
    expect(env.statements.pdfShared.single.$2, greaterThan(1000));

    await tester.tap(find.byTooltip('PDF statement'));
    await advance(tester, 100);
    await advance(tester, 500); // the menu animates in and ignores taps until it settles
    await tester.tap(find.text('Save PDF'));
    await advance(tester, 500);
    await advance(tester, 300);
    expect(env.statements.pdfSaved, hasLength(1));
    await advance(tester, 4000);
  });

  testWidgets('New screens lay out without overflow on a small phone with large text', (tester) async {
    useScreen(tester, const Size(320, 640));
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final env = TestEnv();
    await openLogin(tester, env);
    await signInAsDemo(tester);

    await go(tester, 'Analytics');
    await advance(tester, 2000);
    expect(tester.takeException(), isNull, reason: 'Analytics');

    await go(tester, 'Payments');
    for (final service in ['Transactions', 'Savings goals', 'Loans', 'Statements']) {
      await go(tester, service);
      await advance(tester, 1500);
      expect(tester.takeException(), isNull, reason: service);
      await tester.tap(find.byTooltip('Back'));
      await advance(tester, 100);
      await advance(tester, 700);
    }
  });
}
