import 'package:bank_app/app/providers.dart';
import 'package:bank_app/app/router.dart';
import 'package:bank_app/features/cards/presentation/card_management_pages.dart';
import 'package:bank_app/features/dashboard/data/mock_banking_repositories.dart';
import 'package:bank_app/shared/models/engagement_models.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

const _pin = '246813';
const _branch = 'Zentrix Bank — Colombo Fort';

/// A repository on a clock the test controls, that records what the "bank" tells the customer.
class Rig {
  Rig({List<BankCard> cards = const []}) {
    repo = MockCardRepository(cards: cards, clock: () => now, notify: notices.add);
  }
  DateTime now = DateTime(2026, 11, 3, 10);
  final notices = <AppNotification>[];
  late final MockCardRepository repo;

  Future<BankCard> debit({String? branch = _branch}) => repo.requestCard(kind: CardKind.debit, accountId: 'a-sav', holder: 'Nimal Fernando', collectionBranch: branch);
  Future<BankCard> virtual() => repo.requestCard(kind: CardKind.virtual, accountId: 'a-sav', holder: 'Nimal Fernando');
  Future<BankCard> byId(String id) async => (await repo.cards()).firstWhere((c) => c.id == id);
}

void main() {
  setUpAll(loadAppFont);

  group('debit card: prepared by the bank, collected from the branch', () {
    test('is "being prepared" for 5 days, with the branch and the day it will be ready', () async {
      final r = Rig();
      final card = await r.debit();
      expect(card.issuance, CardIssuance.preparing);
      expect(card.collectionBranch, _branch);
      expect(card.readyOn, DateTime(2026, 11, 8, 10));
      expect(card.usable, isFalse);
      expect(debitCardPreparationDays, 5);
      expect(r.notices, isEmpty, reason: 'nothing to announce yet');
    });

    test('a branch must be chosen', () async {
      for (final bad in [null, '', '   ']) {
        await expectLater(Rig().debit(branch: bad), throwsA(isA<CardException>().having((e) => e.message, 'message', contains('Choose the branch'))), reason: '$bad');
      }
    });

    test('nothing is announced and it cannot be activated before day 5', () async {
      final r = Rig();
      final card = await r.debit();
      r.now = DateTime(2026, 11, 7, 23, 59);
      expect((await r.byId(card.id)).issuance, CardIssuance.preparing);
      expect(r.notices, isEmpty);
      await expectLater(r.repo.activateCard(card.id), throwsA(isA<CardException>().having((e) => e.message, 'message', contains('isn’t ready to collect yet'))));
    });

    test('after 5 days the customer is told, once, to collect it from their branch', () async {
      final r = Rig();
      final card = await r.debit();
      r.now = DateTime(2026, 11, 8, 10, 1);
      expect((await r.byId(card.id)).issuance, CardIssuance.readyToCollect);
      expect(r.notices, hasLength(1));
      final n = r.notices.single;
      expect(n.title, 'Your debit card is ready to collect');
      expect(n.body, contains(_branch));
      expect(n.body, contains('bring your ID'));
      expect(n.body, contains(card.last4));
      expect(n.category, NotifCategory.bankNotices);
      // Looking again, or much later, doesn't repeat it.
      await r.repo.cards();
      r.now = DateTime(2026, 12, 25);
      await r.repo.cards();
      expect(r.notices, hasLength(1));
    });

    test('once collected it is activated, and then it can be managed like any card', () async {
      final r = Rig();
      final card = await r.debit();
      await expectLater(r.repo.setFrozen(card.id, true), throwsA(isA<CardException>().having((e) => e.message, 'message', contains('isn’t active yet'))));
      r.now = DateTime(2026, 11, 9);
      await r.repo.activateCard(card.id);
      final active = await r.byId(card.id);
      expect(active.issuance, CardIssuance.active);
      expect(active.usable, isTrue);
      await r.repo.setFrozen(card.id, true);
      expect((await r.byId(card.id)).frozen, isTrue);
      await expectLater(r.repo.activateCard(card.id), throwsA(isA<CardException>().having((e) => e.message, 'message', contains('already active'))));
    });

    test('only one debit card can be on its way at a time', () async {
      final r = Rig();
      final first = await r.debit();
      await expectLater(r.debit(), throwsA(isA<CardException>().having((e) => e.message, 'message', contains('already being prepared'))));
      r.now = DateTime(2026, 11, 20);
      await r.repo.activateCard(first.id);
      await r.debit();
    });

    test('nothing about a card that is not active yet can be changed', () async {
      final r = Rig();
      final card = await r.debit();
      final controls = const CardControls(dailyLimit: 1000, maxDailyLimit: 100000);
      await expectLater(r.repo.updateControls(card.id, controls), throwsA(isA<CardException>()));
      await expectLater(r.repo.changePin(card.id, currentPin: '4821', newPin: '2580'), throwsA(isA<CardException>()));
      await expectLater(r.repo.reportLostOrStolen(card.id), throwsA(isA<CardException>().having((e) => e.message, 'message', contains('nothing to block'))));
    });
  });

  group('virtual card: only the bank can activate it', () {
    test('is waiting for the bank, and the customer cannot activate or use it', () async {
      final r = Rig();
      final card = await r.virtual();
      expect(card.issuance, CardIssuance.pendingApproval);
      expect(card.usable, isFalse);
      expect(card.holder, 'NIMAL FERNANDO');
      await expectLater(r.repo.activateCard(card.id), throwsA(isA<CardException>().having((e) => e.message, 'message', contains('The bank activates virtual cards'))));
      await expectLater(r.repo.setFrozen(card.id, true), throwsA(isA<CardException>()));
      // Time doesn't approve it either.
      r.now = DateTime(2027, 1, 1);
      expect((await r.byId(card.id)).issuance, CardIssuance.pendingApproval);
      expect(r.notices, isEmpty);
    });

    test('when the bank approves it, it becomes active and the customer is told', () async {
      final r = Rig();
      final card = await r.virtual();
      final other = await r.virtual();
      expect(r.repo.approvePendingVirtualCards(), 2);
      expect((await r.byId(card.id)).issuance, CardIssuance.active);
      expect((await r.byId(other.id)).issuance, CardIssuance.active);
      expect(r.notices.map((n) => n.title), everyElement('Your virtual card is active'));
      expect(r.notices.first.body, contains(card.last4));
      expect(r.repo.approvePendingVirtualCards(), 0, reason: 'nothing left to approve');
      await r.repo.setFrozen(card.id, true); // now it can be managed
    });

    test('waiting cards count towards the limit of three', () async {
      final r = Rig();
      await r.virtual();
      await r.virtual();
      await r.virtual();
      await expectLater(r.virtual(), throwsA(isA<CardException>().having((e) => e.message, 'message', contains('maximum of 3'))));
      r.repo.approvePendingVirtualCards();
      final first = (await r.repo.cards()).first;
      await r.repo.reportLostOrStolen(first.id);
      await r.virtual(); // blocking one frees a slot
    });
  });

  test('credit cards are still not issued from the app', () async {
    await expectLater(
      Rig().repo.requestCard(kind: CardKind.credit, accountId: 'a-sav', holder: 'x'),
      throwsA(isA<CardException>().having((e) => e.message, 'message', contains('branch'))),
    );
  });

  test('statuses name exactly what a card is waiting for', () {
    const base = BankCard(id: 'c', kind: CardKind.debit, network: CardNetwork.visa, holder: 'X', last4: '1111', expiry: '01/30');
    expect(cardStatusOf(base), CardStatus.active);
    expect(cardStatusOf(base.copyWith(issuance: CardIssuance.pendingApproval)), CardStatus.pendingApproval);
    expect(cardStatusOf(base.copyWith(issuance: CardIssuance.preparing)), CardStatus.preparing);
    expect(cardStatusOf(base.copyWith(issuance: CardIssuance.readyToCollect)), CardStatus.readyToCollect);
    expect(cardStatusOf(base.copyWith(issuance: CardIssuance.preparing, frozen: true)), CardStatus.preparing);
    expect(cardStatusLabel(CardStatus.pendingApproval), 'Awaiting bank approval');
    expect(cardStatusLabel(CardStatus.preparing), 'Being prepared');
    expect(cardStatusLabel(CardStatus.readyToCollect), 'Ready to collect');
  });

  group('screens', () {
    Future<ProviderContainer> signedIn(WidgetTester tester) async {
      useScreen(tester, const Size(390, 2600));
      await openLogin(tester, TestEnv());
      await signInAsDemo(tester);
      return ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    }

    Future<void> settle(WidgetTester tester) async {
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
    }

    Future<void> createPinInSheet(WidgetTester tester) async {
      await tapPin(tester, _pin);
      await advance(tester, 300);
      await tapPin(tester, _pin);
      await advance(tester, 500);
      await advance(tester, 700);
    }

    testWidgets('Request a virtual card: it says the bank will activate it, and it shows as awaiting approval', (tester) async {
      final c = await signedIn(tester);
      c.read(routerProvider).push('/cards/manage');
      await settle(tester);
      await tester.tap(find.text('Request a new card'));
      await advance(tester, 100);
      await advance(tester, 700);
      expect(find.textContaining('The bank reviews it and activates it'), findsOneWidget);
      expect(find.text('Collect from'), findsNothing, reason: 'a branch is only needed for a debit card');

      await tester.tap(find.text('Request card'));
      await advance(tester, 100);
      await advance(tester, 700);
      await createPinInSheet(tester);
      await advance(tester, 1200);
      await advance(tester, 1200);

      expect(find.textContaining('The bank will activate it'), findsWidgets);
      expect(find.text('Awaiting bank approval'), findsOneWidget);
      final inbox = (await tester.runAsync(() => c.read(notificationsProvider.future)))!;
      expect(inbox.where((n) => n.title == 'New card requested' && n.body.contains('until the bank activates it')), hasLength(1));
      await advance(tester, 4500);
    });

    testWidgets('Request a debit card: pick a branch, and see when it will be ready and where to collect it', (tester) async {
      final c = await signedIn(tester);
      c.read(routerProvider).push('/cards/manage');
      await settle(tester);
      await tester.tap(find.text('Request a new card'));
      await advance(tester, 100);
      await advance(tester, 700);
      await tester.tap(find.text('Debit card'));
      await advance(tester, 400);
      expect(find.text('Collect from'), findsOneWidget);
      expect(find.textContaining('Ready to collect from a branch in about 5 days'), findsOneWidget);

      await tester.tap(find.text('Request card'));
      await advance(tester, 100);
      await advance(tester, 700);
      await createPinInSheet(tester);
      await advance(tester, 1200);
      await advance(tester, 1200);

      expect(find.text('Being prepared'), findsOneWidget);
      expect(find.textContaining('Ready '), findsWidgets);
      final inbox = (await tester.runAsync(() => c.read(notificationsProvider.future)))!;
      expect(inbox.where((n) => n.title == 'New card requested' && n.body.contains('about 5 days')), hasLength(1));

      await tester.tap(find.text('Being prepared'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.text('Being prepared'), findsWidgets);
      expect(find.textContaining('ready to collect from Zentrix Bank'), findsOneWidget);
      expect(find.text('Activate card'), findsNothing, reason: 'not collectable yet');
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull, reason: 'can’t be frozen until it is active');
      await advance(tester, 4500);
    });

    testWidgets('Prototype tools: skip 5 days and the debit card becomes "Ready to collect" with a notification; activate it with the PIN', (tester) async {
      final c = await signedIn(tester);
      await tester.runAsync(() => c.read(cardRepositoryProvider).requestCard(kind: CardKind.debit, accountId: 'a-sav', holder: 'Dushan Perera', collectionBranch: _branch));
      c.invalidate(cardsProvider);

      c.read(routerProvider).push('/settings');
      await settle(tester);
      expect(find.text('Prototype tools'), findsOneWidget);
      await tester.ensureVisible(find.text('Time: skip 5 days'));
      await tester.tap(find.text('Time: skip 5 days'));
      await advance(tester, 100);
      await advance(tester, 1500);
      expect(find.textContaining('Moved the bank’s clock forward 5 days'), findsOneWidget);
      c.read(routerProvider).pop();
      await advance(tester, 100);
      await advance(tester, 700);

      c.read(routerProvider).push('/cards/manage');
      await settle(tester);
      expect(find.text('Ready to collect'), findsOneWidget);
      expect(find.textContaining('Collect from $_branch'), findsOneWidget);
      final inbox = (await tester.runAsync(() => c.read(notificationsProvider.future)))!;
      expect(inbox.where((n) => n.title == 'Your debit card is ready to collect'), hasLength(1), reason: 'the inbox picked up the bank’s message by itself');

      await tester.tap(find.text('Ready to collect'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.textContaining('Collect your card from $_branch'), findsOneWidget);
      await tester.ensureVisible(find.text('Activate card'));
      await tester.tap(find.text('Activate card'));
      await advance(tester, 100);
      await advance(tester, 700);
      await createPinInSheet(tester);
      await advance(tester, 1000);
      await advance(tester, 1000);
      final cards = (await tester.runAsync(() => c.read(cardRepositoryProvider).cards()))!;
      expect(cards.last.issuance, CardIssuance.active);
      await advance(tester, 4500);
    });

    testWidgets('Prototype tools: approving as the bank activates a waiting virtual card and notifies the customer', (tester) async {
      final c = await signedIn(tester);
      await tester.runAsync(() => c.read(cardRepositoryProvider).requestCard(kind: CardKind.virtual, accountId: 'a-sav', holder: 'Dushan Perera'));
      c.invalidate(cardsProvider);
      c.read(routerProvider).push('/cards/manage');
      await settle(tester);
      expect(find.text('Awaiting bank approval'), findsOneWidget);
      c.read(routerProvider).pop();
      await advance(tester, 100);
      await advance(tester, 700);

      c.read(routerProvider).push('/settings');
      await settle(tester);
      await tester.ensureVisible(find.text('Bank: approve waiting virtual cards'));
      await tester.tap(find.text('Bank: approve waiting virtual cards'));
      await advance(tester, 100);
      await advance(tester, 1500);
      expect(find.textContaining('1 virtual card approved'), findsOneWidget);
      c.read(routerProvider).pop();
      await advance(tester, 100);
      await advance(tester, 700);

      c.read(routerProvider).push('/cards/manage');
      await settle(tester);
      expect(find.text('Awaiting bank approval'), findsNothing);
      expect(find.text('Active'), findsNWidgets(4));
      final inbox = (await tester.runAsync(() => c.read(notificationsProvider.future)))!;
      expect(inbox.where((n) => n.title == 'Your virtual card is active'), hasLength(1));
      await advance(tester, 4500);
    });

    testWidgets('A virtual card waiting for the bank has no Activate button, and says why', (tester) async {
      final c = await signedIn(tester);
      final card = (await tester.runAsync(() => c.read(cardRepositoryProvider).requestCard(kind: CardKind.virtual, accountId: 'a-sav', holder: 'Dushan Perera')))!;
      c.invalidate(cardsProvider);
      c.read(routerProvider).push('/cards/manage/${card.id}');
      await settle(tester);
      expect(find.text('Waiting for the bank'), findsOneWidget);
      expect(find.textContaining('you can’t activate it yourself'), findsOneWidget);
      expect(find.text('Activate card'), findsNothing);
      expect(find.text('Limits & online use'), findsOneWidget);
      expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Limits & online use')).enabled, isFalse);
    });
  });
}
