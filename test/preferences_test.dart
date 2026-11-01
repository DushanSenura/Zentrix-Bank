import 'package:bank_app/app/providers.dart';
import 'package:bank_app/core/security/secure_store.dart';
import 'package:bank_app/core/storage/preferences_store.dart';
import 'package:bank_app/shared/models/engagement_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _BrokenStore implements SecureStore {
  @override
  Future<String?> read(String key) async => throw StateError('keystore unavailable');
  @override
  Future<void> write(String key, String value) async => throw StateError('keystore unavailable');
  @override
  Future<void> delete(String key) async {}
}

ProviderContainer containerFor(PreferencesStore store) {
  final c = ProviderContainer(overrides: [preferencesStoreProvider.overrideWithValue(store)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('Preferences', () {
    test('round-trips through JSON', () {
      const p = Preferences(
        themeMode: ThemeMode.dark,
        reduceMotion: true,
        defaultAccountId: 'a-cur',
        mutedCategories: {'offers', 'payments'},
        lockTimeoutSeconds: 300,
      );
      final back = Preferences.fromJson(p.toJson());
      expect(back.themeMode, ThemeMode.dark);
      expect(back.reduceMotion, isTrue);
      expect(back.defaultAccountId, 'a-cur');
      expect(back.mutedCategories, {'offers', 'payments'});
      expect(back.lockTimeoutSeconds, 300);
    });

    test('garbage or out-of-range stored values fall back to safe defaults', () {
      expect(Preferences.fromJson('nonsense').themeMode, ThemeMode.system);
      final odd = Preferences.fromJson({
        'themeMode': 'neon',
        'reduceMotion': 'yes',
        'defaultAccountId': 42,
        'mutedCategories': 'all',
        'lockTimeoutSeconds': 1,
      });
      expect(odd.themeMode, ThemeMode.system);
      expect(odd.reduceMotion, isFalse);
      expect(odd.defaultAccountId, isNull);
      expect(odd.mutedCategories, isEmpty);
      expect(odd.lockTimeoutSeconds, 120, reason: 'a 1-second lock timeout would be unusable');
      expect(Preferences.fromJson({'lockTimeoutSeconds': 99999}).lockTimeoutSeconds, 120);
    });
  });

  group('PreferencesStore', () {
    test('unreadable storage never stops the app from starting', () async {
      final store = await PreferencesStore.load(_BrokenStore());
      expect(store.current.themeMode, ThemeMode.system);
      await store.update((p) => p.copyWith(reduceMotion: true)); // a failed write must not throw
      expect(store.current.reduceMotion, isTrue);
    });

    test('a corrupted blob is ignored', () async {
      final mem = MemorySecureStore();
      await mem.write('preferences_v1', '{not json');
      expect((await PreferencesStore.load(mem)).current.themeMode, ThemeMode.system);
    });

    test('settings survive a restart, and sign-out clears only what belongs to the customer', () async {
      final disk = MemorySecureStore();
      final first = containerFor(await PreferencesStore.load(disk));
      first.read(themeModeProvider.notifier).set(ThemeMode.dark);
      first.read(settingsProvider.notifier)
        ..setReduceMotion(true)
        ..setDefaultAccount('a-cur')
        ..setMuted(NotifCategory.offers, muted: true);
      first.read(lockTimeoutProvider.notifier).set(const Duration(minutes: 5));
      await Future<void>.delayed(Duration.zero);

      // "Relaunch": a brand-new store and container reading the same disk.
      final store = await PreferencesStore.load(disk);
      final second = containerFor(store);
      expect(second.read(themeModeProvider), ThemeMode.dark);
      expect(second.read(lockTimeoutProvider), const Duration(minutes: 5));
      final s = second.read(settingsProvider);
      expect(s.reduceMotion, isTrue);
      expect(s.defaultAccountId, 'a-cur');
      expect(s.mutedCategories, {NotifCategory.offers});

      await store.clearAccountData();
      final third = containerFor(await PreferencesStore.load(disk));
      expect(third.read(settingsProvider).defaultAccountId, isNull);
      expect(third.read(settingsProvider).mutedCategories, isEmpty);
      expect(third.read(themeModeProvider), ThemeMode.dark, reason: 'theme belongs to the device');
      expect(third.read(settingsProvider).reduceMotion, isTrue);
      expect(third.read(lockTimeoutProvider), const Duration(minutes: 5));
    });
  });
}
