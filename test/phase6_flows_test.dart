import 'package:bank_app/app/providers.dart';
import 'package:bank_app/features/authentication/data/mock_auth_repository.dart';
import 'package:bank_app/core/widgets/bank_logo.dart';
import 'package:bank_app/shared/models/engagement_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

const _pin = '246813';
const _newPin = '135792';

Future<TestEnv> dashboard(WidgetTester tester, {Size size = const Size(390, 1600), bool remember = false}) async {
  useScreen(tester, size);
  final env = TestEnv();
  await openLogin(tester, env);
  if (remember) {
    await signIn(tester, remember: true);
    await tapPin(tester, _pin);
    await advance(tester, 500);
    await tapPin(tester, _pin);
    await advance(tester, 700);
    await advance(tester, 1500);
  } else {
    await signInAsDemo(tester);
  }
  return env;
}

Future<void> go(WidgetTester tester, String label, {int index = 0}) async {
  // Lazily built lists may not have created the row yet.
  if (find.text(label).evaluate().length <= index) await tester.scrollUntilVisible(find.text(label), 200);
  final f = find.text(label).at(index);
  await tester.ensureVisible(f);
  await tester.tap(f);
  await advance(tester, 100);
  await advance(tester, 700);
}

Future<void> openFromProfile(WidgetTester tester, String item) async {
  await go(tester, 'Profile');
  await go(tester, item);
  await advance(tester, 600);
}

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

void main() {
  setUpAll(loadAppFont);

  testWidgets('Notifications: unread badge, mark read, category filter, mark all', (tester) async {
    await dashboard(tester);
    expect(find.byTooltip('Notifications, 3 unread'), findsOneWidget);
    await tester.tap(find.byTooltip('Notifications, 3 unread'));
    await advance(tester, 100);
    await advance(tester, 800);
    expect(find.text('Card payment'), findsOneWidget);

    await tester.tap(find.text('Card payment'));
    await advance(tester, 100);
    await advance(tester, 400);
    expect(containerOf(tester).read(unreadCountProvider), 2);

    await tester.tap(find.text('Security').first);
    await advance(tester, 100);
    await advance(tester, 400);
    expect(find.text('New device signed in'), findsOneWidget);
    expect(find.text('Weekend dining offer'), findsNothing);
    expect(find.text('Warning'), findsOneWidget); // severity chip

    await tester.tap(find.text('All'));
    await advance(tester, 300);
    await tester.tap(find.byTooltip('Mark all as read'));
    await advance(tester, 100);
    await advance(tester, 500);
    expect(containerOf(tester).read(unreadCountProvider), 0);
  });

  testWidgets('Card freeze creates a security notification', (tester) async {
    await dashboard(tester);
    await go(tester, 'Cards');
    await advance(tester, 1000);
    await tester.tap(find.byType(Switch));
    await advance(tester, 100);
    await advance(tester, 500);

    await openFromProfile(tester, 'Notifications');
    expect(find.text('Card frozen'), findsOneWidget);
    expect(find.text('Your card ending 4821 is frozen. Payments are blocked.'), findsOneWidget);
  });

  testWidgets('Search: finds settings and transactions, opens them, remembers recent searches', (tester) async {
    await dashboard(tester);
    await tester.tap(find.byTooltip('Search'));
    await advance(tester, 100);
    await advance(tester, 700);
    expect(find.textContaining('Try “bills”'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'pin');
    await advance(tester, 300);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Change transaction PIN'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await advance(tester, 300);
    expect(find.text('No results'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'uber');
    await advance(tester, 300);
    expect(find.text('Transactions'), findsOneWidget);
    await tester.tap(find.text('Uber').first);
    await advance(tester, 100);
    await advance(tester, 700);
    expect(find.text('Transaction ID'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await advance(tester, 100);
    await advance(tester, 700);
    await tester.enterText(find.byType(TextField), '');
    await advance(tester, 300);
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('uber'), findsOneWidget);
  });

  testWidgets('Change password: wrong current is refused, then the new password works', (tester) async {
    await dashboard(tester);
    await openFromProfile(tester, 'Security center');
    await go(tester, 'Change password');

    Future<void> submit(String current, String next) async {
      await tester.enterText(find.byKey(const ValueKey('currentPassword')), current);
      await tester.enterText(find.byKey(const ValueKey('newPassword')), next);
      await tester.enterText(find.byKey(const ValueKey('confirmNewPassword')), next);
      await tester.ensureVisible(find.text('Update password'));
      await tester.tap(find.text('Update password'));
      await advance(tester, 1000);
      await advance(tester, 500);
    }

    await submit('WrongPass@1', 'Brand@New123');
    expect(find.text('Your current password is incorrect.'), findsOneWidget);

    await submit(MockAuthRepository.demoPassword, 'Brand@New123');
    expect(find.text('Password updated.'), findsOneWidget);
    await advance(tester, 4000);

    // Sign out and back in with the new password.
    await tester.tap(find.byTooltip('Back'));
    await advance(tester, 100);
    await advance(tester, 700);
    await go(tester, 'Log out');
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await advance(tester, 100);
    await advance(tester, 800);
    await signIn(tester, password: 'Brand@New123');
    await advance(tester, 1500);
    expect(find.text('Total balance'), findsOneWidget);
  });

  testWidgets('Change PIN: verifies the old one, rejects weak, and the new one unlocks the app', (tester) async {
    final env = await dashboard(tester, remember: true);
    await openFromProfile(tester, 'Security center');
    await go(tester, 'Change transaction PIN');
    expect(find.text('Enter your current PIN'), findsOneWidget);

    await tapPin(tester, '000001');
    await advance(tester, 100);
    expect(find.text('Incorrect PIN. 2 attempts left.'), findsOneWidget);
    await advance(tester, 600);

    await tapPin(tester, _pin);
    await advance(tester, 300);
    expect(find.text('Choose a new PIN'), findsOneWidget);
    await tapPin(tester, '111111');
    await advance(tester, 100);
    expect(find.textContaining('too easy to guess'), findsOneWidget);
    await advance(tester, 600);

    await tapPin(tester, _newPin);
    await advance(tester, 300);
    await tapPin(tester, _newPin);
    await advance(tester, 700);
    expect(find.text('PIN updated.'), findsWidgets); // the toast shows on both pages mid-transition
    await advance(tester, 4000);

    await relaunch(tester, env);
    await tapPin(tester, _pin);
    await advance(tester, 100);
    expect(find.text('Incorrect PIN. 4 attempts left.'), findsOneWidget); // old PIN no longer works
    await advance(tester, 600);
    await tapPin(tester, _newPin);
    await advance(tester, 800);
    await advance(tester, 1500);
    expect(find.text('Total balance'), findsOneWidget);
  });

  testWidgets('Devices: log out one device, then all others; this device stays', (tester) async {
    await dashboard(tester);
    await openFromProfile(tester, 'Security center');
    await go(tester, 'Trusted devices & sessions');
    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text('iPad'), findsOneWidget);
    expect(find.text('This device'), findsWidgets);

    await tester.tap(find.text('Log out').first);
    await advance(tester, 100);
    await advance(tester, 500);
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await advance(tester, 100);
    await advance(tester, 600);
    expect(find.text('Pixel 8'), findsNothing);
    expect(find.text('iPad'), findsOneWidget);

    await tester.tap(find.text('Log out all other devices'));
    await advance(tester, 100);
    await advance(tester, 500);
    await tester.tap(find.widgetWithText(FilledButton, 'Log out all'));
    await advance(tester, 100);
    await advance(tester, 600);
    expect(find.text('iPad'), findsNothing);
    expect(find.text('Log out all other devices'), findsNothing);
    expect(find.text('This device'), findsWidgets);
    await advance(tester, 4000);
  });

  testWidgets('Limits: lowering the daily limit needs the PIN and is reflected in the security center', (tester) async {
    await dashboard(tester);
    await openFromProfile(tester, 'Security center');
    expect(find.text('Daily transfers up to LKR 500,000.00'), findsOneWidget);
    await go(tester, 'Transaction limits');
    await tester.tap(find.text('Save limit')); // nothing changed yet, so this is inert
    await advance(tester, 100);
    await advance(tester, 700);
    expect(find.text('Create a transaction PIN'), findsNothing);

    await tester.drag(find.byType(Slider), const Offset(-400, 0));
    await advance(tester, 300);
    await tester.ensureVisible(find.text('Save limit'));
    await tester.tap(find.text('Save limit'));
    await advance(tester, 100);
    await advance(tester, 700);
    expect(find.text('Create a transaction PIN'), findsOneWidget);
    await tapPin(tester, _pin);
    await advance(tester, 300);
    await tapPin(tester, _pin);
    await advance(tester, 500);
    await advance(tester, 800);
    expect(find.text('Daily limit saved.'), findsOneWidget);
    await advance(tester, 4000);
    expect(containerOf(tester).read(ledgerProvider).userDailyLimit, lessThan(500000));
  });

  testWidgets('Two-factor toggle asks to confirm, and login history lists a failed attempt', (tester) async {
    await dashboard(tester);
    await openFromProfile(tester, 'Security center');
    await tester.tap(find.byType(Switch).first);
    await advance(tester, 100);
    await advance(tester, 500);
    expect(find.text('Turn on two-factor?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Turn on'));
    await advance(tester, 100);
    await advance(tester, 600);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    expect(find.text('Two-factor turned on'), findsOneWidget); // shown under Security alerts

    await go(tester, 'Login history');
    await advance(tester, 500);
    expect(find.text('Failed sign-in · Unknown browser'), findsOneWidget);
    expect(find.text('Signed in · This device'), findsOneWidget); // recorded when we signed in
  });

  testWidgets('Support: FAQ, call and email launch links, chat replies honestly, branches open maps', (tester) async {
    final env = await dashboard(tester);
    await openFromProfile(tester, 'Help & support');

    await go(tester, 'How do I freeze my card?');
    expect(find.textContaining('switch on “Freeze card”'), findsOneWidget);

    await go(tester, 'Call the bank');
    await go(tester, 'Email support');
    expect(env.links.opened.map((u) => u.scheme), ['tel', 'mailto']);

    await go(tester, 'Branches & ATMs');
    await advance(tester, 500);
    await tester.tap(find.text('Zentrix Bank — Colombo Fort'));
    await advance(tester, 200);
    expect(env.links.opened.last.host, 'www.google.com', reason: 'branches with coordinates open directions');
    expect(env.links.opened.last.queryParameters['destination'], '6.9344,79.8428');
    await tester.tap(find.byTooltip('Back'));
    await advance(tester, 100);
    await advance(tester, 700);

    await go(tester, 'Chat with us');
    expect(find.textContaining('Automated assistant · not a person'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'what are the fees');
    await tester.tap(find.byTooltip('Send'));
    await advance(tester, 100);
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Assistant is typing'), findsOneWidget);
    await advance(tester, 1200);
    await advance(tester, 400);
    expect(find.textContaining('LKR 25'), findsOneWidget);

    await tester.tap(find.byTooltip('Attach a file'));
    await advance(tester, 300);
    expect(find.text('Attachments aren’t available in the prototype.'), findsOneWidget);
    await advance(tester, 4000);
  });

  testWidgets('Settings: reduce motion, lock timeout, muted categories and default account', (tester) async {
    await dashboard(tester);
    await openFromProfile(tester, 'Settings');
    final c = containerOf(tester);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Reduce motion'));
    await advance(tester, 100);
    await advance(tester, 300);
    expect(c.read(settingsProvider).reduceMotion, isTrue);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Offers'));
    await advance(tester, 100);
    await advance(tester, 300);
    expect(c.read(settingsProvider).mutedCategories, {NotifCategory.offers});
    c.read(notificationsProvider.notifier).post(NotifCategory.offers, 'Muted promo', 'should not appear');
    c.read(notificationsProvider.notifier).post(NotifCategory.security, 'Security always shown', 'visible');
    List<String>? titles;
    c.read(notificationRepositoryProvider).notifications().then((l) => titles = [for (final n in l) n.title]);
    await advance(tester, 100);
    await advance(tester, 600);
    expect(titles, isNot(contains('Muted promo')));
    expect(titles, contains('Security always shown'));
    expect(tester.widget<Switch>(find.descendant(of: find.widgetWithText(SwitchListTile, 'Security'), matching: find.byType(Switch))).onChanged, isNull);

    await tester.ensureVisible(find.text('2 min').first);
    await tester.tap(find.text('2 min').first);
    await advance(tester, 100);
    await advance(tester, 400);
    await tester.tap(find.text('5 min').last);
    await advance(tester, 100);
    await advance(tester, 400);
    expect(c.read(lockTimeoutProvider), const Duration(minutes: 5));

    await tester.ensureVisible(find.text('Default account'));
    await tester.tap(find.text('Default account'));
    await advance(tester, 100);
    await advance(tester, 700);
    await tester.tap(find.text('Current Account').last);
    await advance(tester, 100);
    await advance(tester, 700);
    expect(c.read(settingsProvider).defaultAccountId, 'a-cur');
  });

  testWidgets('App lock: idle timeout asks for the PIN and returns you to where you were', (tester) async {
    await dashboard(tester, remember: true);
    final c = containerOf(tester);
    c.read(lockTimeoutProvider.notifier).set(const Duration(minutes: 1));
    await go(tester, 'Payments');
    expect(find.text('Send again'), findsOneWidget);

    // Idle for just over a minute.
    for (var i = 0; i < 13; i++) {
      await advance(tester, 5000);
    }
    await advance(tester, 700);
    expect(find.text('Authentication required'), findsOneWidget);

    await tapPin(tester, '000001');
    await advance(tester, 100);
    expect(find.text('Incorrect PIN. 4 attempts left.'), findsOneWidget);
    await advance(tester, 600);

    await tapPin(tester, _pin);
    await advance(tester, 100);
    await advance(tester, 800);
    expect(find.text('Authentication required'), findsNothing);
    expect(find.text('Send again'), findsOneWidget); // back on the Payments tab's location
  });

  testWidgets('App lock: activity resets the idle timer, and five wrong PINs sign out', (tester) async {
    await dashboard(tester, remember: true);
    final c = containerOf(tester);
    c.read(lockTimeoutProvider.notifier).set(const Duration(minutes: 1));

    // Touching the screen every 40s keeps the session open.
    for (var i = 0; i < 4; i++) {
      await advance(tester, 40000);
      await tester.tapAt(const Offset(5, 5));
    }
    expect(find.text('Authentication required'), findsNothing);

    await advance(tester, 61000);
    await advance(tester, 700);
    expect(find.text('Authentication required'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tapPin(tester, '000001');
      await advance(tester, 100);
      await advance(tester, 600);
    }
    await advance(tester, 800);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(c.read(authProvider), isNull);
  });

  testWidgets('Privacy shield covers the app while it is inactive', (tester) async {
    await dashboard(tester);
    expect(find.byType(BankLogo), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await advance(tester, 100);
    expect(find.byType(BankLogo), findsOneWidget); // the opaque cover shows the logo only
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await advance(tester, 100);
    expect(find.byType(BankLogo), findsNothing);
    expect(find.text('Total balance'), findsOneWidget);
  });

  testWidgets('New screens lay out without overflow on a small phone with large text', (tester) async {
    useScreen(tester, const Size(320, 640));
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openLogin(tester, TestEnv());
    await signInAsDemo(tester);

    await go(tester, 'Profile');
    expect(tester.takeException(), isNull, reason: 'Profile');
    for (final item in ['Notifications', 'Security center', 'Settings', 'Help & support']) {
      await go(tester, item);
      await advance(tester, 1500);
      expect(tester.takeException(), isNull, reason: item);
      await tester.tap(find.byTooltip('Back'));
      await advance(tester, 100);
      await advance(tester, 700);
    }
    for (final item in ['Trusted devices & sessions', 'Transaction limits', 'Login history']) {
      await go(tester, 'Security center');
      await go(tester, item);
      await advance(tester, 1200);
      expect(tester.takeException(), isNull, reason: item);
      await tester.tap(find.byTooltip('Back'));
      await advance(tester, 100);
      await advance(tester, 700);
      await tester.tap(find.byTooltip('Back'));
      await advance(tester, 100);
      await advance(tester, 700);
    }
  });
}
