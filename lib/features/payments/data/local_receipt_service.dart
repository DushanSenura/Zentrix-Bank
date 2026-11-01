import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/payment_models.dart';
import '../domain/payment_repositories.dart';

String receiptText(Receipt r) {
  final b = StringBuffer()
    ..writeln('Zentrix Bank — ${r.scheduled ? 'Payment scheduled' : 'Payment receipt'}')
    ..writeln('Status: ${r.scheduled ? 'Scheduled' : 'Successful'}')
    ..writeln('Amount: ${formatMoney(r.amount)}')
    ..writeln('Fee: ${formatMoney(r.fee)}')
    ..writeln('Total: ${formatMoney(r.total)}')
    ..writeln('To: ${r.payee}')
    ..writeln('From: ${r.fromName} ${r.fromMasked}');
  for (final (k, v) in r.details) {
    if (k != 'To') b.writeln('$k: $v');
  }
  if (r.reference.isNotEmpty) b.writeln('Reference: ${r.reference}');
  b
    ..writeln('Transaction ID: ${r.id}')
    ..writeln('Date: ${r.date.toLocal().toString().split('.').first}');
  return b.toString();
}

/// Shares via the OS sheet and saves plain-text receipts to app storage.
/// A PDF renderer can replace [save] later without touching the UI.
class LocalReceiptService implements ReceiptService {
  const LocalReceiptService();

  @override
  Future<void> share(Receipt receipt) => SharePlus.instance.share(
    ShareParams(text: receiptText(receipt), subject: 'Zentrix Bank receipt ${receipt.id}'),
  );

  @override
  Future<String> save(Receipt receipt) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}receipt_${receipt.id}.txt');
    await file.writeAsString(receiptText(receipt));
    return file.path;
  }
}
