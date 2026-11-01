import 'package:bank_app/app/providers.dart';
import 'package:bank_app/app/router.dart';
import 'package:bank_app/core/security/pin_hasher.dart';
import 'package:bank_app/core/security/secure_store.dart';
import 'package:bank_app/core/security/session_store.dart';
import 'package:bank_app/core/widgets/pin_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Finds the PIN dots by counting them: one per digit of the expected length.
int dotCount(WidgetTester tester) => tester.widget<PinInput>(find.byType(PinInput)).length;

void main() {
  setUpAll(loadAppFont);

  group('SessionStore', () {
    test('remembers whether the PIN has 4 or 6 digits, and verifies either', () async {
      final store = SessionStore(MemorySecureStore());
      expect(await store.pinLength(), 6, reason: 'default before a PIN exists');

      await store.setPin('2580');
      expect(await store.pinLength(), 4);
      expect(await store.verifyPin('2580'), isTrue);
      expect(await store.verifyPin('2581'), isFalse);

      await store.setPin('135790');
      expect(await store.pinLength(), 6);
      expect(await store.verifyPin('135790'), isTrue);
      expect(await store.verifyPin('2580'), isFalse, reason: 'the old 4-digit PIN no longer works');
    });

    test('refuses lengths other than 4 or 6, and never stores the PIN itself', () async {
      final mem = MemorySecureStore();
      final store = SessionStore(mem);
      for (final bad in ['', '123', '12345', '1234567', '12a4', '１２３４']) {
        await expectLater(store.setPin(bad), throwsArgumentError, reason: bad);
      }
      expect(await store.hasPin(), isFalse);
      await store.setPin('2580');
      for (final key in ['pin_hash', 'pin_salt', 'pin_length']) {
        expect(await mem.read(key), isNot(contains('2580')), reason: key);
      }
    });

    test('clearing the session forgets the length too', () async {
      final store = SessionStore(MemorySecureStore());
      await store.setPin('2580');
      await store.clear();
      expect(await store.pinLength(), 6);
      expect(await store.hasPin(), isFalse);
    });
  });

  test('weak 4-digit PINs are rejected like weak 6-digit ones', () {
    for (final weak in ['0000', '1111', '1234', '4321', '0123', '9876', '123456', '111111']) {
      expect(PinHasher.isWeak(weak), isTrue, reason: weak);
    }
    for (final ok in ['2580', '1357', '7391', '135790', '246813']) {
      expect(PinHasher.isWeak(ok), isFalse, reason: ok);
    }
  });

  testWidgets('Choose a 4-digit PIN: setup, relaunch unlock with 4 dots, then change it to 6 digits', (tester) async {
    useScreen(tester, const Size(390, 900));
    final env = TestEnv();
    await openLogin(tester, env);
    await signIn(tester, remember: true);

    // Setup: defaults to 6, switch to 4.
    expect(find.text('Create your PIN'), findsOneWidget);
    expect(dotCount(tester), 6);
    expect(find.textContaining('Choose a 6-digit PIN'), findsOneWidget);
    await tester.tap(find.text('4 digits'));
    await advance(tester, 300);
    expect(dotCount(tester), 4);
    expect(find.textContaining('Choose a 4-digit PIN'), findsOneWidget);

    await tapPin(tester, '1234');
    await advance(tester, 100);
    expect(find.textContaining('too easy to guess'), findsOneWidget);
    await advance(tester, 600);
    await tapPin(tester, '2580');
    await advance(tester, 500);
    expect(find.text('Confirm your PIN'), findsOneWidget);
    expect(find.text('4 digits'), findsNothing, reason: 'the length can only change while choosing');
    await tapPin(tester, '2580');
    await advance(tester, 700);
    await advance(tester, 1500);
    expect(find.text('Total balance'), findsOneWidget);

    // Relaunch: the unlock screen asks for exactly four digits.
    await relaunch(tester, env);
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(dotCount(tester), 4);
    await tapPin(tester, '1357');
    await advance(tester, 100);
    expect(find.text('Incorrect PIN. 4 attempts left.'), findsOneWidget);
    await advance(tester, 600);
    await tapPin(tester, '2580');
    await advance(tester, 800);
    await advance(tester, 1500);
    expect(find.text('Total balance'), findsOneWidget);

    // Change it to 6 digits from the Security centre.
    final c = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    c.read(routerProvider).push('/security/pin');
    await advance(tester, 100);
    await advance(tester, 800);
    expect(find.text('Enter your current PIN'), findsOneWidget);
    expect(dotCount(tester), 4);
    await tapPin(tester, '2580');
    await advance(tester, 100);
    await advance(tester, 600);
    expect(find.text('Choose a new PIN'), findsOneWidget);
    expect(dotCount(tester), 4, reason: 'the picker starts at the current length');
    await tester.tap(find.text('6 digits'));
    await advance(tester, 300);
    expect(dotCount(tester), 6);
    await tapPin(tester, '246813');
    await advance(tester, 100);
    await advance(tester, 600);
    expect(find.text('Confirm your new PIN'), findsOneWidget);
    await tapPin(tester, '246813');
    await advance(tester, 1200);
    await advance(tester, 1000);

    final store = c.read(sessionStoreProvider);
    expect(await tester.runAsync(store.pinLength), 6);
    expect(await tester.runAsync(() => store.verifyPin('246813')), isTrue);
    expect(await tester.runAsync(() => store.verifyPin('2580')), isFalse);
    await advance(tester, 3000);
  });

  testWidgets('A payment is authorised with a 4-digit PIN when that is the chosen length', (tester) async {
    useScreen(tester, const Size(390, 2000));
    final env = TestEnv();
    await tester.runAsync(() => SessionStore(env.store).setPin('2580'));
    await openLogin(tester, env);
    await signInAsDemo(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    c.read(routerProvider).push('/loans');
    await advance(tester, 100);
    await advance(tester, 900);
    await advance(tester, 700);

    await tester.tap(find.text('Pay instalment').first);
    await advance(tester, 100);
    await advance(tester, 700);
    await tester.tap(find.text('Continue'));
    await advance(tester, 100);
    await advance(tester, 800);
    await tester.ensureVisible(find.text('Confirm payment'));
    await tester.tap(find.text('Confirm payment'));
    await advance(tester, 100);
    await advance(tester, 700);

    expect(find.text('Authorise payment'), findsOneWidget, reason: 'a PIN already exists, so no creation step');
    expect(dotCount(tester), 4);
    await tapPin(tester, '1357'); // wrong
    await advance(tester, 100);
    expect(find.text('Incorrect PIN. 2 attempts left.'), findsOneWidget);
    await advance(tester, 600);
    await tapPin(tester, '2580');
    await advance(tester, 500);
    await advance(tester, 700);
    await advance(tester, 1800);
    await advance(tester, 800);
    expect(find.text('Loan Payment Successful'), findsOneWidget);
    await advance(tester, 3000);
  });
}
