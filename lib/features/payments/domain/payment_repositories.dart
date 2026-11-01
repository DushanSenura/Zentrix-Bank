import '../../../shared/models/payment_models.dart';

abstract interface class BeneficiaryRepository {
  Future<List<Beneficiary>> beneficiaries();
  Future<void> add(Beneficiary beneficiary);
  Future<void> update(Beneficiary beneficiary);
  Future<void> remove(String id);
}

abstract interface class PaymentRepository {
  /// Executes [draft]. The server — not the client — decides whether funds and limits allow it.
  /// Throws [PaymentException] on a business failure.
  Future<Receipt> pay(PaymentDraft draft);
}

abstract interface class ScheduledPaymentRepository {
  /// Active and recently finished scheduled payments, soonest first.
  Future<List<ScheduledPayment>> scheduled();

  /// Stops a scheduled (or repeating) payment. Throws `PaymentException` if it can't be found or already finished.
  Future<void> cancel(String id);
}

/// Turns a [Receipt] into something the user can keep or send.
abstract interface class ReceiptService {
  Future<void> share(Receipt receipt);

  /// Saves a copy and returns where it was written.
  Future<String> save(Receipt receipt);
}
