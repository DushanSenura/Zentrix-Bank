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
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/engagement_models.dart';
import '../../authentication/domain/auth_repository.dart';
import '../../payments/presentation/authorize_sheet.dart';

/// Your name and customer number are fixed (they come from the bank's records); phone and email can be updated here.
/// A change goes to the places the bank uses to reach you, so it needs your PIN and leaves a security notification.
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: ref.read(authProvider)?.email ?? '');
  late final _phone = TextEditingController(text: ref.read(authProvider)?.phone ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = ref.read(authProvider);
    if (user == null || _busy) return;
    if (!_form.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }
    final email = _email.text.trim(), phone = _phone.text.trim();
    if (email == user.email && phone == user.phone) {
      context.pop();
      return;
    }
    final result = await authorizePayment(context, title: 'Confirm your new details', summary: 'Update the email and mobile number the bank uses to contact you.');
    if (!mounted) return;
    if (result == AuthResult.locked) {
      BankSnackbar.show(context, 'Too many incorrect PINs. Your details weren’t changed.', kind: SnackKind.error);
      return;
    }
    if (result != AuthResult.approved) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ref.read(authRepositoryProvider).updateContact(userId: user.id, email: email, phone: phone);
      ref.read(authProvider.notifier).updateUser(updated);
      await ref.read(notificationsProvider.notifier).post(
        NotifCategory.security,
        'Contact details changed',
        'The email and mobile number on your profile were updated. If this wasn’t you, contact us immediately.',
        severity: Severity.warning,
      );
      if (!mounted) return;
      BankSnackbar.show(context, 'Your details were updated.', kind: SnackKind.success);
      context.pop();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'We couldn’t save your details. Nothing was changed — please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(authProvider);
    return FlowPage(
      title: 'Personal details',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReadOnly('Name', user?.fullName ?? ''),
                _ReadOnly('Customer number', user?.customerNumber ?? ''),
                const SizedBox(height: 4),
                Text(
                  'To change your name or ID details, visit a branch with your documents.',
                  style: AppTypography.caption.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Form(
            key: _form,
            child: Column(
              children: [
                BankTextField(
                  fieldKey: const ValueKey('profileEmail'),
                  controller: _email,
                  label: 'Email',
                  icon: Icons.mail_rounded,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: Validators.email,
                ),
                const SizedBox(height: AppSpacing.sm),
                BankTextField(
                  fieldKey: const ValueKey('profilePhone'),
                  controller: _phone,
                  label: 'Mobile number',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]'))],
                  textInputAction: TextInputAction.done,
                  validator: Validators.phone,
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    Icon(Icons.error_rounded, size: 18, color: c.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: AppTypography.bodySmall.copyWith(color: c.error))),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: 'Save changes', loading: _busy, onPressed: _save),
        ],
      ),
    );
  }
}

class _ReadOnly extends StatelessWidget {
  const _ReadOnly(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        label: '$label: $value',
        child: ExcludeSemantics(
          child: Row(
            children: [
              SizedBox(width: 130, child: Text(label, style: AppTypography.body.copyWith(color: c.textSecondary))),
              Expanded(child: Text(value, style: AppTypography.title, textAlign: TextAlign.end)),
            ],
          ),
        ),
      ),
    );
  }
}
