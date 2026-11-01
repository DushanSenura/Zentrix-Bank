import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

const _pin = '246813';

Future<TestEnv> dashboard(WidgetTester tester, {Size size = const Size(390, 1400)}) async {
  useScreen(tester, size);
  final env = TestEnv();
  await openLogin(tester, env);
  await signInAsDemo(tester);
  expect(find.text('Total balance'), findsOneWidget);
  return env;
}

Future<void> go(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.tap(find.text(label).first);
  await advance(tester, 100);
  await advance(tester, 600);
}

Future<void> enter(WidgetTester tester, String key, String value) =>
    tester.enterText(find.byKey(ValueKey(key)), value);

/// Confirm payment, then create the transaction PIN the first time (the demo user has none).
Future<void> confirmAndAuthorize(WidgetTester tester, {bool createPin = true}) async {
  await tester.ensureVisible(find.text('Confirm payment'));
  await tester.tap(find.text('Confirm payment'));
  await advance(tester, 100);
  await advance(tester, 700);
  if (createPin) {
    expect(find.text('Create a transaction PIN'), findsOneWidget);
    await tapPin(tester, _pin);
    await advance(tester, 300);
    await tapPin(tester, _pin);
  } else {
    expect(find.text('Authorise payment'), findsOneWidget);
    await tapPin(tester, _pin);
  }
  await advance(tester, 500); // approved flash + sheet closing
  await advance(tester, 700);
  await advance(tester, 1800); // mock network
  await advance(tester, 800);
}

Future<void> sendToSaved(WidgetTester tester, String who, String amount) async {
  await go(tester, 'Transfer');
  expect(find.text('Send money'), findsOneWidget);
  await go(tester, 'Saved');
  await advance(tester, 500);
  await tester.tap(find.text(who));
  await advance(tester, 200);
  await go(tester, 'Continue');
  await enter(tester, 'amount', amount);
  await advance(tester, 100);
  await go(tester, 'Review');
  expect(find.text('Review payment'), findsOneWidget);
}

void main() {
  setUpAll(loadAppFont);

  testWidgets('Transfer to a saved beneficiary: review, authorise, receipt, balances update', (tester) async {
    final env = await dashboard(tester);
    await sendToSaved(tester, 'Nimal', '1000');

    // Review shows exactly what will happen.
    expect(find.text('LKR 1,000.00'), findsWidgets);
    expect(find.text('LKR 25.00'), findsOneWidget); // inter-bank fee
    expect(find.text('LKR 1,025.00'), findsOneWidget);
    expect(find.text('Nimal Perera'), findsOneWidget);

    await confirmAndAuthorize(tester);
    expect(find.text('Transfer Successful'), findsOneWidget);
    expect(find.textContaining('ZB'), findsWidgets); // transaction id
    expect(find.text('Savings Account •••• 3021'), findsOneWidget);

    await tester.ensureVisible(find.text('Share'));
    await tester.tap(find.text('Share'));
    await advance(tester, 100);
    expect(env.receipts.shared, hasLength(1));
    await tester.tap(find.text('Download'));
    await advance(tester, 200);
    expect(env.receipts.saved, hasLength(1));
    expect(find.text('Receipt saved to this device.'), findsOneWidget);

    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    await advance(tester, 100);
    await advance(tester, 700);
    await advance(tester, 1500);
    expect(find.text('LKR 1,762,925.00'), findsOneWidget); // 1,763,950 − 1,025
  });

  testWidgets('Amount above the available balance is blocked before review', (tester) async {
    await dashboard(tester);
    await go(tester, 'Transfer');
    await go(tester, 'Saved');
    await advance(tester, 500);
    await tester.tap(find.text('Nimal'));
    await go(tester, 'Continue');
    await enter(tester, 'amount', '999999');
    await go(tester, 'Review');
    expect(find.text('Amount exceeds your available balance.'), findsOneWidget);
    expect(find.text('Review payment'), findsNothing);
  });

  testWidgets('Three wrong PINs cancel the payment and no money moves', (tester) async {
    await dashboard(tester);
    // Create the PIN with a small first payment.
    await sendToSaved(tester, 'Landlord', '500');
    await confirmAndAuthorize(tester);
    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    await advance(tester, 100);
    await advance(tester, 1000); // refetch lands
    await advance(tester, 1200); // count-up finishes
    expect(find.text('LKR 1,763,450.00'), findsOneWidget); // Zentrix → free

    await sendToSaved(tester, 'Landlord', '700');
    await tester.ensureVisible(find.text('Confirm payment'));
    await tester.tap(find.text('Confirm payment'));
    await advance(tester, 100);
    await advance(tester, 700);
    for (var i = 0; i < 3; i++) {
      await tapPin(tester, '135790');
      await advance(tester, 100);
      await advance(tester, 600);
    }
    await advance(tester, 700);
    expect(find.text('Too many incorrect PINs. This payment was not made.'), findsOneWidget);
    expect(find.text('Review payment'), findsOneWidget); // still on review, nothing submitted
    await advance(tester, 3500);
  });

  testWidgets('A recipient the bank can’t verify fails with a clear message and no debit', (tester) async {
    await dashboard(tester);
    await go(tester, 'Transfer');
    await go(tester, 'Other bank');
    await advance(tester, 200);
    await tester.tap(find.text('Bank'));
    await advance(tester, 300);
    await tester.tap(find.text('Commercial Bank').last);
    await advance(tester, 300);
    await enter(tester, 'toAccount', '8000000000');
    await enter(tester, 'toName', 'Test Person');
    await go(tester, 'Continue');
    await enter(tester, 'amount', '2000');
    await go(tester, 'Review');
    await confirmAndAuthorize(tester);
    expect(find.text('Payment unsuccessful'), findsOneWidget);
    expect(find.textContaining('couldn’t verify that account number'), findsOneWidget);
    expect(find.text('No money has left your account.'), findsOneWidget);
    await tester.tap(find.text('Review again'));
    await advance(tester, 100);
    await advance(tester, 600);
    expect(find.text('Review payment'), findsOneWidget);
  });

  testWidgets('Own-account transfer is free; new beneficiary is saved after paying', (tester) async {
    await dashboard(tester);
    await go(tester, 'Transfer');
    await tester.tap(find.text('Current Account').last);
    await advance(tester, 200);
    await go(tester, 'Continue');
    await enter(tester, 'amount', '3000');
    await go(tester, 'Review');
    expect(find.text('Free'), findsWidgets);
    await confirmAndAuthorize(tester);
    expect(find.text('Transfer Successful'), findsOneWidget);
    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    await advance(tester, 100);
    await advance(tester, 700);

    // New beneficiary, saved with the payment.
    await go(tester, 'Transfer');
    await go(tester, 'New');
    await tester.tap(find.text('Bank'));
    await advance(tester, 300);
    await tester.tap(find.text('Sampath Bank').last);
    await advance(tester, 300);
    await enter(tester, 'toAccount', '5551234567');
    await enter(tester, 'toName', 'Ruwan Jayasinghe');
    await go(tester, 'Continue');
    await enter(tester, 'amount', '1500');
    await go(tester, 'Review');
    await confirmAndAuthorize(tester, createPin: false);
    expect(find.text('Transfer Successful'), findsOneWidget);
    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    await advance(tester, 100);
    await advance(tester, 700);

    await go(tester, 'Payments');
    await go(tester, 'Beneficiaries');
    await advance(tester, 500);
    expect(find.text('Ruwan Jayasinghe'), findsOneWidget);
  });

  testWidgets('Bill payment: category → provider → details → receipt', (tester) async {
    await dashboard(tester);
    await go(tester, 'Pay');
    expect(find.text('Pay bills'), findsOneWidget);
    await go(tester, 'Electricity');
    await go(tester, 'Ceylon Electricity Board');
    await go(tester, 'Review'); // empty form is blocked
    expect(find.text('Account number is required.'), findsOneWidget);
    await enter(tester, 'billReference', '0123456789');
    await enter(tester, 'billAmount', '6840');
    await go(tester, 'Review');
    expect(find.text('Review payment'), findsOneWidget);
    expect(find.text('Account number: 0123456789'), findsOneWidget);
    await confirmAndAuthorize(tester);
    expect(find.text('Bill Paid'), findsOneWidget);
  });

  testWidgets('QR: a merchant code starts a payment; a foreign code is refused', (tester) async {
    await dashboard(tester);
    await go(tester, 'Scan');
    expect(find.text('Scan to pay'), findsOneWidget);

    await tester.ensureVisible(find.text('Not a Zentrix code'));
    await tester.tap(find.text('Not a Zentrix code'));
    await advance(tester, 100);
    await advance(tester, 300);
    expect(find.textContaining('isn’t a Zentrix payment code'), findsOneWidget);

    await tester.tap(find.text('Keells Supermarket'));
    await advance(tester, 100);
    await advance(tester, 700);
    await enter(tester, 'qrAmount', '4200');
    await tester.tap(find.text('Continue'));
    await advance(tester, 100);
    await advance(tester, 700);
    expect(find.text('Review payment'), findsOneWidget);
    expect(find.text('Merchant ID KEELLS-114'), findsOneWidget);
    await confirmAndAuthorize(tester);
    expect(find.text('Payment Successful'), findsOneWidget);
  });

  testWidgets('My QR shows a code with no balances in it', (tester) async {
    await dashboard(tester);
    await go(tester, 'Payments');
    await go(tester, 'My QR');
    expect(find.text('Dushan Perera'), findsOneWidget);
    expect(find.text('Customer NC 1029 3847'), findsOneWidget);
  });

  testWidgets('Beneficiaries: favourite, search, edit nickname, remove', (tester) async {
    await dashboard(tester);
    await go(tester, 'Payments');
    await go(tester, 'Beneficiaries');
    await advance(tester, 500);
    expect(find.text('Nimal'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'kamala');
    await advance(tester, 300);
    expect(find.text('Kamala Silva'), findsOneWidget);
    expect(find.text('Nimal'), findsNothing);
    await tester.enterText(find.byType(TextField), 'zzz');
    await advance(tester, 300);
    expect(find.text('No matches'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await advance(tester, 300);

    await tester.tap(find.byTooltip('Add to favourites').first);
    await advance(tester, 100);
    await advance(tester, 300);

    await tester.tap(find.byTooltip('More options').first);
    await advance(tester, 100);
    await advance(tester, 300);
    await tester.tap(find.text('Remove'));
    await advance(tester, 100);
    await advance(tester, 400);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await advance(tester, 100);
    await advance(tester, 500);
    expect(find.textContaining('removed.'), findsOneWidget);
    await advance(tester, 3500);
  });

  testWidgets('Payment screens lay out without overflow on a small phone with large text', (tester) async {
    useScreen(tester, const Size(320, 640));
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final env = TestEnv();
    await openLogin(tester, env);
    await signInAsDemo(tester);

    await go(tester, 'Payments');
    expect(tester.takeException(), isNull);
    for (final entry in {'Transfer': 'Send money', 'Pay bills': 'Pay bills', 'Card management': 'Card management', 'Scan to pay': 'Scan to pay', 'Beneficiaries': 'Beneficiaries'}.entries) {
      await go(tester, entry.key);
      expect(find.text(entry.value), findsWidgets);
      expect(tester.takeException(), isNull, reason: entry.key);
      await tester.tap(find.byTooltip('Back'));
      await advance(tester, 100);
      await advance(tester, 600);
    }
  });
}
