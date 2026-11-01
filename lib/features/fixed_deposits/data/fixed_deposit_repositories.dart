import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/mappers.dart';
import '../../../shared/models/payment_models.dart';
import '../../payments/data/mock_ledger.dart';
import '../domain/fixed_deposit.dart';

List<FixedDeposit> _ordered(Iterable<FixedDeposit> all) => [...all]..sort((a, b) {
  if (a.active != b.active) return a.active ? -1 : 1;
  return a.maturityDate.compareTo(b.maturityDate);
});

class MockFixedDepositRepository implements FixedDepositRepository {
  MockFixedDepositRepository(this._ledger);
  final MockLedger _ledger;

  @override
  Future<List<FixedDeposit>> deposits() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _ledger.runDue();
    return List.unmodifiable(_ordered(_ledger.fixedDeposits));
  }

  @override
  Future<FixedDeposit> open({required String fromAccountId, required double amount, required int termMonths, required FdRenewal renewal}) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return _ledger.openFixedDeposit(fromAccountId: fromAccountId, amount: amount, termMonths: termMonths, renewal: renewal);
  }
}

class ApiFixedDepositRepository implements FixedDepositRepository {
  ApiFixedDepositRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<FixedDeposit>> deposits() async => _ordered(items(await _api.get('/v1/fixed-deposits')).map(fixedDepositFromJson));

  @override
  Future<FixedDeposit> open({required String fromAccountId, required double amount, required int termMonths, required FdRenewal renewal}) async {
    try {
      return fixedDepositFromJson(
        await _api.post(
          '/v1/fixed-deposits',
          idempotencyKey: newIdempotencyKey(),
          body: {'fromAccountId': fromAccountId, 'amountMinor': toMinor(amount), 'termMonths': termMonths, 'renewal': renewal.name},
        ),
      );
    } on RejectedException catch (e) {
      throw PaymentException(paymentFailureFor(e.code), e.message);
    }
  }
}
