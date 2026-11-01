import '../../../shared/models/models.dart';

class StatementSummary {
  const StatementSummary({required this.moneyIn, required this.moneyOut, required this.count});
  final double moneyIn, moneyOut;
  final int count;
  double get net => moneyIn - moneyOut;
}

/// Settled transactions of [accountId] dated within the given calendar month, newest first.
List<Transaction> statementTransactions(List<Transaction> all, String accountId, DateTime month) => [
  for (final t in all)
    if (t.accountId == accountId && t.status == TxStatus.completed && t.date.year == month.year && t.date.month == month.month) t,
]..sort((a, b) => b.date.compareTo(a.date));

StatementSummary summarize(List<Transaction> list) {
  var inn = 0.0, out = 0.0;
  for (final t in list) {
    t.amount >= 0 ? inn += t.amount : out -= t.amount;
  }
  return StatementSummary(moneyIn: inn, moneyOut: out, count: list.length);
}

String _cell(String v) => v.contains(RegExp(r'[",\n]')) ? '"${v.replaceAll('"', '""')}"' : v;

String _two(int n) => n.toString().padLeft(2, '0');

/// RFC 4180 CSV. Amounts are signed (negative = money out).
String statementCsv(List<Transaction> list, BankAccount account) {
  final b = StringBuffer('Date,Time,Description,Category,Method,Reference,Transaction ID,Amount (${account.currency})\r\n');
  for (final t in list) {
    final d = t.date;
    b.write(
      [
        '${d.year}-${_two(d.month)}-${_two(d.day)}',
        '${_two(d.hour)}:${_two(d.minute)}',
        t.merchant,
        t.category.name,
        t.method,
        t.reference,
        t.id,
        t.amount.toStringAsFixed(2),
      ].map(_cell).join(','),
    );
    b.write('\r\n');
  }
  return b.toString();
}

String statementFileName(BankAccount account, DateTime month) =>
    'statement_${account.maskedNumber.replaceAll(RegExp(r'[^0-9]'), '')}_${month.year}-${_two(month.month)}.csv';
