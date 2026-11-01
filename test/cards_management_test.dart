import 'package:bank_app/app/providers.dart';
import 'package:bank_app/features/cards/presentation/card_pin_page.dart';
import 'package:bank_app/features/dashboard/data/mock_banking_repositories.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

Future<void> dashboard(WidgetTester tester) async {
  useScreen(tester, const Size(390, 1800));
  final env = TestEnv();
  await openLogin(tester, env);
  await signInAsDemo(tester);
}

Future<void> openCardsTab(WidgetTester tester) async {
  await tester.tap(find.text('Cards').last);
  await advance(tester, 100);
  await advance(tester, 900);
  await advance(tester, 700);
}

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

void main() {
  setUpAll(loadAppFont);

  group('MockCardRepository', () {
    test('a limit above the bank maximum is refused and the old limit stays', () async {
      final repo = MockCardRepository();
      final before = await repo.controls('c-1');
      await expectLater(repo.updateControls('c-1', before.copyWith(dailyLimit: before.maxDailyLimit + 1000)), throwsA(isA<CardException>()));
      expect((await repo.controls('c-1')).dailyLimit, before.dailyLimit);
    });

    test('controls persist per card', () async {
      final repo = MockCardRepository();
      await repo.updateControls('c-1', (await repo.controls('c-1')).copyWith(dailyLimit: 20000, internationalEnabled: true));
      final c1 = await repo.controls('c-1');
      expect(c1.dailyLimit, 20000);
      expect(c1.internationalEnabled, isTrue);
      expect((await repo.controls('c-2')).internationalEnabled, isFalse);
    });

    test('changing the PIN needs the current one and a 4-digit new one', () async {
      final repo = MockCardRepository();
      await expectLater(repo.changePin('c-1', currentPin: '0000', newPin: '2580'), throwsA(isA<CardException>()));
      await expectLater(repo.changePin('c-1', currentPin: MockCardRepository.demoCardPin, newPin: '25'), throwsA(isA<CardException>()));
      await repo.changePin('c-1', currentPin: MockCardRepository.demoCardPin, newPin: '2580');
      await expectLater(repo.changePin('c-1', currentPin: MockCardRepository.demoCardPin, newPin: '1357'), throwsA(isA<CardException>()), reason: 'the old PIN no longer works');
      await repo.changePin('c-1', currentPin: '2580', newPin: '1357');
    });

    test('a card reported lost is blocked for good: no freeze, limits or PIN changes', () async {
      final repo = MockCardRepository();
      await repo.setFrozen('c-1', true);
      await repo.reportLostOrStolen('c-1');
      final card = (await repo.cards()).firstWhere((c) => c.id == 'c-1');
      expect(card.blocked, isTrue);
      expect(card.frozen, isFalse, reason: 'blocked supersedes frozen');
      await expectLater(repo.setFrozen('c-1', false), throwsA(isA<CardException>()));
      await expectLater(repo.updateControls('c-1', (await repo.controls('c-1'))), throwsA(isA<CardException>()));
      await expectLater(repo.changePin('c-1', currentPin: '4821', newPin: '2580'), throwsA(isA<CardException>()));
      expect((await repo.cards()).firstWhere((c) => c.id == 'c-2').blocked, isFalse);
    });

    test('unknown cards are refused rather than ignored', () async {
      await expectLater(MockCardRepository().setFrozen('nope', true), throwsA(isA<CardException>()));
    });
  });

  test('weak card PINs: repeats and sequences', () {
    for (final weak in ['1111', '0000', '1234', '4321', '2345', '9876']) {
      expect(isWeakCardPin(weak), isTrue, reason: weak);
    }
    for (final ok in ['2580', '1357', '4821', '7391']) {
      expect(isWeakCardPin(ok), isFalse, reason: ok);
    }
  });

  testWidgets('Cards screen offers real actions instead of "coming soon"', (tester) async {
    await dashboard(tester);
    await openCardsTab(tester);
    expect(find.text('Limits & online use'), findsOneWidget);
    expect(find.text('Change card PIN'), findsOneWidget);
    expect(find.text('Report lost or stolen'), findsOneWidget);
    expect(find.text('Coming soon'), findsNothing);
  });

  testWidgets('Change card PIN: wrong current PIN is explained, then the change succeeds', (tester) async {
    await dashboard(tester);
    await openCardsTab(tester);
    await tester.tap(find.text('Change card PIN'));
    await advance(tester, 100);
    await advance(tester, 800);
    expect(find.text('Enter your current card PIN'), findsOneWidget);

    await tapPin(tester, '1111'); // wrong current PIN
    await advance(tester, 100);
    await tapPin(tester, '2580');
    await advance(tester, 100);
    await tapPin(tester, '2580');
    await advance(tester, 1200);
    expect(find.text('The current card PIN is incorrect.'), findsOneWidget);
    expect(find.text('Enter your current card PIN'), findsOneWidget);

    await advance(tester, 600);
    await tapPin(tester, MockCardRepository.demoCardPin);
    await advance(tester, 100);
    expect(find.text('Choose a new card PIN'), findsOneWidget);
    await tapPin(tester, '1234'); // weak
    await advance(tester, 100);
    expect(find.textContaining('too easy to guess'), findsOneWidget);
    await advance(tester, 600);
    await tapPin(tester, '2580');
    await advance(tester, 100);
    expect(find.text('Confirm your new card PIN'), findsOneWidget);
    await tapPin(tester, '2580');
    await advance(tester, 1000);
    await advance(tester, 1000);
    expect(find.text('Card PIN updated.'), findsWidgets);

    final c = containerOf(tester);
    final inbox = (await tester.runAsync(() => c.read(notificationsProvider.future)))!;
    expect(inbox.where((n) => n.title == 'Card PIN changed'), hasLength(1));
    // The PIN itself must not appear in the notification.
    expect(inbox.any((n) => n.body.contains('2580')), isFalse);
  });

  testWidgets('Turning online payments off is saved without asking for the PIN', (tester) async {
    await dashboard(tester);
    await openCardsTab(tester);
    await tester.tap(find.text('Limits & online use'));
    await advance(tester, 100);
    await advance(tester, 900);
    expect(find.text('Daily spending limit'), findsWidgets);

    await tester.tap(find.text('Online payments'));
    await advance(tester, 200);
    await tester.tap(find.text('Save'));
    await advance(tester, 100);
    await advance(tester, 900);
    await advance(tester, 700);
    expect(find.text('Card controls saved.'), findsWidgets);

    final c = containerOf(tester);
    // The mock bank answers on real timers, which the widget test clock doesn't advance.
    final saved = await tester.runAsync(() => c.read(cardRepositoryProvider).controls('c-1'));
    expect(saved!.onlineEnabled, isFalse);
  });
}
