import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/l10n/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_background.dart';
import 'providers.dart';
import 'app_lock_gate.dart';
import 'status_gate.dart';
import 'router.dart';

class BankApp extends ConsumerWidget {
  const BankApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: AppStrings.bankName,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ref.watch(themeModeProvider),
    themeAnimationDuration: const Duration(milliseconds: 300),
    routerConfig: ref.watch(routerProvider),
    builder: (context, child) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: MediaQuery.of(context).disableAnimations || ref.watch(settingsProvider).reduceMotion,
          ),
          child: AppBackground(child: StatusGate(child: AppLockGate(child: child!))),
        ),
      );
    },
  );
}
