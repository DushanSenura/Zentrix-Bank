import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/security/pin_hasher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/glass_bottom_sheet.dart';
import '../../../core/widgets/pin_input.dart';
import '../../../core/widgets/pin_length_picker.dart';

enum AuthResult { approved, cancelled, locked }

/// Step-up check before money moves. This is the local, simulated authorisation layer:
/// a real backend must additionally verify the payment server-side.
Future<AuthResult> authorizePayment(BuildContext context, {required String summary, String title = 'Authorise payment'}) async {
  final result = await showGlassSheet<AuthResult>(context, builder: (_) => _AuthorizeSheet(summary: summary, title: title));
  return result ?? AuthResult.cancelled;
}

class _AuthorizeSheet extends ConsumerStatefulWidget {
  const _AuthorizeSheet({required this.summary, required this.title});
  final String summary, title;

  static const maxAttempts = 3;

  @override
  ConsumerState<_AuthorizeSheet> createState() => _AuthorizeSheetState();
}

enum _Mode { loading, verify, create, confirm }

class _AuthorizeSheetState extends ConsumerState<_AuthorizeSheet> {
  final _pinKey = GlobalKey<PinInputState>();
  _Mode _mode = _Mode.loading;
  String _first = '';
  String? _hint;
  int _attempts = 0;
  bool _biometric = false;
  int _length = defaultPinLength;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hasPin = await ref.read(sessionStoreProvider).hasPin();
    final length = hasPin ? await ref.read(sessionStoreProvider).pinLength() : defaultPinLength;
    final settings = await ref.read(securityProvider.future);
    if (!mounted) return;
    setState(() {
      _length = length;
      _mode = hasPin ? _Mode.verify : _Mode.create;
      _biometric = hasPin && settings.biometricEnabled;
    });
  }

  Future<void> _approve() async {
    _pinKey.currentState?.showSuccess();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (mounted) Navigator.of(context).pop(AuthResult.approved);
  }

  Future<void> _useBiometric() async {
    if (await ref.read(biometricServiceProvider).authenticate('Authorise this payment') && mounted) await _approve();
  }

  Future<void> _onPin(String pin) async {
    final store = ref.read(sessionStoreProvider);
    switch (_mode) {
      case _Mode.verify:
        if (await store.verifyPin(pin)) return _approve();
        _attempts++;
        if (_attempts >= _AuthorizeSheet.maxAttempts) {
          if (mounted) Navigator.of(context).pop(AuthResult.locked);
          return;
        }
        final left = _AuthorizeSheet.maxAttempts - _attempts;
        setState(() => _hint = 'Incorrect PIN. $left ${left == 1 ? 'attempt' : 'attempts'} left.');
        _pinKey.currentState?.showError();
      case _Mode.create:
        if (PinHasher.isWeak(pin)) {
          setState(() => _hint = 'Choose a PIN that’s harder to guess.');
          _pinKey.currentState?.showError();
          return;
        }
        _pinKey.currentState?.clear();
        setState(() {
          _first = pin;
          _hint = null;
          _mode = _Mode.confirm;
        });
      case _Mode.confirm:
        if (pin != _first) {
          setState(() {
            _hint = 'The PINs didn’t match. Try again.';
            _mode = _Mode.create;
          });
          _pinKey.currentState?.showError();
          return;
        }
        await store.setPin(pin);
        ref.invalidate(securityProvider);
        return _approve();
      case _Mode.loading:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = switch (_mode) {
      _Mode.verify || _Mode.loading => widget.title,
      _Mode.create => 'Create a transaction PIN',
      _Mode.confirm => 'Confirm your PIN',
    };
    final body = _mode == _Mode.create
        ? 'Payments need a PIN. Create one now — you’ll use it for every payment.'
        : _mode == _Mode.confirm
        ? 'Enter the same PIN again.'
        : widget.summary;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(header: true, child: Text(title, style: AppTypography.h2, textAlign: TextAlign.center)),
          const SizedBox(height: AppSpacing.xs),
          Text(body, style: AppTypography.body.copyWith(color: c.textSecondary), textAlign: TextAlign.center),
          SizedBox(
            height: 36,
            child: Center(
              child: Semantics(
                liveRegion: true,
                child: Text(_hint ?? '', style: AppTypography.bodySmall.copyWith(color: c.error)),
              ),
            ),
          ),
          if (_mode == _Mode.loading)
            const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: CircularProgressIndicator())
          else
            if (_mode == _Mode.create) ...[
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
            PinInput(
              key: _pinKey,
              length: _length,
              onCompleted: _onPin,
              leading: _biometric
                  ? IconButton(
                      tooltip: 'Use biometrics',
                      iconSize: 30,
                      onPressed: _useBiometric,
                      icon: Icon(Icons.fingerprint_rounded, color: c.accent),
                    )
                  : null,
            ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
            onPressed: () => Navigator.of(context).pop(AuthResult.cancelled),
            child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
          ),
        ],
      ),
    );
  }
}
