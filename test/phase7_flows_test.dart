import 'package:bank_app/app/providers.dart';
import 'package:bank_app/app/router.dart';
import 'package:bank_app/core/network/api_exceptions.dart';
import 'package:bank_app/core/network/connectivity_service.dart';
import 'package:bank_app/core/theme/app_theme.dart';
import 'package:bank_app/features/authentication/data/mock_auth_repository.dart';
import 'package:bank_app/core/widgets/error_view.dart';
import 'package:bank_app/core/widgets/primary_button.dart';
import 'package:bank_app/features/dashboard/domain/banking_repositories.dart';
import 'package:bank_app/features/payments/presentation/payment_submission.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:bank_app/shared/models/payment_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

Future<TestEnv> dashboard(WidgetTester tester) async {
  useScreen(tester, const Size(390, 1600));
  final env = TestEnv();
  await openLogin(tester, env);
  await signInAsDemo(tester);
  return env;
}

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

class _FailingCards implements CardRepository {
  @override
  Future<List<BankCard>> cards() async => const [
    BankCard(id: 'c1', kind: CardKind.debit, network: CardNetwork.visa, holder: 'D P', last4: '4821', expiry: '09/28'),
  ];

  @override
  Future<void> setFrozen(String cardId, bool frozen) async => throw const NetworkException();

  @override
  Future<CardControls> controls(String cardId) async => throw const NetworkException();

  @override
  Future<void> updateControls(String cardId, CardControls controls) async => throw const NetworkException();

  @override
  Future<void> changePin(String cardId, {required String currentPin, required String newPin}) async => throw const NetworkException();

  @override
  Future<void> reportLostOrStolen(String cardId) async => throw const NetworkException();

  @override
  Future<BankCard> requestCard({required CardKind kind, required String accountId, required String holder, String? collectionBranch}) async => throw const NetworkException();

  @override
  Future<void> activateCard(String cardId) async => throw const NetworkException();
}

void main() {
  setUpAll(loadAppFont);

  group('Offline', () {
    testWidgets('a banner appears while offline and goes away on reconnect', (tester) async {
      final env = await dashboard(tester);
      expect(find.textContaining('You’re offline'), findsNothing);

      env.connectivity.set(false);
      await advance(tester, 100);
      await advance(tester, 300);
      expect(find.textContaining('You’re offline. Balances may be out of date'), findsOneWidget);
      // The page below must still be the dashboard, untouched.
      expect(find.text('Recent transactions'), findsOneWidget);

      env.connectivity.set(true);
      await advance(tester, 100);
      await advance(tester, 300);
      expect(find.textContaining('You’re offline'), findsNothing);
      await advance(tester, 1000); // data refetched on reconnect finishes its mock latency
    });

    testWidgets('payments cannot be confirmed while offline', (tester) async {
      final env = await dashboard(tester);
      final c = containerOf(tester);
      c.read(paymentDraftProvider.notifier).set(
        const PaymentDraft(kind: PaymentKind.bill, fromAccountId: 'a-sav', payee: 'Dialog', payeeDetail: '0771234567', amount: 100),
      );
      c.read(routerProvider).push('/pay/confirm');
      await advance(tester, 100);
      await advance(tester, 800);

      final confirm = find.widgetWithText(PrimaryButton, 'Confirm payment');
      expect(confirm, findsOneWidget);
      expect(tester.widget<PrimaryButton>(confirm).onPressed, isNotNull);

      env.connectivity.set(false);
      await advance(tester, 100);
      await advance(tester, 300);
      expect(tester.widget<PrimaryButton>(confirm).onPressed, isNull);
      expect(find.text('You’re offline. Reconnect to confirm this payment.'), findsOneWidget);
    });

    test('submitting while offline sends nothing and says so', () async {
      final connectivity = FakeConnectivity();
      final c = ProviderContainer(overrides: [connectivityServiceProvider.overrideWithValue(connectivity)]);
      addTearDown(c.dispose);
      c.read(onlineProvider);
      connectivity.set(false);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(onlineProvider), isFalse);

      final sub = c.listen(paymentSubmissionProvider, (_, _) {});
      await c.read(paymentSubmissionProvider.notifier).submit(
        const PaymentDraft(kind: PaymentKind.transfer, fromAccountId: 'a-sav', payee: 'Sam', payeeDetail: 'BOC', amount: 10),
      );
      expect(sub.read().phase, SubmitPhase.failed);
      expect(sub.read().message, contains('nothing was sent'));
      expect(c.read(ledgerProvider).transactions.where((t) => t.merchant == 'Sam'), isEmpty);
    });

    test('the platform service treats an unreadable connectivity state as online', () async {
      // No plugin is registered under `flutter test`, so the lookup throws.
      expect(await PlatformConnectivityService().isOnline(), isTrue);
    });
  });

  group('Maintenance', () {
    testWidgets('covers the app, retries against the health check, and then lets the customer back in', (tester) async {
      final env = await dashboard(tester);
      containerOf(tester).read(serviceStatusProvider.notifier).enterMaintenance(const MaintenanceException('Planned upgrade until 3am.', Duration(minutes: 30)));
      await advance(tester, 100);
      expect(find.text('We’ll be right back'), findsOneWidget);
      expect(find.text('Planned upgrade until 3am.'), findsOneWidget);
      expect(find.textContaining('about 30 minutes'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await advance(tester, 100);
      await advance(tester, 300);
      expect(env.health.checks, 1);
      expect(find.text('We’ll be right back'), findsOneWidget);
      expect(find.textContaining('Still unavailable'), findsOneWidget);

      env.health.up = true;
      await tester.tap(find.text('Try again'));
      await advance(tester, 100);
      await advance(tester, 700);
      expect(find.text('We’ll be right back'), findsNothing);
      expect(find.text('Recent transactions'), findsOneWidget);
    });
  });

  group('Session expiry', () {
    testWidgets('signs the customer out, explains why, and clears the note after the next sign-in', (tester) async {
      await dashboard(tester);
      final c = containerOf(tester);
      await c.read(authProvider.notifier).expireSession();
      await advance(tester, 100);
      await advance(tester, 800);

      expect(c.read(authProvider), isNull);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.textContaining('Your session expired'), findsOneWidget);

      await signInAsDemo(tester);
      expect(c.read(authNoticeProvider), isNull);
      expect(find.textContaining('Your session expired'), findsNothing);
    });
  });

  group('Card freeze', () {
    test('is rolled back, with no notification, when the bank refuses it', () async {
      final c = ProviderContainer(overrides: [cardRepositoryProvider.overrideWithValue(_FailingCards())]);
      addTearDown(c.dispose);
      await c.read(cardsProvider.future);
      final ok = await c.read(cardsProvider.notifier).toggleFreeze('c1');
      expect(ok, isFalse);
      expect(c.read(cardsProvider).value!.single.frozen, isFalse);
      expect((await c.read(notificationsProvider.future)).where((n) => n.title == 'Card frozen'), isEmpty);
    });

    test('sticks when the bank accepts it', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(authProvider.notifier).start(MockAuthRepository.demoUser);
      await c.read(cardsProvider.future);
      expect(await c.read(cardsProvider.notifier).toggleFreeze('c-1'), isTrue);
      expect(c.read(cardsProvider).value!.firstWhere((x) => x.id == 'c-1').frozen, isTrue);
    });
  });

  group('ErrorView', () {
    Future<void> show(WidgetTester tester, Object error, {VoidCallback? onRetry}) => tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: ErrorView(error: error, what: 'cards', onRetry: onRetry))),
    );

    testWidgets('offline errors tell the customer to check their connection', (tester) async {
      var retries = 0;
      await show(tester, const NetworkException(), onRetry: () => retries++);
      expect(find.text('Couldn’t load cards'), findsOneWidget);
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('server errors show a reference for support, never internals', (tester) async {
      await show(tester, const ServerException('Something went wrong on our side. Please try again.', 500, 'abc123'), onRetry: () {});
      expect(find.text('Reference abc123'), findsOneWidget);
    });

    testWidgets('an expired session offers no retry', (tester) async {
      await show(tester, const UnauthorizedException(), onRetry: () {});
      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining('session has expired'), findsOneWidget);
    });

    testWidgets('unknown errors never leak their text', (tester) async {
      await show(tester, StateError('SELECT * FROM secrets'), onRetry: () {});
      expect(find.textContaining('SELECT'), findsNothing);
      expect(find.text('Please try again.'), findsOneWidget);
    });
  });
}
