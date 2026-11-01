import 'package:bank_app/app/providers.dart';
import 'package:bank_app/app/router.dart';
import 'package:bank_app/core/network/api_exceptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Every screen a signed-in customer can reach without extra input.
const _routes = [
  '/home',
  '/payments',
  '/cards',
  '/cards/pin/c-1',
  '/accounts/a-sav',
  '/accounts/a-fd',
  '/scheduled',
  '/disputes',
  '/accounts/open',
  '/loans/apply',
  '/budgets',
  '/fixed-deposits',
  '/fixed-deposits/open',
  '/profile/edit',
  '/analytics',
  '/profile',
  '/transfer',
  '/beneficiaries',
  '/bills',
  '/cards/manage',
  '/cards/manage/c-1',
  '/qr',
  '/transactions',
  '/savings',
  '/loans',
  '/loans/calculator',
  '/statements',
  '/notifications',
  '/search',
  '/settings',
  '/security',
  '/security/password',
  '/security/pin',
  '/security/devices',
  '/security/limits',
  '/security/history',
  '/support',
  '/support/chat',
  '/support/branches',
];

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

/// Text contrast is verified from the design tokens in contrast_test.dart: screenshot sampling
/// over blurred glass gives false readings.
///
/// Runs Flutter's own accessibility checks and returns a readable list of what failed.
Future<List<String>> audit(WidgetTester tester, String where) async {
  final failures = <String>[];
  final guidelines = {
    'Android tap target (48dp)': androidTapTargetGuideline,
    'iOS tap target (44pt)': iOSTapTargetGuideline,
    'Tappable things are labelled': labeledTapTargetGuideline,
  };
  for (final e in guidelines.entries) {
    final r = await e.value.evaluate(tester);
    if (!r.passed) failures.add('$where — ${e.key}: ${r.reason}');
  }
  return failures;
}

Future<void> settle(WidgetTester tester) async {
  await advance(tester, 100);
  await advance(tester, 900);
  await advance(tester, 900);
}

void main() {
  setUpAll(loadAppFont);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('accessibility guidelines hold on every screen (${mode.name})', (tester) async {
      final handle = tester.ensureSemantics();
      useScreen(tester, const Size(390, 1800));
      final env = TestEnv();
      await openLogin(tester, env);
      final failures = <String>[];

      // The signed-out screens first.
      final c = containerOf(tester);
      c.read(themeModeProvider.notifier).set(mode);
      await advance(tester, 400);
      failures.addAll(await audit(tester, 'Sign in'));

      await signInAsDemo(tester);
      for (final route in _routes) {
        c.read(routerProvider).go('/home');
        await settle(tester);
        if (route != '/home') c.read(routerProvider).push(route);
        await settle(tester);
        failures.addAll(await audit(tester, route));
      }

      // Maintenance screen sits above everything else.
      c.read(serviceStatusProvider.notifier).enterMaintenance(const MaintenanceException());
      await settle(tester);
      failures.addAll(await audit(tester, 'Maintenance'));

      await advance(tester, 2000);
      handle.dispose();
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }
}
