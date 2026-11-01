import '../../../core/network/api_client.dart';
import '../../../core/network/mappers.dart';
import '../../../shared/models/models.dart';
import '../../payments/data/mock_ledger.dart';
import '../domain/budgets.dart';

TxCategory _category(String name) => TxCategory.values.firstWhere((c) => c.name == name, orElse: () => TxCategory.other);

class MockBudgetRepository implements BudgetRepository {
  MockBudgetRepository(this._ledger);
  final MockLedger _ledger;

  @override
  Future<List<Budget>> budgets() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return [for (final e in _ledger.budgets.entries) Budget(category: e.key, monthlyLimit: e.value)];
  }

  @override
  Future<void> save(Budget budget) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!budget.monthlyLimit.isFinite || budget.monthlyLimit <= 0) throw ArgumentError.value(budget.monthlyLimit, 'monthlyLimit', 'must be positive');
    if (!budgetCategories.contains(budget.category)) throw ArgumentError.value(budget.category, 'category', 'can’t have a budget');
    _ledger.budgets[budget.category] = budget.monthlyLimit;
  }

  @override
  Future<void> remove(TxCategory category) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _ledger.budgets.remove(category);
  }
}

class ApiBudgetRepository implements BudgetRepository {
  ApiBudgetRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<Budget>> budgets() async => [
    for (final j in items(await _api.get('/v1/budgets'))) Budget(category: _category('${j['category']}'), monthlyLimit: fromMinor((j['monthlyLimitMinor'] as num).round())),
  ];

  @override
  Future<void> save(Budget budget) async {
    await _api.put('/v1/budgets/${budget.category.name}', body: {'monthlyLimitMinor': toMinor(budget.monthlyLimit)});
  }

  @override
  Future<void> remove(TxCategory category) async {
    await _api.delete('/v1/budgets/${category.name}');
  }
}
