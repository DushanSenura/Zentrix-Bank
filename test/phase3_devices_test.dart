import 'dart:io';
import 'package:bank_app/app/router.dart';
import 'package:bank_app/core/device/device_services.dart';
import 'package:bank_app/core/device/geo.dart';
import 'package:bank_app/features/payments/domain/qr_payload.dart';
import 'package:bank_app/shared/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

Future<(TestEnv, ProviderContainer)> signedIn(WidgetTester tester, {Size size = const Size(390, 2400)}) async {
  useScreen(tester, size);
  final env = TestEnv();
  await openLogin(tester, env);
  await signInAsDemo(tester);
  return (env, containerOf(tester));
}

Future<void> open(WidgetTester tester, ProviderContainer c, String route) async {
  c.read(routerProvider).push(route);
  await advance(tester, 100);
  await advance(tester, 900);
  await advance(tester, 700);
}

void main() {
  setUpAll(loadAppFont);

  group('geo', () {
    test('distanceKm matches known city distances', () {
      expect(distanceKm(6.9344, 79.8428, 6.9344, 79.8428), 0);
      // Colombo Fort to Kandy is roughly 94 km in a straight line.
      expect(distanceKm(6.9344, 79.8428, 7.2906, 80.6337), inInclusiveRange(88, 100));
      // Symmetric.
      expect(distanceKm(6.9, 79.8, 7.3, 80.6), closeTo(distanceKm(7.3, 80.6, 6.9, 79.8), 1e-9));
    });

    test('directionsUri targets the destination in a link any maps app can open', () {
      final u = directionsUri(6.9344, 79.8428);
      expect(u.scheme, 'https');
      expect(u.queryParameters['destination'], '6.9344,79.8428');
      expect(u.queryParameters['api'], '1');
    });
  });

  group('Android and iOS declare what the new features need', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    test('Android permissions, with the camera optional', () {
      for (final p in ['CAMERA', 'ACCESS_COARSE_LOCATION', 'INTERNET']) {
        expect(manifest, contains('android.permission.$p'));
      }
      expect(manifest, contains('android:name="android.hardware.camera" android:required="false"'));
      expect(manifest, isNot(contains('ACCESS_FINE_LOCATION')), reason: 'approximate location is enough');
      expect(manifest, isNot(contains('READ_CONTACTS')), reason: 'nothing reads the address book, so the app must not ask for it');
    });

    test('iOS explains camera and location in plain words, and does not ask for contacts', () {
      for (final k in ['NSCameraUsageDescription', 'NSLocationWhenInUseUsageDescription']) {
        expect(plist, contains(k));
      }
      expect(plist, isNot(contains('NSContactsUsageDescription')));
    });
  });

  group('screens', () {
    testWidgets('QR: a code read by the camera starts a payment; a foreign code is refused; repeats are ignored', (tester) async {
      final (env, c) = await signedIn(tester);
      await open(tester, c, '/qr');
      expect(find.text('Camera preview'), findsOneWidget, reason: 'the live camera view is what the Scan tab shows');
      expect(find.text('No code to hand? Try a sample'), findsOneWidget);

      env.scanner.scan('https://example.com/pay?to=someone');
      await advance(tester, 100);
      await advance(tester, 600);
      expect(find.textContaining('isn’t a Zentrix payment code'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);

      await advance(tester, 4500);
      env.scanner.scan(merchantQr('KEELLS-114', 'Keells Supermarket', TxCategory.food));
      env.scanner.scan(merchantQr('KEELLS-114', 'Keells Supermarket', TxCategory.food)); // the camera reports it again
      await advance(tester, 100);
      await advance(tester, 700);
      expect(find.text('Merchant ID KEELLS-114'), findsOneWidget, reason: 'one amount sheet, not two');

      await tester.enterText(find.byKey(const ValueKey('qrAmount')), '1250');
      await tester.tap(find.text('Continue'));
      await advance(tester, 100);
      await advance(tester, 800);
      expect(find.text('Review payment'), findsOneWidget);
      expect(find.text('LKR 1,250.00'), findsWidgets);
    });

    testWidgets('Branches: sorted by real distance when the customer shares where they are, with directions', (tester) async {
      final (env, c) = await signedIn(tester);
      // Standing next to the Bambalapitiya branch.
      env.location.position = const GeoPoint(6.8906, 79.8561);
      await open(tester, c, '/support/branches');
      expect(env.location.asked, 0, reason: 'location is never requested until the customer asks');
      expect(find.textContaining('never stored or sent'), findsOneWidget);

      await tester.tap(find.text('Sort by distance from me'));
      await advance(tester, 100);
      await advance(tester, 500);
      expect(env.location.asked, 1);
      final names = tester.widgetList<Text>(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').startsWith(RegExp(r'(Zentrix Bank —|ATM —)')))).map((t) => t.data).toList();
      expect(names.first, 'Zentrix Bank — Bambalapitiya', reason: 'nearest first');
      expect(find.text('0.0 km'), findsOneWidget);
      expect(find.text('Update my location'), findsOneWidget);

      await tester.tap(find.text('Zentrix Bank — Bambalapitiya'));
      await advance(tester, 200);
      expect(env.links.opened.last.queryParameters['destination'], '6.8905,79.856');
    });

    testWidgets('Branches: if location is unavailable the list stays as it was and says so', (tester) async {
      final (env, c) = await signedIn(tester);
      env.location.position = null;
      await open(tester, c, '/support/branches');
      await tester.tap(find.text('Sort by distance from me'));
      await advance(tester, 100);
      await advance(tester, 500);
      expect(find.textContaining('couldn’t get your location'), findsOneWidget);
      expect(find.text('Sort by distance from me'), findsOneWidget);
      expect(find.text('1.2 km'), findsOneWidget);
      await advance(tester, 4500);
    });
  });
}
