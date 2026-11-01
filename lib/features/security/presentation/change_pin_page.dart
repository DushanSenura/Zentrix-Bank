import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/security/pin_hasher.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/pin_input.dart';
import '../../../core/widgets/pin_length_picker.dart';
import '../../../shared/models/engagement_models.dart';

enum _Phase { verify, create, confirm }

/// Confirm the current PIN (when there is one), then choose and confirm a new one.
class ChangePinPage extends ConsumerStatefulWidget {
  const ChangePinPage({super.key});

  @override
  ConsumerState<ChangePinPage> createState() => _ChangePinPageState();
}

class _ChangePinPageState extends ConsumerState<ChangePinPage> {
  static const _maxAttempts = 3;
  final _pinKey = GlobalKey<PinInputState>();
  _Phase? _phase;
  String _first = '';
  String? _hint;
  int _attempts = 0;

  /// Digits of the PIN being replaced, and of the new one (which starts the same but can be changed).
  int _currentLength = defaultPinLength;
  int _newLength = defaultPinLength;

  @override
  void initState() {
    super.initState();
    () async {
      final store = ref.read(sessionStoreProvider);
      final has = await store.hasPin();
      final length = has ? await store.pinLength() : defaultPinLength;
      if (mounted) {
        setState(() {
          _currentLength = length;
          _newLength = length;
          _phase = has ? _Phase.verify : _Phase.create;
        });
      }
    }();
  }

  Future<void> _onPin(String pin) async {
    final store = ref.read(sessionStoreProvider);
    switch (_phase!) {
      case _Phase.verify:
        if (await store.verifyPin(pin)) {
          _pinKey.currentState?.clear();
          setState(() {
            _phase = _Phase.create;
            _hint = null;
          });
          return;
        }
        _attempts++;
        if (_attempts >= _maxAttempts) {
          if (!mounted) return;
          BankSnackbar.show(context, 'Too many incorrect PINs. Your PIN wasn’t changed.', kind: SnackKind.error);
          context.pop();
          return;
        }
        setState(() => _hint = 'Incorrect PIN. ${_maxAttempts - _attempts} ${_maxAttempts - _attempts == 1 ? 'attempt' : 'attempts'} left.');
        _pinKey.currentState?.showError();
      case _Phase.create:
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
      case _Phase.confirm:
        if (pin != _first) {
          setState(() {
            _hint = 'The PINs didn’t match. Let’s start again.';
            _phase = _Phase.create;
          });
          _pinKey.currentState?.showError();
          return;
        }
        final pause = AppAnimations.scaled(context, const Duration(milliseconds: 450));
        await store.setPin(pin);
        ref.invalidate(securityProvider);
        await ref.read(notificationsProvider.notifier).post(
          NotifCategory.security,
          'Transaction PIN changed',
          'Your PIN was changed on this device.',
          severity: Severity.warning,
        );
        _pinKey.currentState?.showSuccess();
        await Future<void>.delayed(pause);
        if (!mounted) return;
        BankSnackbar.show(context, 'PIN updated.', kind: SnackKind.success);
        context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final phase = _phase;
    final title = switch (phase) {
      _Phase.verify => 'Enter your current PIN',
      _Phase.create || null => 'Choose a new PIN',
      _Phase.confirm => 'Confirm your new PIN',
    };
    return FlowPage(
      title: 'Change PIN',
      child: phase == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.gutter),
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  Semantics(header: true, liveRegion: true, child: Text(title, style: AppTypography.h2, textAlign: TextAlign.center)),
                  SizedBox(
                    height: 40,
                    child: Center(
                      child: Semantics(liveRegion: true, child: Text(_hint ?? '', style: AppTypography.bodySmall.copyWith(color: c.error), textAlign: TextAlign.center)),
                    ),
                  ),
                  if (phase == _Phase.create) ...[
                    PinLengthPicker(
                      value: _newLength,
                      onChanged: (n) {
                        _pinKey.currentState?.clear();
                        setState(() {
                          _newLength = n;
                          _hint = null;
                        });
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  PinInput(key: _pinKey, length: phase == _Phase.verify ? _currentLength : _newLength, onCompleted: _onPin),
                ],
              ),
            ),
    );
  }
}
