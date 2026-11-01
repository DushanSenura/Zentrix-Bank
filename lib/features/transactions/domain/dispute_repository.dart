import '../../../shared/models/models.dart';
import '../../../shared/models/service_models.dart';

abstract interface class DisputeRepository {
  /// Disputes the customer has raised, newest first.
  Future<List<Dispute>> disputes();

  /// Raises a dispute about [transaction]. Throws [DisputeException] if it can't be disputed or already has one open.
  Future<Dispute> raise({required Transaction transaction, required DisputeReason reason, required String details});
}
