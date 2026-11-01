import 'dart:convert';
import 'package:flutter/material.dart';
import '../security/secure_store.dart';

/// Settings that survive a restart. Nothing sensitive lives here: no balances, tokens or PINs.
@immutable
class Preferences {
  const Preferences({
    this.themeMode = ThemeMode.system,
    this.reduceMotion = false,
    this.defaultAccountId,
    this.mutedCategories = const {},
    this.lockTimeoutSeconds = 120,
  });

  final ThemeMode themeMode;
  final bool reduceMotion;

  /// Belongs to the signed-in customer; cleared on sign-out together with [mutedCategories].
  final String? defaultAccountId;
  final Set<String> mutedCategories;
  final int lockTimeoutSeconds;

  Preferences copyWith({
    ThemeMode? themeMode,
    bool? reduceMotion,
    String? defaultAccountId,
    Set<String>? mutedCategories,
    int? lockTimeoutSeconds,
  }) => Preferences(
    themeMode: themeMode ?? this.themeMode,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    defaultAccountId: defaultAccountId ?? this.defaultAccountId,
    mutedCategories: mutedCategories ?? this.mutedCategories,
    lockTimeoutSeconds: lockTimeoutSeconds ?? this.lockTimeoutSeconds,
  );

  Preferences withoutAccountData() => Preferences(
    themeMode: themeMode,
    reduceMotion: reduceMotion,
    lockTimeoutSeconds: lockTimeoutSeconds,
  );

  Map<String, Object?> toJson() => {
    'themeMode': themeMode.name,
    'reduceMotion': reduceMotion,
    'defaultAccountId': defaultAccountId,
    'mutedCategories': mutedCategories.toList(),
    'lockTimeoutSeconds': lockTimeoutSeconds,
  };

  /// Tolerates missing or wrong-typed fields (older app versions, hand-edited storage) by using defaults.
  factory Preferences.fromJson(Object? raw) {
    if (raw is! Map) return const Preferences();
    final theme = ThemeMode.values.where((m) => m.name == raw['themeMode']).firstOrNull ?? ThemeMode.system;
    final muted = raw['mutedCategories'];
    final timeout = raw['lockTimeoutSeconds'];
    return Preferences(
      themeMode: theme,
      reduceMotion: raw['reduceMotion'] == true,
      defaultAccountId: raw['defaultAccountId'] is String ? raw['defaultAccountId'] as String : null,
      mutedCategories: muted is List ? muted.whereType<String>().toSet() : const {},
      lockTimeoutSeconds: timeout is int && timeout >= 30 && timeout <= 3600 ? timeout : 120,
    );
  }
}

/// Keeps the latest [Preferences] in memory (so controllers can read them synchronously) and
/// writes every change through to storage.
class PreferencesStore {
  PreferencesStore(this._store, [this.current = const Preferences()]);
  final SecureStore _store;
  Preferences current;

  static const _key = 'preferences_v1';

  static Future<PreferencesStore> load(SecureStore store) async {
    try {
      final raw = await store.read(_key);
      return PreferencesStore(store, raw == null ? const Preferences() : Preferences.fromJson(jsonDecode(raw)));
    } catch (_) {
      return PreferencesStore(store); // unreadable storage must never stop the app starting
    }
  }

  Future<void> update(Preferences Function(Preferences) change) async {
    current = change(current);
    await _persist();
  }

  Future<void> clearAccountData() => update((p) => p.withoutAccountData());

  Future<void> _persist() async {
    try {
      await _store.write(_key, jsonEncode(current.toJson()));
    } catch (_) {
      // Losing a preference is better than failing the action that changed it.
    }
  }
}
