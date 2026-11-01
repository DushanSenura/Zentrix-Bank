import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/mappers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/service_models.dart';
import '../domain/dispute_repository.dart';

class ApiDisputeRepository implements DisputeRepository {
  ApiDisputeRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<Dispute>> disputes() async => items(await _api.get('/v1/disputes')).map(disputeFromJson).toList();

  @override
  Future<Dispute> raise({required Transaction transaction, required DisputeReason reason, required String details}) async {
    try {
      return disputeFromJson(
        await _api.post(
          '/v1/disputes',
          idempotencyKey: newIdempotencyKey(),
          body: {'transactionId': transaction.id, 'reason': reason.name, 'details': details},
        ),
      );
    } on RejectedException catch (e) {
      throw DisputeException(e.message);
    }
  }
}
