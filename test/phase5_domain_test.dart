import 'package:bank_app/features/analytics/domain/analytics.dart';
import 'package:bank_app/features/loans/domain/loan_math.dart';
import 'package:bank_app/features/payments/data/mock_ledger.dart';
import 'package:bank_app/features/transactions/domain/transaction_filter.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:bank_app/shared/models/payment_models.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';

Transaction tx(String merchant, double amount, DateTime date, {TxCategory c = TxCategory.food, bool internal = false, TxStatus status = TxStatus.completed, String account = 'a-sav'}) =>
    Transaction(id: merchant, merchant: merchant, category: c, amount: amount, date: date, internal: internal, status: status, accountId: account);

void main() {
  final now = DateTime(2026, 11, 15, 12);

  group('TransactionFilter', () {
    final list = [
      tx('Keells', -8000, DateTime(2026, 11, 14), c: TxCategory.food),
      tx('Salary', 185000, DateTime(2026, 11, 1), c: TxCategory.income),
      tx('Uber', -2000, DateTime(2026, 10, 20), c: TxCategory.transport),
      tx('Netflix', -2490, DateTime(2026, 10, 3), c: TxCategory.entertainment, account: 'a-cur'),
    ];

    test('search matches merchant text, case-insensitively', () {
      expect(list.where(const TransactionFilter(query: 'kEE').matches).map((t) => t.merchant), ['Keells']);
    });

    test('category, direction, amount and account combine', () {
      const base = TransactionFilter();
      expect(list.where(base.withFilters(categories: {TxCategory.food, TxCategory.transport}).matches), hasLength(2));
      expect(list.where(base.withFilters(direction: Direction.income).matches).single.merchant, 'Salary');
      expect(list.where(base.withFilters(direction: Direction.expense, minAmount: 2200).matches).map((t) => t.merchant), ['Keells', 'Netflix']);
      expect(list.where(base.withFilters(maxAmount: 2500).matches).map((t) => t.merchant), ['Uber', 'Netflix']);
      expect(list.where(base.withFilters(accountId: 'a-cur').matches).single.merchant, 'Netflix');
    });

    test('date range is inclusive of both end days', () {
      final f = const TransactionFilter().withFilters(range: DateTimeRange(start: DateTime(2026, 10, 3), end: DateTime(2026, 10, 20)));
      expect(list.where(f.matches).map((t) => t.merchant), ['Uber', 'Netflix']);
    });

    test('filterCount ignores search text', () {
      const f = TransactionFilter(query: 'x');
      expect(f.filterCount, 0);
      expect(f.withFilters(direction: Direction.income, minAmount: 1).filterCount, 2);
    });
  });

  test('grouping: Upcoming, Today, Yesterday, This week, Earlier — in order, empty ones omitted', () {
    final groups = groupTransactions([
      tx('future', -1, DateTime(2026, 11, 20)),
      tx('today', -1, DateTime(2026, 11, 15, 8)),
      tx('yday', -1, DateTime(2026, 11, 14, 23)),
      tx('week', -1, DateTime(2026, 11, 10)),
      tx('old', -1, DateTime(2026, 10, 1)),
    ], now);
    expect(groups.map((g) => g.title), ['Upcoming', 'Today', 'Yesterday', 'This week', 'Earlier']);
    expect(groupTransactions([tx('a', -1, DateTime(2026, 11, 15))], now).map((g) => g.title), ['Today']);
  });

  group('Analytics', () {
    final list = [
      tx('Salary', 100000, DateTime(2026, 11, 1), c: TxCategory.income),
      tx('Food now', -10000, DateTime(2026, 11, 10)),
      tx('Food last month, same period', -20000, DateTime(2026, 10, 10)),
      tx('Food last month, later', -99999, DateTime(2026, 10, 28)),
      tx('Bills now', -6000, DateTime(2026, 11, 5), c: TxCategory.bills),
      tx('Bills last', -5000, DateTime(2026, 10, 5), c: TxCategory.bills),
      tx('Own move', -50000, DateTime(2026, 11, 6), c: TxCategory.transfer, internal: true),
      tx('Pending', -777, DateTime(2026, 11, 7), status: TxStatus.pending),
      tx('Future', -888, DateTime(2026, 11, 30)),
      tx('To Kamala', -3000, DateTime(2026, 11, 8), c: TxCategory.transfer),
    ];

    test('monthly totals skip internal, pending and future items', () {
      final nov = monthlyTotals(list, now, months: 2).last;
      expect(nov.income, 100000);
      expect(nov.expense, 10000 + 6000 + 3000);
      expect(nov.net, 100000 - 19000);
      expect(monthlyTotals(list, now, months: 3).map((m) => m.month.month), [9, 10, 11]);
    });

    test('spending folds transfers into Other and excludes income', () {
      final s = spendingByCategory(list, now, from: DateTime(2026, 11), to: now);
      expect(s[TxCategory.food], 10000);
      expect(s[TxCategory.bills], 6000);
      expect(s[TxCategory.other], 3000);
      expect(s.containsKey(TxCategory.income), isFalse);
    });

    test('insights compare month-to-date with the same days last month', () {
      final insights = buildInsights(list, now);
      // Food: 10,000 vs 20,000 over the same days → 50% less (the later 99,999 must not count).
      expect(insights.first.text, contains('50% less on food'));
      expect(insights.first.good, isTrue);
      // Bills: 6,000 vs 5,000 → up 20%.
      expect(insights.any((i) => i.text.contains('bills is up 20%') && !i.good), isTrue);
      expect(insights, hasLength(3));
      expect(insights.last.text, contains('kept 81%')); // (100,000 − 19,000) / 100,000
    });

    test('no insight when there is nothing to compare', () {
      expect(buildInsights([tx('Salary', 1, DateTime(2026, 11, 1), c: TxCategory.income)], now).single.text, contains('kept'));
      expect(buildInsights(const [], now), isEmpty);
    });
  });

  group('Loan maths', () {
    test('known instalment: 1,000,000 at 12% over 12 months ≈ 88,848.79', () {
      expect(monthlyInstallment(1000000, 12, 12), closeTo(88848.79, 0.01));
    });

    test('zero interest divides evenly; bad input yields zero', () {
      expect(monthlyInstallment(120000, 0, 12), 10000);
      expect(monthlyInstallment(0, 10, 12), 0);
      expect(monthlyInstallment(1000, 10, 0), 0);
    });

    test('estimate totals are consistent', () {
      final e = estimateLoan(500000, 14, 36);
      expect(e.totalPayable, closeTo(e.monthly * 36, 0.001));
      expect(e.totalInterest, closeTo(e.totalPayable - 500000, 0.001));
      expect(e.totalInterest, greaterThan(0));
    });
  });

  group('Ledger additions', () {
    test('seed has several months of history and a balanced mix', () {
      final l = MockLedger(now: now);
      final months = monthlyTotals(l.transactions, now);
      expect(months.where((m) => m.expense > 0).length, greaterThanOrEqualTo(5));
      expect(l.transactions.length, greaterThan(40));
    });

    test('own-account transfer writes a debit and a credit, both internal', () {
      final l = MockLedger();
      l.post(PaymentDraft(kind: PaymentKind.transfer, fromAccountId: 'a-sav', payee: 'Current Account', payeeDetail: 'x', toAccountId: 'a-cur', amount: 1000));
      final top = l.transactions.take(2).toList();
      expect(top.every((t) => t.internal), isTrue);
      expect(top.map((t) => t.amount).toSet(), {-1000.0, 1000.0});
      expect(top.map((t) => t.accountId).toSet(), {'a-sav', 'a-cur'});
    });

    test('paying creates a repeatable draft keyed by transaction id', () {
      final l = MockLedger();
      final r = l.post(PaymentDraft(kind: PaymentKind.bill, fromAccountId: 'a-sav', payee: 'CEB', payeeDetail: 'Acct 1', amount: 500, category: TxCategory.bills));
      expect(l.repeatDrafts[r.id]!.payee, 'CEB');
    });

    test('savings goals: deposit, withdraw and guard rails', () {
      final l = MockLedger();
      final saved = l.goals.firstWhere((g) => g.id == 'g-trip').saved;
      final bal = l.accounts.firstWhere((a) => a.id == 'a-sav').balance;
      l.moveGoal('g-trip', 'a-sav', 5000);
      expect(l.goals.firstWhere((g) => g.id == 'g-trip').saved, saved + 5000);
      expect(l.accounts.firstWhere((a) => a.id == 'a-sav').balance, bal - 5000);
      expect(l.transactions.first.internal, isTrue);

      l.moveGoal('g-trip', 'a-sav', -5000);
      expect(l.accounts.firstWhere((a) => a.id == 'a-sav').balance, bal);
      expect(() => l.moveGoal('g-trip', 'a-sav', -10000000), throwsA(isA<PaymentException>()));
      expect(() => l.moveGoal('g-trip', 'a-cur', 99999999), throwsA(isA<PaymentException>()));
      expect(() => l.moveGoal('g-trip', 'a-fd', 100), throwsA(isA<PaymentException>()));
    });
  });
}
