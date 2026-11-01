import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter/foundation.dart';
import '../../../shared/models/models.dart';

enum Direction { all, income, expense }

@immutable
class TransactionFilter {
  const TransactionFilter({
    this.query = '',
    this.range,
    this.categories = const {},
    this.direction = Direction.all,
    this.minAmount,
    this.maxAmount,
    this.accountId,
  });
  final String query;
  final DateTimeRange? range;
  final Set<TxCategory> categories;
  final Direction direction;

  /// Compared against the absolute amount.
  final double? minAmount, maxAmount;
  final String? accountId;

  /// Whether any filter besides the search text is set.
  bool get hasFilters =>
      range != null || categories.isNotEmpty || direction != Direction.all || minAmount != null || maxAmount != null || accountId != null;

  int get filterCount =>
      (range != null ? 1 : 0) +
      (categories.isNotEmpty ? 1 : 0) +
      (direction != Direction.all ? 1 : 0) +
      (minAmount != null || maxAmount != null ? 1 : 0) +
      (accountId != null ? 1 : 0);

  TransactionFilter copyWith({String? query}) => TransactionFilter(
    query: query ?? this.query,
    range: range,
    categories: categories,
    direction: direction,
    minAmount: minAmount,
    maxAmount: maxAmount,
    accountId: accountId,
  );

  /// Replaces every filter field (search text is kept).
  TransactionFilter withFilters({
    DateTimeRange? range,
    Set<TxCategory> categories = const {},
    Direction direction = Direction.all,
    double? minAmount,
    double? maxAmount,
    String? accountId,
  }) => TransactionFilter(
    query: query,
    range: range,
    categories: categories,
    direction: direction,
    minAmount: minAmount,
    maxAmount: maxAmount,
    accountId: accountId,
  );

  bool matches(Transaction t) {
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty && !('${t.merchant} ${t.id} ${t.reference}'.toLowerCase().contains(q))) return false;
    if (range != null) {
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      final from = DateTime(range!.start.year, range!.start.month, range!.start.day);
      final to = DateTime(range!.end.year, range!.end.month, range!.end.day);
      if (day.isBefore(from) || day.isAfter(to)) return false;
    }
    if (categories.isNotEmpty && !categories.contains(t.category)) return false;
    if (direction == Direction.income && t.amount < 0) return false;
    if (direction == Direction.expense && t.amount >= 0) return false;
    final abs = t.amount.abs();
    if (minAmount != null && abs < minAmount!) return false;
    if (maxAmount != null && abs > maxAmount!) return false;
    if (accountId != null && t.accountId != accountId) return false;
    return true;
  }
}

class TransactionGroup {
  const TransactionGroup(this.title, this.items);
  final String title;
  final List<Transaction> items;
}

/// Buckets newest-first transactions into Upcoming / Today / Yesterday / This week / Earlier.
List<TransactionGroup> groupTransactions(List<Transaction> list, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final buckets = <String, List<Transaction>>{
    'Upcoming': [],
    'Today': [],
    'Yesterday': [],
    'This week': [],
    'Earlier': [],
  };
  for (final t in list) {
    final day = DateTime(t.date.year, t.date.month, t.date.day);
    final diff = today.difference(day).inDays;
    final key = day.isAfter(today)
        ? 'Upcoming'
        : diff == 0
        ? 'Today'
        : diff == 1
        ? 'Yesterday'
        : diff < 7
        ? 'This week'
        : 'Earlier';
    buckets[key]!.add(t);
  }
  return [
    for (final e in buckets.entries)
      if (e.value.isNotEmpty) TransactionGroup(e.key, e.value),
  ];
}
