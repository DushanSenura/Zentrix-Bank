import 'package:bank_app/core/network/api_exceptions.dart';
import 'package:bank_app/features/dashboard/data/api_banking_repositories.dart';
import 'package:bank_app/features/fixed_deposits/data/fixed_deposit_repositories.dart';
import 'package:bank_app/features/fixed_deposits/domain/fixed_deposit.dart';
import 'package:bank_app/features/savings/data/api_savings_repository.dart';
import 'package:bank_app/features/security/data/api_engagement_repositories.dart';
import 'package:bank_app/shared/models/engagement_models.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:bank_app/shared/models/payment_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'net_helpers.dart';

void main() {
  group('cards', () {
    test('controls round-trip in minor units, and freeze/PIN/report hit the right endpoints', () async {
      final rig = Rig(
        (o) => switch ((o.method, o.path)) {
          ('GET', '/v1/cards/c1/controls') => json({'dailyLimitMinor': 5000000, 'maxDailyLimitMinor': 10000000, 'onlineEnabled': false}),
          _ => json({}),
        },
      );
      final repo = ApiCardRepository(rig.client);
      final c = await repo.controls('c1');
      expect(c.dailyLimit, 50000);
      expect(c.maxDailyLimit, 100000);
      expect(c.onlineEnabled, isFalse);
      expect(c.internationalEnabled, isFalse);

      await repo.updateControls('c1', c.copyWith(dailyLimit: 20000.5, internationalEnabled: true));
      expect(rig.adapter.requests.last.data, {'dailyLimitMinor': 2000050, 'onlineEnabled': false, 'internationalEnabled': true});

      await repo.changePin('c1', currentPin: '4821', newPin: '2580');
      expect(rig.adapter.requests.last.path, '/v1/cards/c1/pin');
      expect(rig.adapter.requests.last.method, 'PUT');
      // The card PIN is sent to the bank but never reaches the log.
      expect(rig.logs.join('\n'), isNot(contains('4821')));
      expect(rig.logs.join('\n'), isNot(contains('2580')));

      await repo.reportLostOrStolen('c1');
      expect(rig.adapter.requests.last.path, '/v1/cards/c1/report-lost');
    });

    test('bank refusals become CardException with the banks wording; outages stay network errors', () async {
      var rig = Rig((_) => json({'code': 'wrong_pin', 'message': 'The current card PIN is incorrect.'}, 422));
      await expectLater(
        ApiCardRepository(rig.client).changePin('c1', currentPin: '0000', newPin: '2580'),
        throwsA(isA<CardException>().having((e) => e.message, 'message', 'The current card PIN is incorrect.')),
      );
      rig = Rig((o) => throw DioException.connectionError(requestOptions: o, reason: 'x'));
      await expectLater(ApiCardRepository(rig.client).setFrozen('c1', true), throwsA(isA<NetworkException>()));
    });

    test('cards parse the blocked flag', () async {
      final rig = Rig(
        (_) => json({
          'items': [
            {'id': 'c1', 'kind': 'debit', 'network': 'visa', 'holder': 'D P', 'last4': '4821', 'expiry': '09/28', 'blocked': true},
          ],
        }),
      );
      expect((await ApiCardRepository(rig.client).cards()).single.blocked, isTrue);
    });
  });

  group('loans', () {
    test('parse minor units, rates and history', () async {
      final rig = Rig(
        (_) => json({
          'items': [
            {
              'id': 'l1',
              'type': 'vehicle',
              'principalMinor': 350000000,
              'outstandingMinor': 215000000,
              'annualRate': 13.5,
              'monthlyPaymentMinor': 8000050,
              'nextPaymentDate': '2026-12-05T00:00:00Z',
              'remainingMonths': 36,
              'totalMonths': 60,
              'history': [
                {'date': '2026-11-05T00:00:00Z', 'amountMinor': 8000050},
              ],
            },
          ],
        }),
      );
      final loan = (await ApiLoanRepository(rig.client).loans()).single;
      expect(loan.outstanding, 2150000);
      expect(loan.monthlyPayment, 80000.50);
      expect(loan.history.single.amount, 80000.50);
      expect(loan.type, LoanType.vehicle);
    });
  });

  group('savings, notifications, security, limits, branches', () {
    test('savings goals parse, and moving money carries an idempotency key', () async {
      final rig = Rig(
        (o) => o.method == 'GET'
            ? json({
                'items': [
                  {'id': 'g1', 'name': 'Car', 'targetMinor': 250000000, 'savedMinor': 85000000, 'targetDate': '2028-11-01T00:00:00Z', 'autoMonthlyMinor': 2500000},
                ],
              })
            : json({}),
      );
      final repo = ApiSavingsRepository(rig.client);
      final g = (await repo.goals()).single;
      expect(g.target, 2500000);
      expect(g.autoMonthly, 25000);
      await repo.move('g1', 'a-sav', 1500);
      final sent = rig.adapter.requests.last;
      expect(sent.data, {'accountId': 'a-sav', 'amountMinor': 150000});
      expect((sent.headers['Idempotency-Key'] as String).length, 32);
    });

    test('a refused goal transfer becomes a PaymentException; a dropped connection says the outcome is unknown', () async {
      var rig = Rig((_) => json({'code': 'insufficient_funds', 'message': 'Not enough.'}, 422));
      await expectLater(
        ApiSavingsRepository(rig.client).move('g', 'a', 5),
        throwsA(isA<PaymentException>().having((e) => e.failure, 'failure', PaymentFailure.insufficientFunds)),
      );
      rig = Rig((o) => throw DioException.connectionError(requestOptions: o, reason: 'x'));
      await expectLater(
        ApiSavingsRepository(rig.client).move('g', 'a', 5),
        throwsA(isA<PaymentException>().having((e) => e.message, 'message', contains('couldn’t confirm'))),
      );
    });

    test('notifications parse categories and severity; read calls use the right paths', () async {
      final rig = Rig(
        (_) => json({
          'items': [
            {'id': 'n1', 'category': 'bank_notices', 'title': 'Hi', 'body': 'b', 'date': '2026-11-01T08:00:00Z', 'read': true, 'severity': 'critical'},
            {'id': 'n2', 'category': 'security', 'title': 'T', 'body': 'b', 'date': '2026-11-01T08:00:00Z'},
          ],
        }),
      );
      final repo = ApiNotificationRepository(rig.client);
      final list = await repo.notifications();
      expect(list.first.category, NotifCategory.bankNotices);
      expect(list.first.severity, Severity.critical);
      expect(list.last.read, isFalse);
      await repo.markRead('n 2');
      expect(rig.adapter.requests.last.path, '/v1/notifications/n%202/read');
      await repo.markAllRead();
      expect(rig.adapter.requests.last.path, '/v1/notifications/read-all');
    });

    test('sessions, history, two-factor, limits and branches', () async {
      final rig = Rig(
        (o) => switch (o.path) {
          '/v1/security/sessions' => json({
            'items': [
              {'id': 's1', 'name': 'Pixel 9', 'platform': 'Android', 'lastActive': '2026-11-01T08:00:00Z', 'current': true},
            ],
          }),
          '/v1/security/login-history' => json({
            'items': [
              {'date': '2026-11-01T08:00:00Z', 'device': 'Pixel 9', 'success': false},
            ],
          }),
          '/v1/security/two-factor' => json({'enabled': true}),
          '/v1/limits/transfer' => json({'bankMaximumMinor': 50000000, 'dailyMinor': 20000000}),
          '/v1/support/branches' => json({
            'items': [
              {'name': 'Colombo Fort', 'address': '1 Main St', 'distanceKm': 1.2, 'isAtm': false},
            ],
          }),
          _ => json({}),
        },
      );
      expect((await ApiSecurityRepository(rig.client).sessions()).single.current, isTrue);
      expect((await ApiSecurityRepository(rig.client).loginHistory()).single.success, isFalse);
      expect(await ApiSecurityRepository(rig.client).twoFactorEnabled(), isTrue);
      final l = await ApiLimitsRepository(rig.client).limits();
      expect((l.bankMaximum, l.daily), (500000.0, 200000.0));
      expect((await ApiSupportRepository(rig.client).nearby()).single.name, 'Colombo Fort');
    });

    test('a limit the bank rejects surfaces as PaymentException', () async {
      final rig = Rig((_) => json({'code': 'limit_too_high', 'message': 'Above the bank maximum.'}, 422));
      await expectLater(
        ApiLimitsRepository(rig.client).setDaily(9e9),
        throwsA(isA<PaymentException>().having((e) => e.message, 'message', 'Above the bank maximum.')),
      );
    });
  });

  group('fixed deposits', () {
    Map<String, Object?> fd(String id, {String status = 'active', String maturity = '2027-11-01T00:00:00Z'}) => {
      'id': id, 'maskedNumber': '•••• 1234', 'principalMinor': 10000000, 'rate': 9.5, 'termMonths': 12, 'startDate': '2026-11-01T00:00:00Z',
      'maturityDate': maturity, 'renewal': 'renewWithInterest', 'fundingAccountId': 'a-sav', 'status': status, 'renewals': 1, 'paidOutMinor': 10950000,
    };

    test('parse, with active deposits first and the soonest maturity first', () async {
      final rig = Rig((_) => json({
        'items': [fd('later'), fd('done', status: 'matured'), fd('sooner', maturity: '2027-03-01T00:00:00Z')],
      }));
      final list = await ApiFixedDepositRepository(rig.client).deposits();
      expect(list.map((d) => d.id), ['sooner', 'later', 'done']);
      expect(list.first.principal, 100000);
      expect(list.first.rate, 9.5);
      expect(list.last.paidOut, 109500);
      expect(list.last.status, FdStatus.matured);
      expect(list.first.name, 'Fixed Deposit', reason: 'a missing name falls back');
    });

    test('opening sends minor units, the term and the renewal choice, with an idempotency key', () async {
      final rig = Rig((_) => json(fd('new')));
      await ApiFixedDepositRepository(rig.client).open(fromAccountId: 'a-sav', amount: 150000.5, termMonths: 36, renewal: FdRenewal.payOut);
      final sent = rig.adapter.requests.single;
      expect(sent.path, '/v1/fixed-deposits');
      expect(sent.data, {'fromAccountId': 'a-sav', 'amountMinor': 15000050, 'termMonths': 36, 'renewal': 'payOut'});
      expect((sent.headers['Idempotency-Key'] as String).length, 32);
    });

    test('a refusal keeps the bank’s words, and there is no call to edit a deposit', () async {
      var rig = Rig((_) => json({'code': 'insufficient_funds', 'message': 'Not enough in that account.'}, 422));
      await expectLater(
        ApiFixedDepositRepository(rig.client).open(fromAccountId: 'a', amount: 20000, termMonths: 12, renewal: FdRenewal.payOut),
        throwsA(isA<PaymentException>().having((e) => e.failure, 'failure', PaymentFailure.insufficientFunds).having((e) => e.message, 'message', 'Not enough in that account.')),
      );
      expect(rig.adapter.requests.map((r) => r.method).toSet(), {'POST'}, reason: 'nothing here ever sends PUT or DELETE for a deposit');
    });
  });
}
