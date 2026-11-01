import 'dart:convert';
import 'package:bank_app/core/network/api_client.dart';
import 'package:bank_app/core/network/api_config.dart';
import 'package:bank_app/core/network/api_exceptions.dart';
import 'package:bank_app/core/network/log_sanitizer.dart';
import 'package:bank_app/core/network/mappers.dart';
import 'package:bank_app/features/authentication/data/api_auth_repository.dart';
import 'package:bank_app/features/authentication/domain/auth_repository.dart';
import 'package:bank_app/features/payments/data/api_payment_repositories.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:bank_app/shared/models/payment_models.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'net_helpers.dart';

void main() {
  group('ApiConfig', () {
    test('requires https outside local debug servers', () {
      expect(() => ApiConfig(baseUrl: 'http://api.bank.test'), throwsArgumentError);
      expect(() => ApiConfig(baseUrl: 'not a url'), throwsArgumentError);
      expect(ApiConfig(baseUrl: 'https://api.bank.test').baseUrl, 'https://api.bank.test');
      expect(ApiConfig(baseUrl: 'http://10.0.2.2:8080', allowInsecureLoopback: true).baseUrl, 'http://10.0.2.2:8080');
      expect(() => ApiConfig(baseUrl: 'http://10.0.2.2:8080', allowInsecureLoopback: false), throwsArgumentError);
      expect(() => ApiConfig(baseUrl: 'http://evil.test', allowInsecureLoopback: true), throwsArgumentError);
    });

    test('no API_BASE_URL means mock mode', () => expect(ApiConfig.fromEnvironment(), isNull));

    test('certificate pins compare SHA-256 of the DER bytes', () {
      final der = utf8.encode('certificate');
      final pin = sha256.convert(der).toString();
      expect(certificateMatchesPins(der, [pin]), isTrue);
      expect(certificateMatchesPins(utf8.encode('another certificate'), [pin]), isFalse);
      expect(certificateMatchesPins(der, const []), isFalse);
    });
  });

  group('LogSanitizer', () {
    test('hides secrets, masks long numbers, keeps harmless fields', () {
      final out = LogSanitizer.body({
        'identifier': 'dushan',
        'password': 'Dushan@123',
        'refreshToken': 'abc',
        'nested': {'pin': '1234', 'accountNumber': '1234567890123', 'note': 'card 4111111111111111 ok'},
        'amountMinor': 5000,
      })! as Map;
      expect(out['password'], LogSanitizer.redacted);
      expect(out['refreshToken'], LogSanitizer.redacted);
      expect((out['nested'] as Map)['pin'], LogSanitizer.redacted);
      expect((out['nested'] as Map)['accountNumber'], LogSanitizer.redacted);
      expect((out['nested'] as Map)['note'], 'card ••••1111 ok');
      expect(out['amountMinor'], 5000);
      expect(LogSanitizer.headers({'Authorization': 'Bearer x', 'Accept': 'json'})['Authorization'], LogSanitizer.redacted);
      expect(LogSanitizer.uri(Uri.parse('https://a.test/v1/x?account=123&q=zzz')), 'https://a.test/v1/x?account&q');
    });
  });

  group('ApiClient', () {
    test('sends bearer token and a request id, and never logs the secrets', () async {
      final rig = Rig((_) => json({'ok': true}));
      rig.tokens.setAccessToken('ACCESS-SECRET');
      await rig.client.post('/v1/auth/login', body: {'identifier': 'dushan', 'password': 'Dushan@123'});
      final sent = rig.adapter.requests.single;
      expect(sent.headers['Authorization'], 'Bearer ACCESS-SECRET');
      expect((sent.headers['X-Request-Id'] as String).length, 32);
      final all = rig.logs.join('\n');
      expect(all, isNot(contains('ACCESS-SECRET')));
      expect(all, isNot(contains('Dushan@123')));
      expect(all, contains('dushan'));
    });

    test('unauthenticated calls carry no bearer token', () async {
      final rig = Rig((_) => json({}));
      rig.tokens.setAccessToken('t');
      await rig.client.post('/v1/auth/login', body: {}, authenticated: false);
      expect(rig.adapter.requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('a 401 refreshes once, rotates the stored token and replays the request', () async {
      var accounts = 0;
      final rig = Rig((o) {
        if (o.path == '/v1/auth/refresh') return json({'accessToken': 'new-access', 'refreshToken': 'rotated'});
        accounts++;
        return accounts == 1 ? json({'code': 'expired'}, 401) : json({'items': []});
      });
      await rig.sessions.saveRefreshToken('old');
      rig.tokens.setAccessToken('stale');
      final res = await rig.client.get('/v1/accounts');
      expect(res['items'], isEmpty);
      expect(rig.adapter.count('/v1/accounts'), 2);
      expect(rig.adapter.requests.last.headers['Authorization'], 'Bearer new-access');
      expect(await rig.sessions.refreshToken(), 'rotated');
      expect(rig.expired, 0);
    });

    test('concurrent 401s share a single refresh', () async {
      final rig = Rig((o) {
        if (o.path == '/v1/auth/refresh') return json({'accessToken': 'n', 'refreshToken': 'r2'});
        return o.headers['Authorization'] == 'Bearer n' ? json({'items': []}) : json({}, 401);
      });
      await rig.sessions.saveRefreshToken('r1');
      rig.tokens.setAccessToken('stale');
      await Future.wait([rig.client.get('/v1/accounts'), rig.client.get('/v1/cards'), rig.client.get('/v1/transactions')]);
      expect(rig.adapter.count('/v1/auth/refresh'), 1);
    });

    test('a failed refresh ends the session', () async {
      final rig = Rig((o) => o.path == '/v1/auth/refresh' ? json({'code': 'revoked'}, 401) : json({}, 401));
      await rig.sessions.saveRefreshToken('r1');
      rig.tokens.setAccessToken('stale');
      await expectLater(rig.client.get('/v1/accounts'), throwsA(isA<UnauthorizedException>()));
      expect(rig.expired, 1);
      expect(rig.tokens.accessToken, isNull);
    });

    test('maintenance is reported and not retried', () async {
      final rig = Rig((_) => json({'code': 'maintenance', 'message': 'Back at 3am.'}, 503, {'retry-after': ['600']}));
      await expectLater(rig.client.get('/v1/accounts'), throwsA(isA<MaintenanceException>().having((e) => e.retryAfter, 'retryAfter', const Duration(minutes: 10))));
      expect(rig.maintenance.single.message, 'Back at 3am.');
      expect(rig.adapter.requests, hasLength(1));
    });

    test('reads retry transient failures, then succeed', () async {
      var n = 0;
      final rig = Rig((_) => ++n < 3 ? json({'code': 'bad_gateway'}, 502) : json({'items': []}));
      await rig.client.get('/v1/cards');
      expect(rig.adapter.requests, hasLength(3));
    });

    test('writes are never retried', () async {
      final rig = Rig((_) => json({'code': 'bad_gateway'}, 502));
      await expectLater(rig.client.post('/v1/payments', body: {}), throwsA(isA<ServerException>()));
      expect(rig.adapter.requests, hasLength(1));
    });

    test('connection failures become NetworkException', () async {
      final rig = Rig((o) => throw DioException.connectionError(requestOptions: o, reason: 'no route'));
      await expectLater(rig.client.get('/v1/cards'), throwsA(isA<NetworkException>()));
      expect(rig.adapter.requests, hasLength(3)); // original + two retries
    });

    test('business rejections keep the server code and field errors', () async {
      final rig = Rig((_) => json({'code': 'validation', 'message': 'Fix the form.', 'fields': {'amount': 'Too small'}}, 422));
      await expectLater(
        rig.client.post('/v1/beneficiaries', body: {}),
        throwsA(isA<RejectedException>().having((e) => e.code, 'code', 'validation').having((e) => e.fieldErrors['amount'], 'field', 'Too small')),
      );
    });

    test('garbage responses become ServerException, not a crash', () async {
      final rig = Rig((_) => ResponseBody.fromString('[1,2,3]', 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]}));
      await expectLater(rig.client.get('/v1/accounts'), throwsA(isA<ServerException>()));
    });
  });

  group('mappers', () {
    test('convert minor units and enums', () {
      final a = accountFromJson({'id': 'a1', 'type': 'fixed_deposit', 'name': 'FD', 'maskedNumber': '•••• 1', 'balanceMinor': 1234567});
      expect(a.balance, 12345.67);
      expect(a.type, AccountType.fixedDeposit);
      expect(toMinor(19.99), 1999);
      final t = transactionFromJson({'id': 't', 'merchant': 'Keells', 'category': 'food', 'amountMinor': -250050, 'date': '2026-10-31T10:00:00Z', 'accountId': 'a1'});
      expect(t.amount, -2500.50);
      expect(t.category, TxCategory.food);
    });

    test('malformed payloads raise ServerException', () {
      expect(() => accountFromJson({'id': 'a1'}), throwsA(isA<ServerException>()));
      expect(() => accountFromJson({'id': 'a', 'type': 'bogus', 'name': 'n', 'maskedNumber': 'm', 'balanceMinor': 1}), throwsA(isA<ServerException>()));
      expect(() => items({'items': 'nope'}), throwsA(isA<ServerException>()));
    });

    test('payment bodies carry minor units and no client-chosen fee', () {
      final body = paymentToJson(const PaymentDraft(kind: PaymentKind.bill, fromAccountId: 'a1', payee: 'Dialog', payeeDetail: '0771234567', amount: 500, fee: 99));
      expect(body['amountMinor'], 50000);
      expect(body['kind'], 'bill');
      expect(body.containsKey('fee'), isFalse);
      expect(body.containsKey('feeMinor'), isFalse);
    });
  });

  group('ApiPaymentRepository', () {
    const draft = PaymentDraft(kind: PaymentKind.transfer, fromAccountId: 'a1', payee: 'Sam', payeeDetail: 'BOC', amount: 1000);
    Map<String, Object?> receipt() => {
      'id': 'r1', 'kind': 'transfer', 'status': 'completed', 'payee': 'Sam', 'amountMinor': 100000, 'feeMinor': 2500,
      'fromName': 'Savings', 'fromMasked': '•••• 1', 'date': '2026-11-01T08:00:00Z',
      'details': [{'label': 'Bank', 'value': 'BOC'}],
    };

    test('returns the server receipt, fee included', () async {
      final rig = Rig((_) => json(receipt()));
      final r = await ApiPaymentRepository(rig.client).pay(draft);
      expect(r.fee, 25);
      expect(r.total, 1025);
      expect(r.details.single, ('Bank', 'BOC'));
    });

    test('resending the same draft reuses the idempotency key; a different draft gets a new one', () async {
      final rig = Rig((_) => json(receipt()));
      final repo = ApiPaymentRepository(rig.client);
      await repo.pay(draft);
      await repo.pay(draft);
      await repo.pay(draft.withAccount('a2'));
      final keys = rig.adapter.requests.map((r) => r.headers['Idempotency-Key'] as String).toList();
      expect(keys[0], keys[1]);
      expect(keys[2], isNot(keys[0]));
    });

    test('server refusals become the failures the UI knows', () async {
      for (final (code, expected) in [
        ('insufficient_funds', PaymentFailure.insufficientFunds),
        ('invalid_recipient', PaymentFailure.invalidRecipient),
        ('limit_exceeded', PaymentFailure.limitExceeded),
        ('something_else', PaymentFailure.unavailable),
      ]) {
        final rig = Rig((_) => json({'code': code, 'message': 'No.'}, 422));
        await expectLater(ApiPaymentRepository(rig.client).pay(draft), throwsA(isA<PaymentException>().having((e) => e.failure, 'failure', expected)));
      }
    });

    test('a dropped connection never claims the payment failed cleanly', () async {
      final rig = Rig((o) => throw DioException.connectionError(requestOptions: o, reason: 'reset'));
      await expectLater(
        ApiPaymentRepository(rig.client).pay(draft),
        throwsA(isA<PaymentException>().having((e) => e.message, 'message', contains('Check your recent transactions'))),
      );
      expect(rig.adapter.requests, hasLength(1));
    });
  });

  group('ApiAuthRepository', () {
    Map<String, Object?> session() => {
      'accessToken': 'acc',
      'refreshToken': 'ref-1',
      'user': {'id': 'u1', 'fullName': 'Dushan Perera', 'firstName': 'Dushan', 'customerNumber': 'NC 1', 'email': 'd@x.test', 'phone': '+94771234567'},
    };

    test('signs in, keeps the access token in memory and hands out the refresh token once', () async {
      final rig = Rig((o) => json(session()));
      final repo = ApiAuthRepository(rig.client, rig.tokens);
      final user = await repo.signIn(' dushan ', 'pw');
      expect(user.firstName, 'Dushan');
      expect(rig.tokens.accessToken, 'acc');
      expect(rig.adapter.requests.single.data, {'identifier': 'dushan', 'password': 'pw'});
      expect(await repo.issueRefreshToken(user), 'ref-1');
      expect(await rig.sessions.refreshToken(), isNull, reason: 'persisting is the caller’s choice (remember me)');
    });

    test('bad credentials give a generic message; outages say so', () async {
      var rig = Rig((_) => json({'code': 'invalid_credentials'}, 401));
      await expectLater(
        ApiAuthRepository(rig.client, rig.tokens).signIn('x', 'y'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', 'Incorrect username or password.')),
      );
      expect(rig.expired, 0, reason: 'a failed login is not an expired session');

      rig = Rig((o) => throw DioException.connectionError(requestOptions: o, reason: 'down'));
      await expectLater(
        ApiAuthRepository(rig.client, rig.tokens).signIn('x', 'y'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('Can’t reach the bank'))),
      );
    });

    test('restoring a session rotates the refresh token and loads the user', () async {
      final rig = Rig((o) {
        if (o.path == '/v1/auth/refresh') return json({'accessToken': 'acc2', 'refreshToken': 'ref-2'});
        return json({'user': (session()['user'])});
      });
      await rig.sessions.saveRefreshToken('ref-1');
      final user = await ApiAuthRepository(rig.client, rig.tokens).restoreSession('ref-1');
      expect(user?.id, 'u1');
      expect(await rig.sessions.refreshToken(), 'ref-2');
    });

    test('a revoked refresh token restores nothing', () async {
      final rig = Rig((_) => json({'code': 'revoked'}, 401));
      await rig.sessions.saveRefreshToken('dead');
      expect(await ApiAuthRepository(rig.client, rig.tokens).restoreSession('dead'), isNull);
    });

    test('password reset requests look successful whatever happens', () async {
      final rig = Rig((_) => json({'code': 'nope'}, 404));
      await ApiAuthRepository(rig.client, rig.tokens).requestPasswordReset('ghost');
    });

    test('signing out clears the token even when the server is unreachable', () async {
      final rig = Rig((o) => throw DioException.connectionError(requestOptions: o, reason: 'down'));
      rig.tokens.setAccessToken('t');
      await ApiAuthRepository(rig.client, rig.tokens).signOut();
      expect(rig.tokens.accessToken, isNull);
    });
  });
}
