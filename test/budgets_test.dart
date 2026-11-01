import 'package:bank_app/app/providers.dart';
import 'package:bank_app/app/router.dart';
import 'package:bank_app/features/analytics/domain/budgets.dart';
import 'package:bank_app/features/authentication/data/mock_auth_repository.dart';
import 'package:bank_app/features/payments/presentation/payment_submission.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:bank_app/shared/models/payment_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

final _now = DateTime(2026, 11, 20, 12);

Transaction spend(String id, TxCategory c, double amount, DateTime date, {TxStatus status = TxStatus.completed, bool internal = false}) =>
    Transaction(id: id, merchant: id, category: c, amount: -amount, date: date, status: status, internal: internal);

void main() {
  setUpAll(loadAppFont);

  group('budgetProgress', () {
    final txs = [
      spend('a', TxCategory.food, 3000, DateTime(2026, 11, 2)),
      spend('b', TxCategory.food, 2500, DateTime(2026, 11, 19)),
      spend('old', TxCategory.food, 9999, DateTime(2026, 10, 30)),
      spend('pending', TxCategory.food, 5000, DateTime(2026, 11, 18), status: TxStatus.pending),
      spend('own', TxCategory.food, 7000, DateTime(2026, 11, 10), internal: true),
      spend('failed', TxCategory.food, 4000, DateTime(2026, 11, 11), status: TxStatus.failed),
      spend('future', TxCategory.food, 6000, DateTime(2026, 11, 28)),
      spend('bus', TxCategory.transport, 800, DateTime(2026, 11, 5)),
      spend('send', TxCategory.transfer, 20000, DateTime(2026, 11, 6)), // transfers fold into "other"
    ];

    test('counts only this month’s settled spending, not own-account moves, pending, failed or future items', () {
      final p = budgetProgress(const [Budget(category: TxCategory.food, monthlyLimit: 10000)], txs, _now).single;
      expect(p.spent, 5500);
      expect(p.remaining, 4500);
      expect(p.fraction, 0.55);
      expect(p.state, BudgetState.onTrack);
    });

    test('states switch at 80% and 100%', () {
      BudgetState at(double spent) => BudgetProgress(budget: const Budget(category: TxCategory.food, monthlyLimit: 1000), spent: spent).state;
      expect(at(0), BudgetState.onTrack);
      expect(at(799), BudgetState.onTrack);
      expect(at(800), BudgetState.nearLimit);
      expect(at(999.99), BudgetState.nearLimit);
      expect(at(1000), BudgetState.over);
      expect(at(5000), BudgetState.over);
    });

    test('transfers to other people count under "other"', () {
      final p = budgetProgress(const [Budget(category: TxCategory.other, monthlyLimit: 30000)], txs, _now).single;
      expect(p.spent, 20000);
    });

    test('a category with no spending is zero, and order follows the budgets given', () {
      final p = budgetProgress(
        const [Budget(category: TxCategory.health, monthlyLimit: 5000), Budget(category: TxCategory.food, monthlyLimit: 5000)],
        txs,
        _now,
      );
      expect(p.map((x) => x.budget.category), [TxCategory.health, TxCategory.food]);
      expect(p.first.spent, 0);
    });
  });

  group('suggestedBudget', () {
    test('averages the months that had spending, rounded to the nearest 1,000', () {
      final txs = [
        spend('sep', TxCategory.food, 12000, DateTime(2026, 9, 10)),
        spend('oct1', TxCategory.food, 9000, DateTime(2026, 10, 3)),
        spend('oct2', TxCategory.food, 2000, DateTime(2026, 10, 20)),
        // July is outside the three full months before November (Aug–Oct); November is the current month.
        spend('jul', TxCategory.food, 99000, DateTime(2026, 7, 10)),
        spend('nov', TxCategory.food, 50000, DateTime(2026, 11, 3)),
      ];
      expect(suggestedBudget(txs, _now, TxCategory.food), 12000);
    });

    test('no history means no suggestion', () {
      expect(suggestedBudget([spend('x', TxCategory.food, 100, DateTime(2026, 11, 3))], _now, TxCategory.food), isNull);
      expect(suggestedBudget(const [], _now, TxCategory.health), isNull);
    });

    test('never suggests less than 1,000', () {
      expect(suggestedBudget([spend('tiny', TxCategory.food, 40, DateTime(2026, 10, 3))], _now, TxCategory.food), 1000);
    });
  });

  group('budgetAlerts', () {
    BudgetProgress p(double spent, {TxCategory c = TxCategory.food}) => BudgetProgress(budget: Budget(category: c, monthlyLimit: 1000), spent: spent);

    test('raised once when a threshold is first crossed', () {
      expect(budgetAlerts([p(500)], [p(850)]).single.kind, BudgetAlertKind.nearLimit);
      expect(budgetAlerts([p(850)], [p(1100)]).single.kind, BudgetAlertKind.over);
      expect(budgetAlerts([p(500)], [p(1200)]).single.kind, BudgetAlertKind.over, reason: 'jumping straight past 100% is one "over" alert');
    });

    test('not repeated while it stays in the same state, or when spending is unchanged', () {
      expect(budgetAlerts([p(850)], [p(900)]), isEmpty);
      expect(budgetAlerts([p(1100)], [p(1300)]), isEmpty);
      expect(budgetAlerts([p(100)], [p(100)]), isEmpty);
    });

    test('a budget created already over its limit is reported as over', () {
      expect(budgetAlerts(const [], [p(1500)]).single.kind, BudgetAlertKind.over);
    });
  });

  group('MockBudgetRepository', () {
    test('saves, replaces and removes per category, per customer', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(authProvider.notifier).start(MockAuthRepository.demoUser);
      final repo = c.read(budgetRepositoryProvider);
      expect(await repo.budgets(), isEmpty);
      await repo.save(const Budget(category: TxCategory.food, monthlyLimit: 20000));
      await repo.save(const Budget(category: TxCategory.food, monthlyLimit: 25000));
      await repo.save(const Budget(category: TxCategory.bills, monthlyLimit: 40000));
      expect((await repo.budgets()).map((b) => (b.category, b.monthlyLimit)), [(TxCategory.food, 25000.0), (TxCategory.bills, 40000.0)]);
      await repo.remove(TxCategory.food);
      expect((await repo.budgets()).single.category, TxCategory.bills);
    });

    test('rejects limits that are not positive, and categories that cannot have a budget', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final repo = c.read(budgetRepositoryProvider);
      for (final bad in [0.0, -5.0, double.nan, double.infinity]) {
        await expectLater(repo.save(Budget(category: TxCategory.food, monthlyLimit: bad)), throwsArgumentError, reason: '$bad');
      }
      await expectLater(repo.save(const Budget(category: TxCategory.income, monthlyLimit: 100)), throwsArgumentError);
      expect(await repo.budgets(), isEmpty);
    });
  });

  test('a payment that crosses a budget threshold raises one notification, and only once', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(authProvider.notifier).start(MockAuthRepository.demoUser);
    final ledger = c.read(ledgerProvider);
    final now = DateTime.now();
    // A category with nothing spent yet this month, so the thresholds are easy to reason about.
    final spent = budgetProgress([for (final cat in budgetCategories) Budget(category: cat, monthlyLimit: 1)], ledger.transactions, now);
    final category = spent.firstWhere((p) => p.spent == 0).budget.category;
    await c.read(budgetRepositoryProvider).save(Budget(category: category, monthlyLimit: 10000));
    c.listen(paymentSubmissionProvider, (_, _) {});

    Future<void> pay(double amount) async {
      await c.read(paymentSubmissionProvider.notifier).submit(
        PaymentDraft(kind: PaymentKind.bill, fromAccountId: 'a-sav', payee: 'Test payee', payeeDetail: 'x', amount: amount, category: category),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1800)); // the alert is computed after the receipt
    }

    Future<List<String>> titles() async => [
      for (final n in await c.read(notificationsProvider.future))
        if (n.title.contains('budget')) n.title,
    ];

    await pay(2000); // 20%: nothing to say
    expect(await titles(), isEmpty);
    await pay(6500); // 85%
    expect(await titles(), hasLength(1));
    expect((await titles()).single, startsWith('Nearly at your'));
    await pay(500); // 90%: still "nearly", already told
    expect(await titles(), hasLength(1));
    await pay(1500); // 105%
    expect(await titles(), hasLength(2));
    expect((await titles()).first, startsWith('Over your'));
    await pay(100); // still over: no repeat
    expect(await titles(), hasLength(2));
  });

  group('screens', () {
    testWidgets('Budgets: empty state, add one with a suggestion, see progress, edit and remove it', (tester) async {
      useScreen(tester, const Size(390, 2000));
      await openLogin(tester, TestEnv());
      await signInAsDemo(tester);
      final c = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      c.read(routerProvider).push('/budgets');
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.text('No budgets yet'), findsOneWidget);

      await tester.tap(find.text('Add a budget'));
      await advance(tester, 100);
      await advance(tester, 700);
      await tester.tap(find.text('Food'));
      await advance(tester, 300);
      // Starbucks today is always inside the current month, so a 1,000 limit is certainly exceeded.
      await tester.enterText(find.byKey(const ValueKey('budgetLimit')), '0');
      await tester.tap(find.text('Save'));
      await advance(tester, 300);
      expect(find.text('Enter a valid amount.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('budgetLimit')), '1000');
      await tester.tap(find.text('Save'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);

      expect(find.text('No budgets yet'), findsNothing);
      expect(find.textContaining('Over by'), findsOneWidget);
      expect(find.text('This month'), findsOneWidget);

      await tester.tap(find.text('Food').first);
      await advance(tester, 100);
      await advance(tester, 700);
      expect(find.text('Food budget'), findsOneWidget);
      await tester.tap(find.text('Remove budget'));
      await advance(tester, 100);
      await advance(tester, 500);
      await tester.tap(find.text('Remove'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.text('No budgets yet'), findsOneWidget);
      await advance(tester, 4000);
    });
  });
}
