import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/pin_input.dart';
import '../../../shared/models/engagement_models.dart';
import '../../../shared/models/models.dart';

enum _Phase { current, create, confirm, saving }

/// Card PINs are 4 digits and belong to the card issuer, not this app: they are sent straight to
/// the bank over TLS and are never saved, logged or compared locally.
bool isWeakCardPin(String pin) {
  if (RegExp(r'^(\d)\1+$').hasMatch(pin)) return true;
  const ascending = '0123456789';
  return ascending.contains(pin) || ascending.split('').reversed.join().contains(pin);
}

class CardPinPage extends ConsumerStatefulWidget {
  const CardPinPage({super.key, required this.cardId});
  final String cardId;

  @override
  ConsumerState<CardPinPage> createState() => _CardPinPageState();
}

class _CardPinPageState extends ConsumerState<CardPinPage> {
  static const _maxAttempts = 3;
  final _pinKey = GlobalKey<PinInputState>();
  _Phase _phase = _Phase.current;
  String _current = '', _first = '';
  String? _hint;
  int _attempts = 0;

  Future<void> _onPin(String pin) async {
    switch (_phase) {
      case _Phase.current:
        _current = pin;
        _pinKey.currentState?.clear();
        setState(() {
          _phase = _Phase.create;
          _hint = null;
        });
      case _Phase.create:
        if (isWeakCardPin(pin)) {
          setState(() => _hint = 'That PIN is too easy to guess. Avoid repeats and sequences.');
          _pinKey.currentState?.showError();
          return;
        }
        if (pin == _current) {
          setState(() => _hint = 'Choose a PIN different from your current one.');
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
        await _submit(pin);
      case _Phase.saving:
        break;
    }
  }

  Future<void> _submit(String newPin) async {
    setState(() => _phase = _Phase.saving);
    final pause = AppAnimations.scaled(context, const Duration(milliseconds: 450));
    try {
      await ref.read(cardRepositoryProvider).changePin(widget.cardId, currentPin: _current, newPin: newPin);
      final cards = ref.read(cardsProvider).value ?? const <BankCard>[];
      final last4 = cards.where((c) => c.id == widget.cardId).map((c) => c.last4).firstOrNull ?? '';
      await ref.read(notificationsProvider.notifier).post(
        NotifCategory.security,
        'Card PIN changed',
        'The PIN for your card ending $last4 was changed.',
        severity: Severity.warning,
      );
      _pinKey.currentState?.showSuccess();
      await Future<void>.delayed(pause);
      if (!mounted) return;
      BankSnackbar.show(context, 'Card PIN updated.', kind: SnackKind.success);
      context.pop();
    } on CardException catch (e) {
      if (!mounted) return;
      _attempts++;
      _current = '';
      _first = '';
      if (_attempts >= _maxAttempts) {
        BankSnackbar.show(context, 'Too many failed attempts. Your card PIN wasn’t changed.', kind: SnackKind.error);
        context.pop();
        return;
      }
      setState(() {
        _hint = e.message;
        _phase = _Phase.current;
      });
      _pinKey.currentState?.showError();
    } catch (_) {
      if (!mounted) return;
      BankSnackbar.show(context, 'Couldn’t reach the bank. Your card PIN wasn’t changed.', kind: SnackKind.error);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = switch (_phase) {
      _Phase.current => 'Enter your current card PIN',
      _Phase.create => 'Choose a new card PIN',
      _Phase.confirm => 'Confirm your new card PIN',
      _Phase.saving => 'Updating your card PIN…',
    };
    return FlowPage(
      title: 'Change card PIN',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.lg),
            Semantics(header: true, liveRegion: true, child: Text(title, style: AppTypography.h2, textAlign: TextAlign.center)),
            SizedBox(
              height: 48,
              child: Center(
                child: Semantics(liveRegion: true, child: Text(_hint ?? '', style: AppTypography.bodySmall.copyWith(color: c.error), textAlign: TextAlign.center)),
              ),
            ),
            PinInput(key: _pinKey, length: 4, enabled: _phase != _Phase.saving, onCompleted: _onPin),
          ],
        ),
      ),
    );
  }
}
