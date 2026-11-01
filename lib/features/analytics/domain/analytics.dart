import 'package:flutter/foundation.dart';
import '../../../shared/models/models.dart';

/// Categories shown in the spending breakdown. Transfers to other people fold into "Other".
const spendingCategories = [
  TxCategory.food,
  TxCategory.shopping,
  TxCategory.transport,
  TxCategory.bills,
  TxCategory.entertainment,
  TxCategory.health,
  TxCategory.education,
  TxCategory.other,
];

TxCategory spendingBucket(TxCategory c) => spendingCategories.contains(c) ? c : TxCategory.other;

/// Transactions that count towards income/spending: settled, in the past, and not own-account moves.
Iterable<Transaction> _countable(List<Transaction> list, DateTime now) =>
    list.where((t) => t.status == TxStatus.completed && !t.internal && !t.date.isAfter(now));

@immutable
class MonthTotals {
  const MonthTotals(this.month, this.income, this.expense);
  final DateTime month;
  final double income, expense;
  double get net => income - expense;
}

/// Oldest → newest, ending with the month containing [now].
List<MonthTotals> monthlyTotals(List<Transaction> list, DateTime now, {int months = 6}) {
  final counted = _countable(list, now).toList();
  return [
    for (var i = months - 1; i >= 0; i--)
      () {
        final month = DateTime(now.year, now.month - i);
        var income = 0.0, expense = 0.0;
        for (final t in counted) {
          if (t.date.year != month.year || t.date.month != month.month) continue;
          t.amount >= 0 ? income += t.amount : expense -= t.amount;
        }
        return MonthTotals(month, income, expense);
      }(),
  ];
}

/// Spending per category between [from] and [to] (inclusive days).
Map<TxCategory, double> spendingByCategory(List<Transaction> list, DateTime now, {required DateTime from, required DateTime to}) {
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
  final out = <TxCategory, double>{};
  for (final t in _countable(list, now)) {
    if (t.amount >= 0 || t.date.isBefore(start) || t.date.isAfter(end)) continue;
    out.update(spendingBucket(t.category), (v) => v - t.amount, ifAbsent: () => -t.amount);
  }
  return out;
}

@immutable
class Insight {
  const Insight(this.text, {required this.good});
  final String text;

  /// True when the change is favourable (spending down, saving up).
  final bool good;
}

String categoryName(TxCategory c) => switch (c) {
  TxCategory.food => 'food',
  TxCategory.shopping => 'shopping',
  TxCategory.transport => 'transport',
  TxCategory.bills => 'bills',
  TxCategory.entertainment => 'entertainment',
  TxCategory.health => 'health',
  TxCategory.education => 'education',
  _ => 'other spending',
};

/// Plain arithmetic over the user's own transactions: month-to-date versus the same days last month.
/// This is not financial advice and isn't produced by a model.
List<Insight> buildInsights(List<Transaction> list, DateTime now, {int max = 3}) {
  final thisFrom = DateTime(now.year, now.month);
  final lastFrom = DateTime(now.year, now.month - 1);
  // Same number of days into the previous month (clamped for shorter months).
  final lastDaysInMonth = DateTime(now.year, now.month, 0).day;
  final lastTo = DateTime(now.year, now.month - 1, now.day.clamp(1, lastDaysInMonth));

  final current = spendingByCategory(list, now, from: thisFrom, to: now);
  final previous = spendingByCategory(list, now, from: lastFrom, to: lastTo);

  final changes = <(TxCategory, double)>[
    for (final c in spendingCategories)
      if ((current[c] ?? 0) > 0 && (previous[c] ?? 0) > 0) (c, ((current[c]! - previous[c]!) / previous[c]!) * 100),
  ]..sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));

  final out = <Insight>[
    for (final (c, pct) in changes)
      if (pct.abs() >= 5)
        Insight(
          pct < 0
              ? 'You’ve spent ${pct.abs().round()}% less on ${categoryName(c)} than at this point last month.'
              : 'Spending on ${categoryName(c)} is up ${pct.round()}% compared with this point last month.',
          good: pct < 0,
        ),
  ];

  final month = monthlyTotals(list, now, months: 1).single;
  if (month.income > 0) {
    final rate = (month.net / month.income * 100).round();
    out.add(
      rate >= 0
          ? Insight('You’ve kept $rate% of this month’s income so far.', good: true)
          : Insight('You’ve spent more than you’ve earned so far this month.', good: false),
    );
  }
  return out.take(max).toList();
}
