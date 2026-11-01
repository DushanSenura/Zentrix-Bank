import '../../../shared/models/models.dart';
import '../../../shared/models/service_models.dart';
import '../../payments/data/mock_ledger.dart';
import '../domain/dispute_repository.dart';

class MockDisputeRepository implements DisputeRepository {
  MockDisputeRepository(this._ledger);
  final MockLedger _ledger;

  @override
  Future<List<Dispute>> disputes() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_ledger.disputes);
  }

  @override
  Future<Dispute> raise({required Transaction transaction, required DisputeReason reason, required String details}) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return _ledger.raiseDispute(transaction, reason, details);
  }
}
