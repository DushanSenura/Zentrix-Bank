import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/mappers.dart';
import '../../../shared/models/payment_models.dart';
import '../domain/payment_repositories.dart';

class ApiBeneficiaryRepository implements BeneficiaryRepository {
  ApiBeneficiaryRepository(this._api);
  final ApiClient _api;

  String _path(String id) => '/v1/beneficiaries/${Uri.encodeComponent(id)}';

  @override
  Future<List<Beneficiary>> beneficiaries() async => items(await _api.get('/v1/beneficiaries')).map(beneficiaryFromJson).toList();

  @override
  Future<void> add(Beneficiary beneficiary) async {
    try {
      await _api.post('/v1/beneficiaries', body: beneficiaryToJson(beneficiary));
    } on RejectedException catch (e) {
      // 409 `duplicate`: the controller already treats this as "already saved".
      throw PaymentException(e.code == 'duplicate' ? PaymentFailure.invalidRecipient : PaymentFailure.unavailable, e.message);
    }
  }

  @override
  Future<void> update(Beneficiary beneficiary) async {
    await _api.put(_path(beneficiary.id), body: beneficiaryToJson(beneficiary));
  }

  @override
  Future<void> remove(String id) async {
    await _api.delete(_path(id));
  }
}

class ApiScheduledPaymentRepository implements ScheduledPaymentRepository {
  ApiScheduledPaymentRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<ScheduledPayment>> scheduled() async => items(await _api.get('/v1/scheduled-payments')).map(scheduledPaymentFromJson).toList();

  @override
  Future<void> cancel(String id) async {
    try {
      await _api.delete('/v1/scheduled-payments/${Uri.encodeComponent(id)}');
    } on RejectedException catch (e) {
      throw PaymentException(PaymentFailure.unavailable, e.message);
    }
  }
}

/// Maps API failures onto the exceptions the payment UI already understands.
class ApiPaymentRepository implements PaymentRepository {
  ApiPaymentRepository(this._api);
  final ApiClient _api;

  /// One key per draft object. If the connection drops after the request left the device, resending
  /// the same draft reuses the key, so the server returns the first result instead of paying twice.
  final _keys = Expando<String>('payment idempotency key');

  @override
  Future<Receipt> pay(PaymentDraft draft) async {
    final key = _keys[draft] ??= newIdempotencyKey();
    try {
      return receiptFromJson(await _api.post('/v1/payments', body: paymentToJson(draft), idempotencyKey: key));
    } on RejectedException catch (e) {
      throw PaymentException(paymentFailureFor(e.code), e.message);
    } on MaintenanceException catch (e) {
      throw PaymentException(PaymentFailure.unavailable, e.message);
    } on NetworkException {
      // Ambiguous: the request may have reached the bank. Never claim it failed cleanly.
      throw const PaymentException(
        PaymentFailure.unavailable,
        'We couldn’t confirm whether this payment went through. Check your recent transactions before trying again.',
      );
    } on ServerException {
      throw const PaymentException(
        PaymentFailure.unavailable,
        'The bank couldn’t process this payment right now. Check your recent transactions before trying again.',
      );
    }
  }
}
