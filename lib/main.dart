import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'app/providers.dart';
import 'core/diagnostics/error_reporting.dart';
import 'core/security/secure_store.dart';
import 'core/storage/preferences_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandling(const DebugCrashReporter());
  // Load saved settings first so the very first frame already uses the saved theme.
  final preferences = await PreferencesStore.load(const FlutterSecureStore());
  runApp(ProviderScope(overrides: [preferencesStoreProvider.overrideWithValue(preferences)], child: const BankApp()));
}
