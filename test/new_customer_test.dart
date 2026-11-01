import 'package:bank_app/app/providers.dart';
import 'package:bank_app/app/router.dart';
import 'package:bank_app/core/security/secure_store.dart';
import 'package:bank_app/features/authentication/data/mock_auth_repository.dart';
import 'package:bank_app/shared/models/engagement_models.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:bank_app/shared/models/payment_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

Future<AppUser> register(MockAuthRepository repo, {double deposit = 25000, String username = 'nimal.f'}) => repo.register(
  fullName: 'Nimal Fernando',
  username: username,
  password: 'Nimal@12345',
  initialDeposit: deposit,
  profile: const {'email': 'nimal@example.com', 'mobile': '0771234567'},
);

void main() {
  setUpAll(loadAppFont);

  group('a customer who has just opened an account', () {
    late ProviderContainer c;
    late AppUser nimal;

    setUp(() async {
      c = ProviderContainer(overrides: [secureStoreProvider.overrideWithValue(MemorySecureStore())]);
      addTearDown(c.dispose);
      nimal = await register(MockAuthRepository(latency: Duration.zero));
      c.read(mockBankProvider).openAccount(nimal, deposit: 25000);
      c.read(authProvider.notifier).start(nimal);
    });

    test('has exactly one account holding the opening deposit, not the demo accounts', () async {
      final accounts = await c.read(accountsProvider.future);
      expect(accounts, hasLength(1));
      expect(accounts.single.name, 'Savings Account');
      expect(accounts.single.balance, 25000);
      expect(accounts.single.maskedNumber, isNot(contains('3021')));
    });

    test('history is the opening deposit only', () async {
      final txs = await c.read(transactionsProvider.future);
      expect(txs, hasLength(1));
      expect(txs.single.merchant, 'Opening deposit');
      expect(txs.single.amount, 25000);
    });

    test('a current account is opened when that was chosen', () async {
      final other = ProviderContainer();
      addTearDown(other.dispose);
      final user = await register(MockAuthRepository(latency: Duration.zero), username: 'sam.c');
      other.read(mockBankProvider).openAccount(user, deposit: 5000, type: AccountType.current);
      other.read(authProvider.notifier).start(user);
      final account = (await other.read(accountsProvider.future)).single;
      expect(account.type, AccountType.current);
      expect(account.name, 'Current Account');
    });

    test('a zero deposit leaves an empty history', () async {
      final other = ProviderContainer();
      addTearDown(other.dispose);
      final user = await register(MockAuthRepository(latency: Duration.zero), deposit: 0, username: 'zed');
      other.read(mockBankProvider).openAccount(user, deposit: 0);
      other.read(authProvider.notifier).start(user);
      expect(await other.read(transactionsProvider.future), isEmpty);
    });

    test('has no cards, beneficiaries, goals or loans', () async {
      expect(await c.read(cardsProvider.future), isEmpty);
      expect(await c.read(beneficiariesProvider.future), isEmpty);
      expect(await c.read(goalsProvider.future), isEmpty);
      expect(await c.read(loansProvider.future), isEmpty);
    });

    test('inbox holds only a welcome note, and only this device is signed in', () async {
      final inbox = await c.read(notificationsProvider.future);
      expect(inbox, hasLength(1));
      expect(inbox.single.title, startsWith('Welcome to Zentrix Bank, Nimal'));
      expect(inbox.single.category, NotifCategory.bankNotices);
      final sessions = await c.read(securityRepositoryProvider).sessions();
      expect(sessions.map((s) => s.current), [true]);
      // One entry: the sign-in that just happened — nothing from a past life.
      final history = await c.read(securityRepositoryProvider).loginHistory();
      expect(history, hasLength(1));
      expect(history.single.success, isTrue);
    });

    test('can only spend what they actually deposited', () async {
      final ledger = c.read(ledgerProvider);
      PaymentDraft pay(double amount) => PaymentDraft(
        kind: PaymentKind.transfer,
        fromAccountId: 'a-sav',
        payee: 'Sam',
        payeeDetail: 'Bank of Ceylon 7712340988',
        amount: amount,
      );
      expect(() => ledger.post(pay(40000)), throwsA(isA<PaymentException>().having((e) => e.failure, 'failure', PaymentFailure.insufficientFunds)));
      ledger.post(pay(10000));
      expect(ledger.accounts.single.balance, 15000);
      expect(ledger.transactions.first.amount, -10000);
    });

    test('customers are isolated: the demo customer is untouched, and each keeps their own changes across sign-out', () async {
      final ledgerNimal = c.read(ledgerProvider);
      ledgerNimal.post(const PaymentDraft(kind: PaymentKind.transfer, fromAccountId: 'a-sav', payee: 'Sam', payeeDetail: 'x 7712340988', amount: 1000));

      await c.read(authProvider.notifier).signOut(remote: false);
      c.read(authProvider.notifier).start(MockAuthRepository.demoUser);
      final demoAccounts = await c.read(accountsProvider.future);
      expect(demoAccounts, hasLength(3));
      expect(demoAccounts.first.balance, 428750);
      expect(await c.read(cardsProvider.future), hasLength(3));
      expect((await c.read(beneficiariesProvider.future)).length, 3);

      await c.read(authProvider.notifier).signOut(remote: false);
      c.read(authProvider.notifier).start(nimal);
      expect((await c.read(accountsProvider.future)).single.balance, 24000, reason: 'Nimal’s payment is still there');
      expect(await c.read(cardsProvider.future), isEmpty);
    });
  });

  testWidgets('After registering and signing in, every screen shows a new, empty account', (tester) async {
    useScreen(tester, const Size(390, 2000));
    final env = TestEnv();
    await openLogin(tester, env);
    // Register with the app's own repository so the sign-in below accepts these credentials.
    await tester.runAsync(() => register(env.repo as MockAuthRepository));
    final c = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    final user = (await tester.runAsync(() => env.repo.signIn('nimal.f', 'Nimal@12345')))!;
    c.read(mockBankProvider).openAccount(user, deposit: 25000);

    await signIn(tester, user: 'nimal.f', password: 'Nimal@12345');
    await advance(tester, 1500);

    expect(find.text('LKR 25,000.00'), findsWidgets);
    expect(find.text('Opening deposit'), findsOneWidget);
    expect(find.text('Savings Account'), findsOneWidget);
    expect(find.text('Current Account'), findsNothing);
    expect(find.text('Fixed Deposit'), findsNothing);
    expect(find.text('Starbucks'), findsNothing);
    expect(find.text('Welcome back, Dushan'), findsNothing);

    final router = c.read(routerProvider);
    router.go('/cards');
    await advance(tester, 100);
    await advance(tester, 900);
    expect(find.text('No cards yet'), findsOneWidget);

    router.push('/loans');
    await advance(tester, 100);
    await advance(tester, 900);
    expect(find.text('No loans'), findsOneWidget);
    router.pop();
    await advance(tester, 100);
    await advance(tester, 700);

    router.push('/savings');
    await advance(tester, 100);
    await advance(tester, 900);
    expect(find.text('No savings goals yet'), findsOneWidget);
    router.pop();
    await advance(tester, 100);
    await advance(tester, 700);

    router.push('/beneficiaries');
    await advance(tester, 100);
    await advance(tester, 900);
    expect(find.text('Nimal Perera'), findsNothing);
    expect(find.text('Kamala Silva'), findsNothing);
    await advance(tester, 1500);
  });
}
