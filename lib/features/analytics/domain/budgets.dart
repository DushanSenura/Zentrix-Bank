import 'package:flutter/foundation.dart';
import '../../../shared/models/models.dart';
import 'analytics.dart';

/// A monthly spending limit the customer sets for one category.
@immutable
class Budget {
  const Budget({required this.category, required this.monthlyLimit});
  final TxCategory category;
  final double monthlyLimit;
}

enum BudgetState { onTrack, nearLimit, over }

@immutable
class BudgetProgress {
  const BudgetProgress({required this.budget, required this.spent});
  final Budget budget;
  final double spent;

  double get remaining => budget.monthlyLimit - spent;
  double get fraction => budget.monthlyLimit <= 0 ? 0 : spent / budget.monthlyLimit;

  BudgetState get state => fraction >= 1 ? BudgetState.over : (fraction >= nearLimitAt ? BudgetState.nearLimit : BudgetState.onTrack);

  /// Warn once spending reaches this share of the limit.
  static const nearLimitAt = 0.8;
}

/// Budgets that can be set: the same categories the spending breakdown uses.
const budgetCategories = spendingCategories;

DateTime _monthStart(DateTime d) => DateTime(d.year, d.month);

/// Month-to-date spending against each budget, in the order the budgets are given.
/// Counts the same transactions the analytics screen does: settled, not own-account moves.
List<BudgetProgress> budgetProgress(List<Budget> budgets, List<Transaction> transactions, DateTime now) {
  final spent = spendingByCategory(transactions, now, from: _monthStart(now), to: now);
  return [for (final b in budgets) BudgetProgress(budget: b, spent: spent[b.category] ?? 0)];
}

/// What the customer has typically spent in [category] per month over the last [months] full months
/// (rounded to the nearest 1,000), as a starting point for a limit. Null when there is no history to go on.
double? suggestedBudget(List<Transaction> transactions, DateTime now, TxCategory category, {int months = 3}) {
  var total = 0.0;
  var counted = 0;
  for (var i = 1; i <= months; i++) {
    final start = DateTime(now.year, now.month - i);
    final end = DateTime(now.year, now.month - i + 1, 0);
    final spent = spendingByCategory(transactions, now, from: start, to: end)[category] ?? 0;
    if (spent > 0) {
      total += spent;
      counted++;
    }
  }
  if (counted == 0) return null;
  final avg = total / counted;
  return ((avg / 1000).round() * 1000).clamp(1000, double.infinity).toDouble();
}

enum BudgetAlertKind { nearLimit, over }

@immutable
class BudgetAlert {
  const BudgetAlert(this.category, this.kind, this.progress);
  final TxCategory category;
  final BudgetAlertKind kind;
  final BudgetProgress progress;
}

/// Alerts for budgets that crossed a threshold between [before] and [after], so each one is raised once as spending grows,
/// not on every later payment.
List<BudgetAlert> budgetAlerts(List<BudgetProgress> before, List<BudgetProgress> after) {
  final prior = {for (final p in before) p.budget.category: p.state};
  final alerts = <BudgetAlert>[];
  for (final p in after) {
    final was = prior[p.budget.category] ?? BudgetState.onTrack;
    if (p.state == BudgetState.over && was != BudgetState.over) {
      alerts.add(BudgetAlert(p.budget.category, BudgetAlertKind.over, p));
    } else if (p.state == BudgetState.nearLimit && was == BudgetState.onTrack) {
      alerts.add(BudgetAlert(p.budget.category, BudgetAlertKind.nearLimit, p));
    }
  }
  return alerts;
}

abstract interface class BudgetRepository {
  Future<List<Budget>> budgets();

  /// Creates or replaces the budget for [Budget.category]. Throws [ArgumentError] for a limit that isn't positive.
  Future<void> save(Budget budget);

  Future<void> remove(TxCategory category);
}
