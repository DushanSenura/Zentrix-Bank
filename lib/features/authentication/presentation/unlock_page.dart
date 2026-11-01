import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/bank_logo.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/pin_input.dart';

/// Returning-user gate: PIN (or biometrics) re-opens the stored session without a password.
class UnlockPage extends ConsumerStatefulWidget {
  const UnlockPage({super.key});

  static const maxAttempts = 5;

  @override
  ConsumerState<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends ConsumerState<UnlockPage> {
  final _pinKey = GlobalKey<PinInputState>();
  int _length = 6;
  int _attempts = 0;
  bool _busy = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    ref.read(sessionStoreProvider).pinLength().then((n) {
      if (mounted) setState(() => _length = n);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoBiometric());
  }

  Future<void> _autoBiometric() async {
    final settings = await ref.read(securityProvider.future);
    if (mounted && settings.biometricEnabled) await _biometric();
  }

  Future<void> _biometric() async {
    if (_busy) return;
    final ok = await ref.read(biometricServiceProvider).authenticate('Unlock Zentrix Bank');
    if (ok && mounted) await _restore();
  }

  /// Re-opens the session with the stored refresh token.
  Future<void> _restore() async {
    setState(() => _busy = true);
    final store = ref.read(sessionStoreProvider);
    final token = await store.refreshToken();
    final user = token == null ? null : await ref.read(authRepositoryProvider).restoreSession(token);
    if (!mounted) return;
    if (user == null) {
      await store.clear();
      if (!mounted) return;
      BankSnackbar.show(context, 'Your session has expired. Please sign in again.', kind: SnackKind.warning);
      context.go('/login');
      return;
    }
    ref.read(authProvider.notifier).start(user);
  }

  Future<void> _onPin(String pin) async {
    if (_busy) return;
    setState(() => _busy = true);
    final store = ref.read(sessionStoreProvider);
    final ok = await store.verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      _pinKey.currentState?.showSuccess();
      await _restore();
      return;
    }
    _attempts++;
    if (_attempts >= UnlockPage.maxAttempts) {
      await store.clear();
      if (!mounted) return;
      BankSnackbar.show(context, 'Too many incorrect PINs. Please sign in with your password.', kind: SnackKind.error);
      context.go('/login');
      return;
    }
    final left = UnlockPage.maxAttempts - _attempts;
    setState(() {
      _busy = false;
      _hint = 'Incorrect PIN. $left ${left == 1 ? 'attempt' : 'attempts'} left.';
    });
    _pinKey.currentState?.showError();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bio = ref.watch(securityProvider).value?.biometricEnabled ?? false;
    return Scaffold(
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
                  Semantics(header: true, child: const Text('Enter your PIN', style: AppTypography.h2)),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: 24,
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _hint ?? 'Unlock to continue',
                        style: AppTypography.bodySmall.copyWith(color: _hint == null ? c.textSecondary : c.error),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PinInput(
      length: _length,
                    key: _pinKey,
                    enabled: !_busy,
                    onCompleted: _onPin,
                    leading: bio
                        ? IconButton(
                            tooltip: 'Unlock with biometrics',
                            iconSize: 30,
                            onPressed: _biometric,
                            icon: Icon(Icons.fingerprint_rounded, color: c.accent),
                          )
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
                    onPressed: _busy ? null : () => context.go('/login'),
                    child: Text('Use password instead', style: TextStyle(color: c.accent)),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
