import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/security/pin_hasher.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/pin_input.dart';
import '../../../core/widgets/pin_length_picker.dart';
import '../../../core/widgets/primary_button.dart';

enum _Phase { create, confirm, biometric }

/// Shown once after "remember me" sign-in or registration. The PIN is stored only
/// as a salted hash and unlocks the app on this device; it never authorises payments by itself.
class PinSetupPage extends ConsumerStatefulWidget {
  const PinSetupPage({super.key});

  @override
  ConsumerState<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends ConsumerState<PinSetupPage> {
  final _pinKey = GlobalKey<PinInputState>();
  _Phase _phase = _Phase.create;
  String _first = '';
  String? _hint;
  bool _busy = false;
  int _length = defaultPinLength;

  void _finish() => ref.read(pinSetupPendingProvider.notifier).set(false);

  Future<void> _skip() async {
    // Without a PIN the stored token could never be used, so don't leave it behind.
    await ref.read(sessionStoreProvider).clear();
    _finish();
  }

  Future<void> _onPin(String pin) async {
    if (_phase == _Phase.create) {
      if (PinHasher.isWeak(pin)) {
        setState(() => _hint = 'That PIN is too easy to guess. Avoid repeats and sequences.');
        _pinKey.currentState?.showError();
        return;
      }
      _pinKey.currentState?.clear();
      setState(() {
        _first = pin;
        _hint = null;
        _phase = _Phase.confirm;
      });
      return;
    }
    if (pin != _first) {
      setState(() {
        _hint = 'The PINs didn’t match. Let’s start again.';
        _phase = _Phase.create;
        _first = '';
      });
      _pinKey.currentState?.showError();
      return;
    }
    final pause = AppAnimations.scaled(context, const Duration(milliseconds: 450));
    await ref.read(sessionStoreProvider).setPin(pin);
    _pinKey.currentState?.showSuccess();
    ref.invalidate(securityProvider);
    await Future<void>.delayed(pause);
    if (!mounted) return;
    final available = await ref.read(securityProvider.future).then((s) => s.biometricAvailable);
    if (!mounted) return;
    available ? setState(() => _phase = _Phase.biometric) : _finish();
  }

  Future<void> _enableBiometric() async {
    setState(() => _busy = true);
    final ok = await ref.read(securityProvider.notifier).setBiometric(true, reason: 'Enable biometric unlock for Zentrix Bank');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _finish();
    } else {
      BankSnackbar.show(context, 'Biometric unlock wasn’t enabled. You can try again from Profile.', kind: SnackKind.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final biometric = _phase == _Phase.biometric;
    final title = switch (_phase) {
      _Phase.create => 'Create your PIN',
      _Phase.confirm => 'Confirm your PIN',
      _Phase.biometric => 'Unlock with biometrics?',
    };
    final body = switch (_phase) {
      _Phase.create => 'Choose a $_length-digit PIN to unlock Zentrix Bank on this device.',
      _Phase.confirm => 'Enter the same PIN again to confirm.',
      _Phase.biometric => 'Use your fingerprint or face instead of typing your PIN. Your biometric data never leaves your device.',
    };
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
                        onPressed: _busy ? null : _skip,
                        child: Text('Skip for now', style: TextStyle(color: c.textSecondary)),
                      ),
                    ),
                    const Spacer(),
                    Icon(biometric ? Icons.fingerprint_rounded : Icons.lock_rounded, size: 48, color: c.accent),
                    const SizedBox(height: AppSpacing.md),
                    Semantics(header: true, child: Text(title, style: AppTypography.h1, textAlign: TextAlign.center)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(body, style: AppTypography.bodyLarge.copyWith(color: c.textSecondary), textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: 40,
                      child: Semantics(
                        liveRegion: true,
                        child: Text(_hint ?? '', style: AppTypography.bodySmall.copyWith(color: c.error), textAlign: TextAlign.center),
                      ),
                    ),
                    if (biometric) ...[
                      const SizedBox(height: AppSpacing.lg),
                      PrimaryButton(label: 'Enable biometrics', icon: Icons.fingerprint_rounded, loading: _busy, onPressed: _enableBiometric),
                      TextButton(
                        style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
                        onPressed: _busy ? null : _finish,
                        child: Text('Not now', style: TextStyle(color: c.textSecondary)),
                      ),
                    ] else ...[
                      if (_phase == _Phase.create) ...[
                        PinLengthPicker(
                          value: _length,
                          onChanged: (n) {
                            _pinKey.currentState?.clear();
                            setState(() {
                              _length = n;
                              _hint = null;
                            });
                          },
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      PinInput(key: _pinKey, length: _length, onCompleted: _onPin),
                    ],
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
