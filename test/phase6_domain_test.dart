import 'package:bank_app/features/payments/data/mock_ledger.dart';
import 'package:bank_app/features/search/domain/search.dart';
import 'package:bank_app/features/security/data/mock_engagement_repositories.dart';
import 'package:bank_app/features/support/domain/support_content.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:bank_app/shared/models/payment_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const people = [
    Beneficiary(id: 'b1', bank: 'Commercial Bank', accountNumber: '8001234567', name: 'Nimal Perera', nickname: 'Nimal'),
    Beneficiary(id: 'b2', bank: 'Bank of Ceylon', accountNumber: '7712340988', name: 'Kamala Silva'),
  ];
  final txs = [
    Transaction(id: 'TX1', merchant: 'Keells Supermarket', category: TxCategory.food, amount: -100, date: DateTime(2026, 11, 1)),
    Transaction(id: 'TX2', merchant: 'Uber', category: TxCategory.transport, amount: -50, date: DateTime(2026, 11, 1), reference: 'airport'),
  ];

  group('searchAll', () {
    test('blank query finds nothing', () {
      expect(searchAll('  ', transactions: txs, beneficiaries: people), isEmpty);
    });

    test('finds across features, settings, people and transactions', () {
      final r = searchAll('pin', transactions: txs, beneficiaries: people);
      expect(r.map((s) => s.title), ['Features', 'Settings']);
      expect(r.first.hits.map((h) => h.route), ['/cards/manage'], reason: 'card PINs live under Card management');
      expect(r.last.hits.map((h) => h.route), contains('/security/pin'));

      final names = searchAll('nimal', transactions: txs, beneficiaries: people);
      expect(names.single.title, 'Beneficiaries');
      expect(names.single.hits.single.extra, people.first);

      final merchant = searchAll('keells', transactions: txs, beneficiaries: people);
      expect(merchant.single.hits.single.route, '/transactions/TX1');
    });

    test('every word must match, in any order', () {
      expect(searchAll('bills pay', transactions: txs, beneficiaries: people).first.hits.first.title, 'Pay bills');
      expect(searchAll('pay zzz', transactions: txs, beneficiaries: people), isEmpty);
    });

    test('matches on references and keywords, case-insensitively', () {
      expect(searchAll('AIRPORT', transactions: txs, beneficiaries: people).single.hits.single.title, 'Uber');
      expect(searchAll('freeze', transactions: txs, beneficiaries: people).single.hits.single.title, 'Card management');
    });

    test('caps each section', () {
      final many = [for (var i = 0; i < 20; i++) Transaction(id: 'T$i', merchant: 'Shop $i', category: TxCategory.shopping, amount: -1, date: DateTime(2026))];
      expect(searchAll('shop', transactions: many, beneficiaries: const []).single.hits, hasLength(6));
    });
  });

  group('botReply', () {
    test('urgent card problems point to a human', () {
      final r = botReply('I lost my card!');
      expect(r, contains('freeze'));
      expect(r, contains(supportPhone));
    });

    test('known topics get specific answers', () {
      expect(botReply('what are the fees'), contains('LKR 25'));
      expect(botReply('how do I change my password'), contains('Change password'));
      expect(botReply('daily limit?'), contains('500,000'));
    });

    test('unknown input is honest about being automated', () {
      expect(botReply('qwerty'), contains('automated assistant'));
    });
  });

  group('Mock engagement repositories', () {
    test('only other devices can be revoked', () async {
      final repo = MockSecurityRepository();
      await repo.revoke('d-this');
      expect((await repo.sessions()).any((s) => s.current), isTrue);
      await repo.revoke('d-2');
      expect((await repo.sessions()).map((s) => s.id), ['d-this', 'd-3']);
      await repo.revokeOthers();
      expect((await repo.sessions()).single.current, isTrue);
    });

    test('sign-ins are recorded newest first', () async {
      final repo = MockSecurityRepository();
      await repo.recordSignIn(success: false);
      final h = await repo.loginHistory();
      expect(h.first.success, isFalse);
      expect(h.first.device, 'This device');
    });

    test('notifications mark read individually and all at once, newest first', () async {
      final repo = MockNotificationRepository();
      var list = await repo.notifications();
      expect(list.first.date.isAfter(list.last.date), isTrue);
      final unread = list.where((n) => !n.read).length;
      expect(unread, greaterThan(1));
      await repo.markRead(list.firstWhere((n) => !n.read).id);
      list = await repo.notifications();
      expect(list.where((n) => !n.read).length, unread - 1);
      await repo.markAllRead();
      expect((await repo.notifications()).every((n) => n.read), isTrue);
    });

    test('daily limit can only be lowered below the bank maximum', () async {
      final ledger = MockLedger();
      final repo = MockLimitsRepository(ledger);
      await repo.setDaily(100000);
      expect((await repo.limits()).daily, 100000);
      expect(() => repo.setDaily(600000), throwsA(isA<PaymentException>()));
      expect(() => repo.setDaily(-1), throwsA(isA<PaymentException>()));
    });

    test('the ledger enforces the customer’s own daily limit', () {
      final ledger = MockLedger()..userDailyLimit = 100000;
      PaymentDraft d(double amount) => PaymentDraft(kind: PaymentKind.transfer, fromAccountId: 'a-sav', payee: 'X', payeeDetail: 'Bank •••• 1234', amount: amount);
      ledger.post(d(60000));
      expect(
        () => ledger.post(d(50000)),
        throwsA(isA<PaymentException>().having((e) => e.message, 'message', contains('LKR 100,000'))),
      );
    });
  });
}
