import 'package:bank_app/app/providers.dart';
import 'package:bank_app/features/dashboard/data/mock_banking_repositories.dart';
import 'package:bank_app/features/payments/data/local_receipt_service.dart';
import 'package:bank_app/features/payments/data/mock_ledger.dart';
import 'package:bank_app/features/payments/domain/banks.dart';
import 'package:bank_app/features/payments/domain/qr_payload.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:bank_app/shared/models/payment_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bank_app/features/authentication/data/mock_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

PaymentDraft draft({
  double amount = 1000,
  double fee = 0,
  String from = 'a-sav',
  String detail = 'Commercial Bank •••• 4567',
  String? toOwn,
  DateTime? when,
  PaymentKind kind = PaymentKind.transfer,
}) => PaymentDraft(
  kind: kind,
  fromAccountId: from,
  payee: 'Nimal Perera',
  payeeDetail: detail,
  amount: amount,
  fee: fee,
  toAccountId: toOwn,
  scheduledFor: when,
);

double balance(MockLedger l, String id) => l.accounts.firstWhere((a) => a.id == id).balance;

void main() {
  group('MockLedger (the server-side rules)', () {
    test('debits amount plus fee and records a completed transaction', () {
      final l = MockLedger();
      final before = balance(l, 'a-sav');
      final r = l.post(draft(amount: 1000, fee: 25));
      expect(balance(l, 'a-sav'), before - 1025);
      expect(r.total, 1025);
      expect(r.status, TxStatus.completed);
      expect(l.transactions.first.amount, -1025);
      expect(l.transactions.first.id, r.id);
    });

    test('own-account transfers move money between accounts without a fee', () {
      final l = MockLedger();
      final sav = balance(l, 'a-sav'), cur = balance(l, 'a-cur');
      l.post(draft(amount: 5000, toOwn: 'a-cur'));
      expect(balance(l, 'a-sav'), sav - 5000);
      expect(balance(l, 'a-cur'), cur + 5000);
    });

    test('rejects insufficient funds without changing anything', () {
      final l = MockLedger();
      final before = balance(l, 'a-cur');
      expect(
        () => l.post(draft(amount: 90000, from: 'a-cur')),
        throwsA(isA<PaymentException>().having((e) => e.failure, 'failure', PaymentFailure.insufficientFunds)),
      );
      expect(balance(l, 'a-cur'), before);
    });

    test('the fee counts towards the funds check', () {
      final l = MockLedger();
      final cur = balance(l, 'a-cur');
      expect(() => l.post(draft(amount: cur, fee: 25, from: 'a-cur')), throwsA(isA<PaymentException>()));
    });

    test('rejects an unverifiable recipient account', () {
      final l = MockLedger();
      expect(
        () => l.post(draft(detail: 'Commercial Bank •••• 0000')),
        throwsA(isA<PaymentException>().having((e) => e.failure, 'failure', PaymentFailure.invalidRecipient)),
      );
    });

    test('enforces the daily transfer limit across payments', () {
      final l = MockLedger();
      l.post(draft(amount: 300000, toOwn: 'a-cur')); // counts towards the limit
      expect(
        () => l.post(draft(amount: 250000, from: 'a-cur')),
        throwsA(isA<PaymentException>().having((e) => e.failure, 'failure', PaymentFailure.limitExceeded)),
      );
    });

    test('scheduled payments are recorded as pending and move no money yet', () {
      final l = MockLedger();
      final before = balance(l, 'a-sav');
      final r = l.post(draft(when: DateTime.now().add(const Duration(days: 3))));
      expect(balance(l, 'a-sav'), before);
      expect(r.scheduled, isTrue);
      expect(l.transactions.first.status, TxStatus.pending);
    });

    test('deposits can’t be paid from', () {
      expect(() => MockLedger().post(draft(from: 'a-fd')), throwsA(isA<PaymentException>()));
    });
  });

  group('QR payloads', () {
    test('round-trips a merchant code', () {
      final m = parseMerchantQr(merchantQr('KEELLS-114', 'Keells Supermarket', TxCategory.food))!;
      expect(m.id, 'KEELLS-114');
      expect(m.name, 'Keells Supermarket');
      expect(m.category, TxCategory.food);
    });

    test('rejects foreign or incomplete codes', () {
      expect(parseMerchantQr('https://example.com/pay'), isNull);
      expect(parseMerchantQr('zentrixpay://pay?m=X'), isNull);
      expect(parseMerchantQr('zentrixpay://receive?c=1&n=A'), isNull);
      expect(parseMerchantQr(''), isNull);
    });

    test('My QR carries identity only', () {
      final qr = receiveQr('NC 1029 3847', 'Dushan Perera');
      expect(qr, contains('NC10293847'));
      expect(qr.toLowerCase(), isNot(contains('balance')));
    });
  });

  group('Helpers', () {
    test('inter-bank fee', () {
      expect(transferFeeFor(ownBank), 0);
      expect(transferFeeFor('Bank of Ceylon'), interbankFee);
    });

    test('receipt text has the essentials and no card data', () {
      final r = MockLedger().post(draft(amount: 1000, fee: 25));
      final text = receiptText(r);
      expect(text, contains('LKR 1,000.00'));
      expect(text, contains('LKR 1,025.00'));
      expect(text, contains(r.id));
    });
  });

  test('a payment made in the app can be repeated; seeded history can’t', () async {
    final ledger = MockLedger();
    final repo = MockTransactionRepository(ledger);
    final receipt = ledger.post(draft(amount: 750));
    expect((await repo.repeatDraft(receipt.id))!.amount, 750);
    expect(await repo.repeatDraft('TX482100'), isNull);
  });

  test('beneficiaries list favourites first, then alphabetically', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(authProvider.notifier).start(MockAuthRepository.demoUser);
    final list = await container.read(beneficiariesProvider.future);
    expect(list.first.favorite, isTrue);
    final rest = list.skip(1).map((b) => b.displayName.toLowerCase()).toList();
    expect(rest, [...rest]..sort());

    final notifier = container.read(beneficiariesProvider.notifier);
    final kamala = list.firstWhere((b) => b.name == 'Kamala Silva');
    await notifier.edit(kamala.copyWith(favorite: true));
    expect(container.read(beneficiariesProvider).value!.first.name, 'Kamala Silva');
    await notifier.remove(kamala.id);
    expect(container.read(beneficiariesProvider).value!.any((b) => b.id == kamala.id), isFalse);
  });
}
