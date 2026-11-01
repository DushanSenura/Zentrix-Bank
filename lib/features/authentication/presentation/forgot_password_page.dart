import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/animated_success_icon.dart';
import '../../../core/widgets/bank_text_field.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/password_rules.dart';
import '../../../core/widgets/primary_button.dart';
import '../domain/auth_repository.dart';

enum _Stage { identify, reset, done }

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _identifyForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  _Stage _stage = _Stage.identify;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_identifier, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_identifyForm.currentState!.validate()) return;
    setState(() => _busy = true);
    await ref.read(authRepositoryProvider).requestPasswordReset(_identifier.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = null;
      _stage = _Stage.reset;
    });
  }

  Future<void> _reset() async {
    if (!_resetForm.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).confirmPasswordReset(
        identifier: _identifier.text,
        code: _code.text,
        newPassword: _password.text,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _busy = false;
        _stage = _Stage.done;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (title, subtitle) = switch (_stage) {
      _Stage.identify => ('Forgot password?', 'Enter your username, email or customer ID and we’ll send you a code.'),
      _Stage.reset => ('Reset your password', 'If an account matches ${_identifier.text.trim()}, a 6-digit code is on its way.'),
      _Stage.done => ('Password updated', 'You can now sign in with your new password.'),
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_stage != _Stage.done)
                    IconButton(
                      tooltip: 'Back',
                      constraints: const BoxConstraints(minWidth: AppSpacing.touchTarget, minHeight: AppSpacing.touchTarget),
                      onPressed: _busy ? null : () => _stage == _Stage.reset ? setState(() => _stage = _Stage.identify) : context.pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_stage == _Stage.done) ...[
                    const Center(child: AnimatedSuccessIcon(size: 96)),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  Semantics(header: true, liveRegion: true, child: Text(title, style: AppTypography.h1)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: AppTypography.bodyLarge.copyWith(color: c.textSecondary)),
                  const SizedBox(height: AppSpacing.lg),
                  AnimatedSwitcher(
                    duration: AppAnimations.scaled(context, AppAnimations.normal),
                    child: switch (_stage) {
                      _Stage.identify => KeyedSubtree(key: const ValueKey('identify'), child: _identify()),
                      _Stage.reset => KeyedSubtree(key: const ValueKey('reset'), child: _resetStage()),
                      _Stage.done => KeyedSubtree(
                        key: const ValueKey('done'),
                        child: PrimaryButton(label: 'Back to sign in', onPressed: () => context.go('/login')),
                      ),
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _identify() => GlassCard(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Form(
      key: _identifyForm,
      child: Column(
        children: [
          BankTextField(
            fieldKey: const ValueKey('resetIdentifier'),
            controller: _identifier,
            label: 'Username, email or customer ID',
            icon: Icons.person_rounded,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _sendCode(),
            validator: (v) => Validators.required(v, 'Username'),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: 'Send code', loading: _busy, onPressed: _sendCode),
        ],
      ),
    ),
  );

  Widget _resetStage() {
    final c = context.colors;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Form(
        key: _resetForm,
        child: Column(
          children: [
            BankTextField(
              fieldKey: const ValueKey('resetCode'),
              controller: _code,
              label: '6-digit code',
              icon: Icons.pin_rounded,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              textInputAction: TextInputAction.next,
              validator: Validators.pin,
            ),
            const SizedBox(height: AppSpacing.sm),
            BankTextField(
              fieldKey: const ValueKey('resetPassword'),
              controller: _password,
              label: 'New password',
              icon: Icons.lock_rounded,
              secure: true,
              textInputAction: TextInputAction.next,
              validator: Validators.password,
            ),
            const SizedBox(height: AppSpacing.sm),
            PasswordRules(controller: _password),
            const SizedBox(height: AppSpacing.sm),
            BankTextField(
              fieldKey: const ValueKey('resetConfirm'),
              controller: _confirm,
              label: 'Confirm new password',
              icon: Icons.lock_outline_rounded,
              secure: true,
              textInputAction: TextInputAction.done,
              validator: (v) => Validators.matches(v, _password.text),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: AppTypography.bodySmall.copyWith(color: c.error)),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Reset password', loading: _busy, onPressed: _reset),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Prototype: no message is sent. Use code 123456.',
              style: AppTypography.caption.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
