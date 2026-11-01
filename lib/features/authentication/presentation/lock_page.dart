import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/bank_logo.dart';
import '../../../core/widgets/pin_input.dart';

/// Shown when an idle or backgrounded session needs the PIN again. The session stays open underneath.
class LockPage extends ConsumerStatefulWidget {
  const LockPage({super.key});

  static const maxAttempts = 5;

  @override
  ConsumerState<LockPage> createState() => _LockPageState();
}

class _LockPageState extends ConsumerState<LockPage> {
  final _pinKey = GlobalKey<PinInputState>();
  int _length = 6;
  int _attempts = 0;
  String? _hint;

  @override
  void initState() {
    super.initState();
    ref.read(sessionStoreProvider).pinLength().then((n) {
      if (mounted) setState(() => _length = n);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = await ref.read(securityProvider.future);
      if (mounted && s.biometricEnabled) await _biometric();
    });
  }

  void _unlock() {
    final to = ref.read(appLockProvider).returnTo;
    ref.read(appLockProvider.notifier).unlock();
    context.go(to == null || to == '/lock' ? '/home' : to);
  }

  Future<void> _biometric() async {
    if (await ref.read(biometricServiceProvider).authenticate('Unlock Zentrix Bank') && mounted) _unlock();
  }

  Future<void> _onPin(String pin) async {
    if (await ref.read(sessionStoreProvider).verifyPin(pin)) {
      _pinKey.currentState?.showSuccess();
      if (mounted) _unlock();
      return;
    }
    _attempts++;
    if (_attempts >= LockPage.maxAttempts) {
      await ref.read(authProvider.notifier).signOut();
      return;
    }
    final left = LockPage.maxAttempts - _attempts;
    if (mounted) setState(() => _hint = 'Incorrect PIN. $left ${left == 1 ? 'attempt' : 'attempts'} left.');
    _pinKey.currentState?.showError();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bio = ref.watch(securityProvider).value?.biometricEnabled ?? false;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: Column(
                  children: [
                    const Spacer(),
                    const BankLogo(),
                    const SizedBox(height: AppSpacing.lg),
                    Semantics(header: true, child: const Text('Authentication required', style: AppTypography.h2)),
                    SizedBox(
                      height: 32,
                      child: Semantics(
                        liveRegion: true,
                        child: Center(child: Text(_hint ?? 'Enter your PIN to continue', style: AppTypography.bodySmall.copyWith(color: _hint == null ? c.textSecondary : c.error))),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    PinInput(
      length: _length,
                      key: _pinKey,
                      onCompleted: _onPin,
                      leading: bio
                          ? IconButton(tooltip: 'Unlock with biometrics', iconSize: 30, onPressed: _biometric, icon: Icon(Icons.fingerprint_rounded, color: c.accent))
                          : null,
                    ),
                    TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
                      onPressed: () => ref.read(authProvider.notifier).signOut(),
                      child: Text('Sign out', style: TextStyle(color: c.error)),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
