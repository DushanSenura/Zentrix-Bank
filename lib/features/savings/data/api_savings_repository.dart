import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/mappers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/payment_models.dart';
import '../domain/phase5_repositories.dart';

class ApiSavingsRepository implements SavingsRepository {
  ApiSavingsRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<SavingsGoal>> goals() async => items(await _api.get('/v1/savings/goals')).map(goalFromJson).toList();

  @override
  Future<void> create(SavingsGoal goal) async {
    await _api.post('/v1/savings/goals', body: goalToJson(goal));
  }

  /// Money moves, so this carries an idempotency key like a payment does. A fresh key per call is
  /// right here: the UI never auto-resends, and a second tap is a second deliberate request.
  @override
  Future<void> move(String goalId, String accountId, double amount) async {
    try {
      await _api.post(
        '/v1/savings/goals/${Uri.encodeComponent(goalId)}/transfer',
        body: {'accountId': accountId, 'amountMinor': toMinor(amount)},
        idempotencyKey: newIdempotencyKey(),
      );
    } on RejectedException catch (e) {
      throw PaymentException(paymentFailureFor(e.code), e.message);
    } on NetworkException {
      throw const PaymentException(PaymentFailure.unavailable, 'We couldn’t confirm whether that went through. Check your balance before trying again.');
    }
  }
}
