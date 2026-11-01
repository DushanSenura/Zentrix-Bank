import 'package:bank_app/app/providers.dart';
import 'package:bank_app/app/router.dart';
import 'package:bank_app/features/authentication/data/mock_auth_repository.dart';
import 'package:bank_app/features/authentication/domain/auth_repository.dart';
import 'package:bank_app/shared/models/engagement_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

const _pin = '246813';

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

Future<TestEnv> dashboard(WidgetTester tester, {Size size = const Size(390, 2000)}) async {
  useScreen(tester, size);
  final env = TestEnv();
  await openLogin(tester, env);
  await signInAsDemo(tester);
  return env;
}

/// The demo customer has no transaction PIN yet, so the first authorisation creates one.
Future<void> createPinInSheet(WidgetTester tester) async {
  expect(find.text('Create a transaction PIN'), findsOneWidget);
  await tapPin(tester, _pin);
  await advance(tester, 300);
  await tapPin(tester, _pin);
  await advance(tester, 500);
  await advance(tester, 700);
}

void main() {
  setUpAll(loadAppFont);

  group('MockAuthRepository.updateContact', () {
    test('changes only email and phone, and later sign-ins see the new details', () async {
      final repo = MockAuthRepository(latency: Duration.zero);
      final updated = await repo.updateContact(userId: MockAuthRepository.demoUser.id, email: 'new@example.com', phone: '+94 71 000 1111');
      expect(updated.email, 'new@example.com');
      expect(updated.phone, '+94 71 000 1111');
      expect(updated.fullName, MockAuthRepository.demoUser.fullName);
      expect(updated.customerNumber, MockAuthRepository.demoUser.customerNumber);
      expect((await repo.signIn('dushan', 'Dushan@123')).email, 'new@example.com');
    });

    test('refuses an email that belongs to another customer, and unknown profiles', () async {
      final repo = MockAuthRepository(latency: Duration.zero);
      final other = await repo.register(fullName: 'Sam Cooray', username: 'sam.c', password: 'Sam@123456', initialDeposit: 5000, profile: const {'email': 'sam@example.com'});
      await expectLater(
        repo.updateContact(userId: other.id, email: 'DUSHAN@example.com', phone: '0771234567'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('already used'))),
      );
      await expectLater(repo.updateContact(userId: 'nope', email: 'a@b.co', phone: '0771234567'), throwsA(isA<AuthException>()));
    });
  });

  testWidgets('Personal details: validation, PIN check, then the new details show everywhere', (tester) async {
    await dashboard(tester);
    final c = containerOf(tester);
    c.read(routerProvider).push('/profile/edit');
    await advance(tester, 100);
    await advance(tester, 900);
    expect(find.text('Dushan Perera'), findsOneWidget);
    expect(find.text('NC 1029 3847'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('profileEmail')), 'not-an-email');
    await tester.tap(find.text('Save changes'));
    await advance(tester, 300);
    expect(find.text('Enter a valid email address.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('profileEmail')), 'dushan.new@example.com');
    await tester.enterText(find.byKey(const ValueKey('profilePhone')), '0712223344');
    await tester.tap(find.text('Save changes'));
    await advance(tester, 100);
    await advance(tester, 700);
    expect(find.text('Confirm your new details'), findsNothing, reason: 'the first authorisation creates a PIN');
    await createPinInSheet(tester);
    await advance(tester, 1200);
    await advance(tester, 1000);

    final user = c.read(authProvider)!;
    expect(user.email, 'dushan.new@example.com');
    expect(user.phone, '0712223344');
    expect(user.fullName, 'Dushan Perera');
    final history = await tester.runAsync(() => c.read(securityRepositoryProvider).loginHistory());
    expect(history!.where((e) => e.success).length, lessThanOrEqualTo(4), reason: 'editing details is not a new sign-in');
    final inbox = (await tester.runAsync(() => c.read(notificationsProvider.future)))!;
    expect(inbox.where((n) => n.title == 'Contact details changed' && n.category == NotifCategory.security), hasLength(1));
    // The change is also what the profile screen shows.
    c.read(routerProvider).go('/profile');
    await advance(tester, 100);
    await advance(tester, 900);
    expect(find.text('dushan.new@example.com'), findsOneWidget);
    await advance(tester, 4500);
  });

  testWidgets('Personal details: saving without changes does not ask for a PIN', (tester) async {
    await dashboard(tester);
    final c = containerOf(tester);
    c.read(routerProvider).push('/profile/edit');
    await advance(tester, 100);
    await advance(tester, 900);
    await tester.tap(find.text('Save changes'));
    await advance(tester, 100);
    await advance(tester, 700);
    expect(find.text('Create a transaction PIN'), findsNothing);
    expect(find.text('Personal details'), findsNothing, reason: 'it simply closed');
  });
}
