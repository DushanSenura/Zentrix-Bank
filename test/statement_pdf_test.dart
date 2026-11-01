import 'dart:convert';
import 'package:bank_app/features/statements/domain/statement_pdf.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const account = BankAccount(id: 'a-sav', type: AccountType.savings, name: 'Savings Account', maskedNumber: '•••• 3021', balance: 1);

Transaction tx(String id, String merchant, double amount, {int day = 3, TxStatus status = TxStatus.completed}) => Transaction(
  id: id,
  merchant: merchant,
  category: amount > 0 ? TxCategory.income : TxCategory.food,
  amount: amount,
  date: DateTime(2026, 10, day, 12),
  status: status,
  method: 'Debit card •••• 4821',
);

void main() {
  test('pdfSafe keeps text readable in the built-in Latin-1 fonts', () {
    expect(pdfSafe('Salary — NovaCore Techs'), 'Salary - NovaCore Techs');
    expect(pdfSafe('Debit card •••• 4821'), 'Debit card **** 4821');
    expect(pdfSafe('“Café” it’s'), '"Café" it\'s');
    expect(pdfSafe('නමස්කාර'), '???????', reason: 'unsupported scripts become ?, never a crash');
  });

  test('file name mirrors the CSV one', () {
    expect(statementPdfFileName(account, DateTime(2026, 10)), 'statement_3021_2026-10.pdf');
  });

  test('builds a real PDF document with a statement of many pages', () async {
    final list = [for (var i = 0; i < 120; i++) tx('t$i', 'Merchant number $i — café', i.isEven ? -1500.5 : 2000, day: 1 + i % 28)];
    final bytes = await buildStatementPdf(
      account: account,
      month: DateTime(2026, 10),
      transactions: list,
      customerName: 'Dushan Perera',
      generatedAt: DateTime(2026, 11, 1, 9, 30),
    );
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(ascii.decode(bytes.sublist(bytes.length - 6), allowInvalid: true), contains('%%EOF'));
    expect(bytes.length, greaterThan(5000));
    final text = latin1.decode(bytes);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, greaterThan(1), reason: '120 rows need more than one page');
  });

  test('an empty month still produces a valid document', () async {
    final bytes = await buildStatementPdf(
      account: account,
      month: DateTime(2026, 9),
      transactions: const [],
      customerName: 'Dushan Perera',
      generatedAt: DateTime(2026, 11, 1),
    );
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });
}
