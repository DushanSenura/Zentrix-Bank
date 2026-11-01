import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

const _pin = '246813';

Future<void> pick(WidgetTester tester, String label, String option) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.tap(find.text(label).first);
  await advance(tester, 300);
  await tester.tap(find.text(option).last);
  await advance(tester, 300);
}

Future<void> fill(WidgetTester tester, Map<String, String> values) async {
  for (final e in values.entries) {
    await tester.enterText(find.byKey(ValueKey(e.key)), e.value);
  }
}

Future<void> next(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
  await advance(tester, 100);
  await advance(tester, 500);
}

Future<void> setPin(WidgetTester tester) async {
  await tapPin(tester, _pin);
  await advance(tester, 500);
  expect(find.text('Confirm your PIN'), findsOneWidget);
  await tapPin(tester, _pin);
  await advance(tester, 700);
}

void main() {
  setUpAll(loadAppFont);

  testWidgets('Registration: validates each step, then creates an account and offers PIN setup', (tester) async {
    useScreen(tester, const Size(390, 2400));
    await openLogin(tester, TestEnv());
    await tester.tap(find.text('Create account'));
    await advance(tester, 100);
    await advance(tester, 500);
    expect(find.text('Personal information'), findsOneWidget);

    // Nothing filled in: blocked with inline errors.
    await next(tester);
    expect(find.text('Full name is required.'), findsOneWidget);
    expect(find.text('Personal information'), findsOneWidget);

    await fill(tester, {'fullName': 'Nimal Fernando', 'idNumber': '200012345678', 'occupation': 'Engineer'});
    await tester.tap(find.byKey(const ValueKey('dob')));
    await advance(tester, 400);
    await tester.tap(find.text('OK'));
    await advance(tester, 400);
    await next(tester);
    expect(find.text('Contact information'), findsOneWidget);

    await fill(tester, {
      'mobile': '0771234567',
      'email': 'nimal@example.com',
      'address': '12 Lake Road',
      'city': 'Colombo',
      'postalCode': '10100',
    });
    await pick(tester, 'Province', 'Western');
    await next(tester);
    expect(find.text('Banking information'), findsOneWidget);

    await fill(tester, {'initialDeposit': '500'});
    await next(tester);
    expect(find.text('The minimum opening deposit is LKR 1000.'), findsOneWidget);
    await fill(tester, {'initialDeposit': '5000'});
    await pick(tester, 'Source of funds', 'Salary');
    await pick(tester, 'Employment status', 'Employed');
    await pick(tester, 'Estimated monthly income', 'LKR 100,000 – 250,000');
    await pick(tester, 'Purpose of account', 'Personal banking');
    await next(tester);
    expect(find.text('Verify your identity'), findsOneWidget);

    // Identity must be completed before continuing.
    await next(tester);
    expect(find.text('Please complete all three verification items.'), findsOneWidget);
    for (final doc in ['NIC / passport', 'Selfie check', 'Proof of address']) {
      await tester.tap(find.text(doc));
      await advance(tester, 100);
      await advance(tester, 800);
    }
    await next(tester);
    expect(find.text('Review & secure'), findsOneWidget);
    expect(find.text('Nimal Fernando'), findsOneWidget);
    expect(find.textContaining('•'), findsWidgets); // ID is masked
    expect(find.text('200012345678'), findsNothing);

    await tester.tap(find.text('Create Account'));
    await advance(tester, 300);
    expect(find.text('Username is required.'), findsOneWidget);

    await fill(tester, {'username': 'nimal.f', 'newPassword': 'Nimal@12345', 'confirmPassword': 'Nimal@12345'});
    await tester.tap(find.text('Create Account'));
    await advance(tester, 300);
    expect(find.text('Please accept both to continue.'), findsOneWidget);

    for (final box in find.byType(Checkbox).evaluate().toList()) {
      await tester.tap(find.byWidget(box.widget));
    }
    await tester.tap(find.text('Create Account'));
    await advance(tester, 1000);
    await advance(tester, 800);
    expect(find.text('Welcome, Nimal'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await advance(tester, 100);
    await advance(tester, 700);
    expect(find.text('Create your PIN'), findsOneWidget);
  });

  testWidgets('PIN setup rejects weak and mismatched PINs, then unlocks on relaunch', (tester) async {
    useScreen(tester, const Size(390, 844));
    final env = TestEnv();
    await openLogin(tester, env);
    await signIn(tester, remember: true);
    expect(find.text('Create your PIN'), findsOneWidget);

    await tapPin(tester, '111111');
    await advance(tester, 100);
    expect(find.textContaining('too easy to guess'), findsOneWidget);
    await advance(tester, 600);

    await tapPin(tester, _pin);
    await advance(tester, 500);
    await tapPin(tester, '246810');
    await advance(tester, 100);
    expect(find.textContaining('didn’t match'), findsOneWidget);
    await advance(tester, 600);

    await setPin(tester);
    await advance(tester, 1500);
    expect(find.text('Total balance'), findsOneWidget);

    // Relaunch: the stored session is gated by the PIN.
    await relaunch(tester, env);
    expect(find.text('Enter your PIN'), findsOneWidget);

    await tapPin(tester, '135790');
    await advance(tester, 100);
    expect(find.text('Incorrect PIN. 4 attempts left.'), findsOneWidget);
    await advance(tester, 600);

    await tapPin(tester, _pin);
    await advance(tester, 800);
    await advance(tester, 1500);
    expect(find.text('Total balance'), findsOneWidget);
  });

  testWidgets('Five wrong PINs wipe the stored session and require the password', (tester) async {
    useScreen(tester, const Size(390, 844));
    final env = TestEnv();
    await openLogin(tester, env);
    await signIn(tester, remember: true);
    await setPin(tester);
    await relaunch(tester, env);

    for (var i = 0; i < 5; i++) {
      await tapPin(tester, '135790');
      await advance(tester, 100);
      await advance(tester, 600);
    }
    await advance(tester, 600);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(await env.store.read('refresh_token'), isNull);
    expect(await env.store.read('pin_hash'), isNull);
  });

  testWidgets('Skipping PIN setup discards the stored token', (tester) async {
    useScreen(tester, const Size(390, 844));
    final env = TestEnv();
    await openLogin(tester, env);
    await signIn(tester, remember: true);
    await tester.tap(find.text('Skip for now'));
    await advance(tester, 100);
    await advance(tester, 700);
    await advance(tester, 1500);
    expect(find.text('Total balance'), findsOneWidget);
    expect(await env.store.read('refresh_token'), isNull);
  });

  testWidgets('Biometrics: enabled during setup, then unlock without typing a PIN', (tester) async {
    useScreen(tester, const Size(390, 844));
    final env = TestEnv(biometrics: FakeBiometrics(available: true));
    await openLogin(tester, env);
    await signIn(tester, remember: true);
    await setPin(tester);
    expect(find.text('Unlock with biometrics?'), findsOneWidget);
    await tester.tap(find.text('Enable biometrics'));
    await advance(tester, 100);
    await advance(tester, 700);
    await advance(tester, 1500);
    expect(find.text('Total balance'), findsOneWidget);
    expect(await env.store.read('biometric_enabled'), 'true');

    await relaunch(tester, env);
    await advance(tester, 1500);
    expect(find.text('Total balance'), findsOneWidget);
  });

  testWidgets('Forgot password: code, new password rules, then sign in with it', (tester) async {
    useScreen(tester, const Size(390, 1000));
    final env = TestEnv();
    await openLogin(tester, env);
    await tester.tap(find.text('Forgot password?'));
    await advance(tester, 100);
    await advance(tester, 500);
    expect(find.text('Forgot password?'), findsOneWidget);

    await fill(tester, {'resetIdentifier': 'dushan'});
    await tester.tap(find.text('Send code'));
    await advance(tester, 1000);
    await advance(tester, 500);
    expect(find.text('Reset your password'), findsOneWidget);

    await fill(tester, {'resetCode': '000000', 'resetPassword': 'NewPass@123', 'resetConfirm': 'NewPass@123'});
    await tester.tap(find.text('Reset password'));
    await advance(tester, 1000);
    await advance(tester, 300);
    expect(find.text('That code is invalid or has expired.'), findsOneWidget);

    await fill(tester, {'resetCode': '123456'});
    await tester.tap(find.text('Reset password'));
    await advance(tester, 1000);
    await advance(tester, 700);
    expect(find.text('Password updated'), findsOneWidget);

    await tester.tap(find.text('Back to sign in'));
    await advance(tester, 100);
    await advance(tester, 700);
    await signIn(tester, password: 'NewPass@123');
    await advance(tester, 1500);
    expect(find.text('Total balance'), findsOneWidget);
  });

  testWidgets('New screens lay out without overflow on a small phone with large text', (tester) async {
    useScreen(tester, const Size(320, 640));
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final env = TestEnv();
    await openLogin(tester, env);
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await advance(tester, 100);
    await advance(tester, 600);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Back'));
    await advance(tester, 100);
    await advance(tester, 600);
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await advance(tester, 100);
    await advance(tester, 600);
    expect(find.text('Personal information'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
