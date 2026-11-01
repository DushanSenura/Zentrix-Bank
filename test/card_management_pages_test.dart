import 'package:bank_app/app/providers.dart';
import 'package:bank_app/app/router.dart';
import 'package:bank_app/features/cards/presentation/card_management_pages.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

Future<ProviderContainer> signedIn(WidgetTester tester) async {
  useScreen(tester, const Size(390, 2600));
  await openLogin(tester, TestEnv());
  await signInAsDemo(tester);
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
}

Future<void> go(WidgetTester tester, ProviderContainer c, String route) async {
  c.read(routerProvider).push(route);
  await advance(tester, 100);
  await advance(tester, 900);
  await advance(tester, 700);
}

void main() {
  setUpAll(loadAppFont);

  test('blocked outranks frozen, and every status has a label', () {
    const base = BankCard(id: 'c', kind: CardKind.debit, network: CardNetwork.visa, holder: 'X', last4: '1111', expiry: '01/30');
    expect(cardStatusOf(base.copyWith(frozen: true)), CardStatus.frozen);
    expect(cardStatusOf(base.copyWith(blocked: true)), CardStatus.blocked);
    expect(cardStatusOf(base.copyWith(blocked: true, frozen: true)), CardStatus.blocked);
    for (final s in CardStatus.values) {
      expect(cardStatusLabel(s), isNotEmpty);
    }
  });

  testWidgets('The Payments grid and the home shortcut open Card management; top-up is gone', (tester) async {
    final c = await signedIn(tester);
    expect(find.text('My cards'), findsOneWidget);
    expect(find.text('Top Up'), findsNothing);

    await tester.tap(find.text('My cards'));
    await advance(tester, 100);
    await advance(tester, 900);
    await advance(tester, 700);
    expect(find.text('Card management'), findsOneWidget);
    c.read(routerProvider).pop();
    await advance(tester, 100);
    await advance(tester, 700);

    c.read(routerProvider).go('/payments');
    await advance(tester, 100);
    await advance(tester, 900);
    expect(find.text('Top-up'), findsNothing);
    expect(find.text('Card management'), findsOneWidget);
    await tester.tap(find.text('Card management'));
    await advance(tester, 100);
    await advance(tester, 900);
    await advance(tester, 700);
    expect(find.text('3 cards · all active'), findsOneWidget);
  });

  testWidgets('The list shows every card with its status, and frozen ones need attention', (tester) async {
    final c = await signedIn(tester);
    await go(tester, c, '/cards/manage');
    expect(find.text('3 cards · all active'), findsOneWidget);
    expect(find.text('Debit •••• 4821'), findsOneWidget);
    expect(find.text('Credit •••• 1176'), findsOneWidget);
    expect(find.text('Virtual •••• 6630'), findsOneWidget);
    expect(find.text('Active'), findsNWidgets(3));

    await tester.runAsync(() => c.read(cardRepositoryProvider).setFrozen('c-2', true));
    c.invalidate(cardsProvider);
    await advance(tester, 100);
    await advance(tester, 1200);
    expect(find.text('3 cards · 1 needs attention'), findsOneWidget);
    expect(find.text('Frozen'), findsOneWidget);
    await advance(tester, 300);
  });

  testWidgets('Open one card: details, freeze it, and see the limits, PIN and report actions', (tester) async {
    final c = await signedIn(tester);
    await go(tester, c, '/cards/manage');
    await tester.tap(find.text('Debit •••• 4821'));
    await advance(tester, 100);
    await advance(tester, 900);
    await advance(tester, 700);

    expect(find.text('Manage card'), findsOneWidget);
    expect(find.text('Name on card'), findsOneWidget);
    expect(find.text('DUSHAN PERERA'), findsWidgets);
    expect(find.text('Limits & online use'), findsOneWidget);
    expect(find.text('Change card PIN'), findsOneWidget);
    expect(find.text('Report lost or stolen'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await advance(tester, 100);
    await advance(tester, 700);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    final card = (await tester.runAsync(() => c.read(cardRepositoryProvider).cards()))!.firstWhere((k) => k.id == 'c-1');
    expect(card.frozen, isTrue);
    expect(find.text('Frozen'), findsWidgets);
    await advance(tester, 4500);
  });

  testWidgets('An unknown card says so instead of crashing', (tester) async {
    final c = await signedIn(tester);
    await go(tester, c, '/cards/manage/zzz');
    expect(find.text('Card not found'), findsOneWidget);
  });

  testWidgets('Cards tab links to Manage all cards', (tester) async {
    final c = await signedIn(tester);
    c.read(routerProvider).go('/cards');
    await advance(tester, 100);
    await advance(tester, 900);
    await advance(tester, 700);
    await tester.ensureVisible(find.text('Manage all cards'));
    await tester.tap(find.text('Manage all cards'));
    await advance(tester, 100);
    await advance(tester, 900);
    await advance(tester, 700);
    expect(find.text('Card management'), findsOneWidget);
  });
}
