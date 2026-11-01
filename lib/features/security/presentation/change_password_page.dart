import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/bank_text_field.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/password_rules.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/shake.dart';
import '../../../shared/models/engagement_models.dart';
import '../../authentication/domain/auth_repository.dart';

class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _form = GlobalKey<FormState>();
  final _shake = GlobalKey<ShakeState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      _shake.currentState?.shake();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(
        userId: ref.read(authProvider)!.id,
        current: _current.text,
        next: _next.text,
      );
      await ref.read(notificationsProvider.notifier).post(
        NotifCategory.security,
        'Password changed',
        'Your password was changed. If this wasn’t you, contact us immediately.',
        severity: Severity.warning,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      BankSnackbar.show(context, 'Password updated.', kind: SnackKind.success);
      context.pop();
    } on AuthException catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _shake.currentState?.shake();
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FlowPage(
      title: 'Change password',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
        children: [
          Shake(
            key: _shake,
            child: GlassCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Form(
                key: _form,
                child: Column(
                  children: [
                    BankTextField(
                      fieldKey: const ValueKey('currentPassword'),
                      controller: _current,
                      label: 'Current password',
                      icon: Icons.lock_clock_rounded,
                      secure: true,
                      textInputAction: TextInputAction.next,
                      validator: (v) => Validators.required(v, 'Current password'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    BankTextField(
                      fieldKey: const ValueKey('newPassword'),
                      controller: _next,
                      label: 'New password',
                      icon: Icons.lock_rounded,
                      secure: true,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        final base = Validators.password(v);
                        if (base != null) return base;
                        return v == _current.text ? 'Choose a password you haven’t used just now.' : null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    PasswordRules(controller: _next),
                    const SizedBox(height: AppSpacing.sm),
                    BankTextField(
                      fieldKey: const ValueKey('confirmNewPassword'),
                      controller: _confirm,
                      label: 'Confirm new password',
                      icon: Icons.lock_outline_rounded,
                      secure: true,
                      textInputAction: TextInputAction.done,
                      validator: (v) => Validators.matches(v, _next.text),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Semantics(liveRegion: true, child: Text(_error!, style: AppTypography.bodySmall.copyWith(color: c.error))),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(label: 'Update password', loading: _busy, onPressed: _save),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
