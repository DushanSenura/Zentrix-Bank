import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/service_models.dart';
import '../../payments/data/mock_ledger.dart';
import '../domain/phase5_repositories.dart';

class MockSavingsRepository implements SavingsRepository {
  MockSavingsRepository(this._ledger);
  final MockLedger _ledger;

  @override
  Future<List<SavingsGoal>> goals() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return List.unmodifiable(_ledger.goals);
  }

  @override
  Future<void> create(SavingsGoal goal) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _ledger.addGoal(goal);
  }

  @override
  Future<void> move(String goalId, String accountId, double amount) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    _ledger.moveGoal(goalId, accountId, amount);
  }
}

class MockLoanRepository implements LoanRepository {
  MockLoanRepository(this._ledger);
  final MockLedger _ledger;

  @override
  Future<List<Loan>> loans() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return List.unmodifiable(_ledger.loans);
  }

  @override
  Future<List<LoanApplication>> applications() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_ledger.loanApplications);
  }

  @override
  Future<LoanApplication> apply(LoanApplicationRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return _ledger.applyForLoan(request);
  }
}

/// Writes statement files to app storage and shares them as files.
class LocalStatementExporter implements StatementExporter {
  const LocalStatementExporter();

  Future<File> _write(String name, List<int> bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$name').writeAsBytes(bytes, flush: true);
  }

  Future<void> _share(String name, List<int> bytes, String mime) async {
    final file = await _write(name, bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime)], subject: name));
  }

  @override
  Future<String> saveCsv(String fileName, String csv) async => (await _write(fileName, utf8.encode(csv))).path;

  @override
  Future<void> shareCsv(String fileName, String csv) => _share(fileName, utf8.encode(csv), 'text/csv');

  @override
  Future<String> savePdf(String fileName, Uint8List bytes) async => (await _write(fileName, bytes)).path;

  @override
  Future<void> sharePdf(String fileName, Uint8List bytes) => _share(fileName, bytes, 'application/pdf');
}
