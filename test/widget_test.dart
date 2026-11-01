import 'package:bank_app/features/authentication/data/mock_auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUpAll(loadAppFont);

  testWidgets('Splash leads to onboarding, then login', (tester) async {
    useScreen(tester, const Size(390, 844));
    await openLogin(tester, TestEnv());
  });

  testWidgets('Login validates, rejects bad credentials and opens the dashboard', (tester) async {
    useScreen(tester, const Size(390, 844));
    await openLogin(tester, TestEnv());

    await tester.tap(find.text('Sign In'));
    await advance(tester, 300);
    expect(find.text('Username is required.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('identifier')), 'dushan');
    await tester.enterText(find.byKey(const ValueKey('password')), 'wrong');
    await tester.tap(find.text('Sign In'));
    await advance(tester, 1000);
    await advance(tester, 400);
    expect(find.text('Incorrect username or password.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('password')), MockAuthRepository.demoPassword);
    await tester.tap(find.text('Sign In'));
    await advance(tester, 1000);
    await advance(tester, 400);
    await advance(tester, 700);
    await advance(tester, 1500);
    expect(find.text('Total balance'), findsOneWidget);
    expect(find.text('LKR 1,763,950.00'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Dialog Axiata'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Dialog Axiata'), findsOneWidget);
  });

  testWidgets('Balance can be hidden and shown again', (tester) async {
    useScreen(tester, const Size(390, 844));
    await openLogin(tester, TestEnv());
    await signInAsDemo(tester);

    await tester.tap(find.byTooltip('Hide balances'));
    await advance(tester, 100); // animation starts on this frame
    await advance(tester, 500);
    expect(find.text('LKR 1,763,950.00'), findsNothing);
    expect(find.text('LKR ••••••••'), findsOneWidget);

    await tester.tap(find.byTooltip('Show balances'));
    await advance(tester, 1500);
    expect(find.text('LKR 1,763,950.00'), findsOneWidget);
  });

  testWidgets('A card can be frozen from the Cards tab', (tester) async {
    useScreen(tester, const Size(390, 844));
    await openLogin(tester, TestEnv());
    await signInAsDemo(tester);

    await tester.tap(find.text('Cards'));
    await advance(tester, 300);
    await advance(tester, 1000);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await advance(tester, 500);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('Card •••• 4821 frozen'), findsOneWidget);
  });

  testWidgets('Logging out asks for confirmation and returns to login', (tester) async {
    useScreen(tester, const Size(390, 844));
    await openLogin(tester, TestEnv());
    await signInAsDemo(tester);

    await tester.tap(find.text('Profile'));
    await advance(tester, 500);
    await tester.tap(find.text('Log out'));
    await advance(tester, 500);
    expect(find.text('Are you sure you want to log out?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await advance(tester, 600);
    await advance(tester, 600);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  for (final size in const [Size(360, 800), Size(412, 915), Size(430, 932), Size(320, 640)]) {
    testWidgets('Login and dashboard lay out without overflow at ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      useScreen(tester, size);
      await openLogin(tester, TestEnv());
      await signInAsDemo(tester);
      expect(find.text('Total balance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
