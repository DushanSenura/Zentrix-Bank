import 'dart:typed_data';
import '../../../shared/models/models.dart';
import '../../../shared/models/service_models.dart';

abstract interface class SavingsRepository {
  Future<List<SavingsGoal>> goals();
  Future<void> create(SavingsGoal goal);

  /// Positive [amount] deposits from [accountId] into the goal; negative withdraws back to it.
  /// Throws `PaymentException` when the bank refuses.
  Future<void> move(String goalId, String accountId, double amount);
}

abstract interface class LoanRepository {
  Future<List<Loan>> loans();

  /// Applications the customer has sent, newest first.
  Future<List<LoanApplication>> applications();

  /// Sends an application for review. Throws [LoanApplicationException] when it can't be accepted.
  Future<LoanApplication> apply(LoanApplicationRequest request);
}

/// Writes statement files (CSV and PDF) to app storage or the OS share sheet.
abstract interface class StatementExporter {
  Future<void> shareCsv(String fileName, String csv);

  /// Returns where the file was saved.
  Future<String> saveCsv(String fileName, String csv);

  Future<void> sharePdf(String fileName, Uint8List bytes);

  /// Returns where the file was saved.
  Future<String> savePdf(String fileName, Uint8List bytes);
}
