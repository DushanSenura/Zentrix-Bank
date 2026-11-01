import 'package:bank_app/app/providers.dart';
import 'package:bank_app/app/router.dart';
import 'package:bank_app/features/payments/data/mock_ledger.dart';
import 'package:bank_app/features/payments/domain/recurrence.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:bank_app/shared/models/payment_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

PaymentDraft scheduled(DateTime when, {Recurrence repeat = Recurrence.once, double amount = 1000, String from = 'a-sav'}) => PaymentDraft(
  kind: PaymentKind.transfer,
  fromAccountId: from,
  payee: 'Landlord',
  payeeDetail: 'Zentrix Bank 1000200030',
  amount: amount,
  scheduledFor: when,
  recurrence: repeat,
);

/// Pending entries created by scheduling (the demo data has an unrelated pending card payment of its own).
Iterable<Transaction> queued(MockLedger l) => l.transactions.where((t) => t.status == TxStatus.pending && t.id.startsWith('ZB'));

double savings(MockLedger l) => l.accounts.firstWhere((a) => a.id == 'a-sav').balance;

void main() {
  setUpAll(loadAppFont);

  group('nextOccurrence', () {
    test('weekly adds seven days and keeps the time', () {
      expect(nextOccurrence(DateTime(2026, 11, 3, 9), Recurrence.weekly), DateTime(2026, 11, 10, 9));
      expect(nextOccurrence(DateTime(2026, 12, 28, 9), Recurrence.weekly), DateTime(2027, 1, 4, 9));
    });

    test('monthly keeps the chosen day, clamped to short months, without drifting', () {
      var d = DateTime(2027, 1, 31, 9);
      final seen = <DateTime>[];
      for (var i = 0; i < 4; i++) {
        d = nextOccurrence(d, Recurrence.monthly, anchorDay: 31);
        seen.add(d);
      }
      expect(seen, [DateTime(2027, 2, 28, 9), DateTime(2027, 3, 31, 9), DateTime(2027, 4, 30, 9), DateTime(2027, 5, 31, 9)]);
      expect(nextOccurrence(DateTime(2027, 12, 15, 9), Recurrence.monthly), DateTime(2028, 1, 15, 9));
      expect(nextOccurrence(DateTime(2028, 1, 31, 9), Recurrence.monthly, anchorDay: 31), DateTime(2028, 2, 29, 9), reason: 'leap year');
    });

    test('a one-off has no next run', () {
      final d = DateTime(2026, 11, 3, 9);
      expect(nextOccurrence(d, Recurrence.once), d);
    });
  });

  group('MockLedger scheduled payments', () {
    test('scheduling moves no money and queues a pending entry', () {
      final l = MockLedger();
      final before = savings(l);
      final when = DateTime.now().add(const Duration(days: 5));
      final r = l.post(scheduled(when));
      expect(r.scheduled, isTrue);
      expect(savings(l), before);
      expect(l.scheduled.single.nextRun, when);
      expect(l.scheduled.single.active, isTrue);
      expect(l.transactions.first.status, TxStatus.pending);
    });

    test('nothing runs before its day', () {
      final l = MockLedger();
      l.post(scheduled(DateTime.now().add(const Duration(days: 5))));
      l.runDue(DateTime.now().add(const Duration(days: 4)));
      expect(l.scheduled.single.runCount, 0);
      expect(queued(l), hasLength(1));
    });

    test('a one-off payment is made on its day: money moves, the pending entry becomes a real one, and it is finished', () {
      final l = MockLedger();
      final before = savings(l);
      final when = DateTime.now().add(const Duration(days: 2));
      l.post(scheduled(when));
      l.runDue(when.add(const Duration(hours: 1)));
      expect(savings(l), before - 1000);
      final sp = l.scheduled.single;
      expect(sp.status, ScheduleStatus.completed);
      expect(sp.runCount, 1);
      expect(queued(l), isEmpty);
      final paid = l.transactions.first;
      expect(paid.status, TxStatus.completed);
      expect(paid.amount, -1000);
      expect(paid.date, when, reason: 'dated on the day it was due');
      expect(l.transactions.where((t) => t.merchant.contains('Landlord')), hasLength(1), reason: 'no duplicate left behind');
    });

    test('a weekly payment runs each week, queues the next one, and never doubles up', () {
      final l = MockLedger();
      final before = savings(l);
      final first = DateTime.now().add(const Duration(days: 1));
      l.post(scheduled(first, repeat: Recurrence.weekly, amount: 500));

      l.runDue(first.add(const Duration(hours: 1)));
      var sp = l.scheduled.single;
      expect(sp.runCount, 1);
      expect(sp.active, isTrue);
      expect(sp.nextRun, nextOccurrence(first, Recurrence.weekly));
      expect(queued(l), hasLength(1), reason: 'exactly one upcoming entry');

      l.runDue(first.add(const Duration(days: 8)));
      sp = l.scheduled.single;
      expect(sp.runCount, 2);
      expect(savings(l), before - 1000);
      expect(queued(l), hasLength(1));
      expect(l.transactions.where((t) => t.status == TxStatus.completed && t.merchant == 'Landlord'), hasLength(2));
    });

    test('a repeating payment that missed several weeks catches up one run at a time', () {
      final l = MockLedger();
      final first = DateTime.now().add(const Duration(days: 1));
      l.post(scheduled(first, repeat: Recurrence.weekly, amount: 100));
      l.runDue(first.add(const Duration(days: 22))); // runs on day 0, 7, 14, 21
      expect(l.scheduled.single.runCount, 4);
      expect(l.scheduled.single.nextRun.isAfter(first.add(const Duration(days: 22))), isTrue);
    });

    test('a run that cannot be paid is recorded as failed, not silently skipped, and a repeating one carries on', () {
      final l = MockLedger();
      final first = DateTime.now().add(const Duration(days: 1));
      // Schedule within today's means, then drain the account before the day arrives.
      l.post(scheduled(first, repeat: Recurrence.weekly, amount: 2000));
      final all = savings(l);
      l.post(PaymentDraft(kind: PaymentKind.bill, fromAccountId: 'a-sav', payee: 'Big spend', payeeDetail: 'x', amount: all - 100));

      l.runDue(first.add(const Duration(hours: 1)));
      final sp = l.scheduled.single;
      expect(sp.runCount, 0);
      expect(sp.lastMessage, contains('balance is too low'));
      expect(sp.active, isTrue, reason: 'next week may work');
      final failed = l.transactions.firstWhere((t) => t.status == TxStatus.failed);
      expect(failed.merchant, contains('not paid'));
      expect(savings(l), closeTo(100, 0.001), reason: 'nothing was taken');
    });

    test('a failed one-off is marked failed with the reason', () {
      final l = MockLedger();
      final when = DateTime.now().add(const Duration(days: 1));
      l.post(scheduled(when, amount: 5000));
      l.post(PaymentDraft(kind: PaymentKind.bill, fromAccountId: 'a-sav', payee: 'Big spend', payeeDetail: 'x', amount: savings(l) - 10));
      l.runDue(when.add(const Duration(hours: 1)));
      expect(l.scheduled.single.status, ScheduleStatus.failed);
      expect(l.scheduled.single.lastMessage, isNotEmpty);
    });

    test('cancelling stops it and clears the pending entry; a finished one cannot be cancelled again', () {
      final l = MockLedger();
      final before = savings(l);
      final when = DateTime.now().add(const Duration(days: 3));
      final r = l.post(scheduled(when, repeat: Recurrence.monthly));
      l.cancelScheduled(r.id);
      expect(l.scheduled.single.status, ScheduleStatus.cancelled);
      expect(queued(l), isEmpty);
      l.runDue(when.add(const Duration(days: 60)));
      expect(savings(l), before);
      expect(() => l.cancelScheduled(r.id), throwsA(isA<PaymentException>()));
      expect(() => l.cancelScheduled('nope'), throwsA(isA<PaymentException>()));
    });

    test('an own-account transfer moves both sides when it runs', () {
      final l = MockLedger();
      final cur = l.accounts.firstWhere((a) => a.id == 'a-cur').balance;
      final sav = savings(l);
      final when = DateTime.now().add(const Duration(days: 1));
      l.post(PaymentDraft(kind: PaymentKind.transfer, fromAccountId: 'a-sav', toAccountId: 'a-cur', payee: 'Current', payeeDetail: 'x', amount: 700, scheduledFor: when));
      expect(queued(l), hasLength(2));
      l.runDue(when.add(const Duration(hours: 1)));
      expect(savings(l), sav - 700);
      expect(l.accounts.firstWhere((a) => a.id == 'a-cur').balance, cur + 700);
      expect(queued(l), isEmpty);
    });
  });

  group('screens', () {
    testWidgets('Account detail: balance, activity, and actions for this account only', (tester) async {
      useScreen(tester, const Size(390, 2000));
      await openLogin(tester, TestEnv());
      await signInAsDemo(tester);

      await tester.ensureVisible(find.text('Current Account'));
      await tester.tap(find.text('Current Account'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.text('Current account · •••• 7745'), findsOneWidget);
      expect(find.text('LKR 85,200.00'), findsOneWidget);
      expect(find.text('Recent activity'), findsOneWidget);
      expect(find.text('Netflix'), findsOneWidget, reason: 'a Current Account transaction');
      expect(find.text('Starbucks'), findsNothing, reason: 'that is a Savings Account transaction');
      expect(find.text('Send'), findsOneWidget);
      expect(find.text('Statement'), findsOneWidget);
    });

    testWidgets('Account detail: a fixed deposit explains that money cannot be sent from it', (tester) async {
      useScreen(tester, const Size(390, 1600));
      await openLogin(tester, TestEnv());
      await signInAsDemo(tester);
      final c = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      c.read(routerProvider).push('/accounts/a-fd');
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.textContaining('can’t be sent from a fixed deposit'), findsOneWidget);
      expect(find.text('Send'), findsNothing);
    });

    testWidgets('Account detail: an unknown account says so instead of crashing', (tester) async {
      useScreen(tester, const Size(390, 1200));
      await openLogin(tester, TestEnv());
      await signInAsDemo(tester);
      final c = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      c.read(routerProvider).push('/accounts/zzz');
      await advance(tester, 100);
      await advance(tester, 900);
      expect(find.text('Account not found'), findsOneWidget);
    });

    testWidgets('Send from an account pre-selects it on the transfer screen', (tester) async {
      useScreen(tester, const Size(390, 2000));
      await openLogin(tester, TestEnv());
      await signInAsDemo(tester);
      final c = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      c.read(routerProvider).push('/transfer?from=a-cur');
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.textContaining('Current Account'), findsWidgets);
    });

    testWidgets('Scheduled payments: empty state, then a queued payment can be cancelled', (tester) async {
      useScreen(tester, const Size(390, 1600));
      await openLogin(tester, TestEnv());
      await signInAsDemo(tester);
      final c = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      final router = c.read(routerProvider);

      router.push('/scheduled');
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.text('Nothing scheduled'), findsOneWidget);
      router.pop();
      await advance(tester, 100);
      await advance(tester, 700);

      c.read(ledgerProvider).post(scheduled(DateTime.now().add(const Duration(days: 4)), repeat: Recurrence.monthly, amount: 25000));
      router.push('/scheduled');
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Landlord'), findsOneWidget);
      expect(find.textContaining('Every month'), findsOneWidget);
      expect(find.text('LKR 25,000.00'), findsOneWidget);

      await tester.tap(find.text('Stop repeating'));
      await advance(tester, 100);
      await advance(tester, 500);
      expect(find.text('Stop this repeating payment?'), findsOneWidget);
      await tester.tap(find.text('Keep it'));
      await advance(tester, 100);
      await advance(tester, 500);
      expect(c.read(ledgerProvider).scheduled.single.active, isTrue, reason: '"Keep it" changes nothing');

      await tester.tap(find.text('Stop repeating'));
      await advance(tester, 100);
      await advance(tester, 500);
      await tester.tap(find.text('Stop payments'));
      await advance(tester, 100);
      await advance(tester, 900);
      await advance(tester, 700);
      expect(c.read(ledgerProvider).scheduled.single.status, ScheduleStatus.cancelled);
      expect(find.text('Finished'), findsOneWidget);
      expect(find.textContaining('Cancelled'), findsWidgets);
      await advance(tester, 4500);
    });
  });
}
