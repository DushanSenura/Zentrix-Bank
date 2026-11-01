import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_animations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/bank_dropdown.dart';
import '../../../../core/widgets/bank_text_field.dart';
import '../../../../core/widgets/password_rules.dart';
import '../../domain/identity_verification_service.dart';
import 'registration_controller.dart';
import 'registration_fields.dart';

/// Renders the data-driven steps (personal, contact, banking) from [registrationSteps].
class FormStep extends ConsumerStatefulWidget {
  const FormStep({super.key, required this.step, required this.formKey});
  final int step;
  final GlobalKey<FormState> formKey;

  @override
  ConsumerState<FormStep> createState() => _FormStepState();
}

class _FormStepState extends ConsumerState<FormStep> {
  final _controllers = <String, TextEditingController>{};

  TextEditingController _controller(String key) => _controllers.putIfAbsent(
    key,
    () => TextEditingController(text: ref.read(registrationProvider).values[key] ?? ''),
  );

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(FieldSpec spec) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select your date of birth',
    );
    if (picked == null) return;
    final text = DateFormat('dd/MM/yyyy').format(picked);
    _controller(spec.key).text = text;
    ref.read(registrationProvider.notifier).setValue(spec.key, text);
    widget.formKey.currentState?.validate();
  }

  Widget _field(FieldSpec spec) {
    final notifier = ref.read(registrationProvider.notifier);
    String? validator(String? v) => validateField(spec, v, DateTime.now());

    if (spec.kind == FieldKind.dropdown) {
      return BankDropdown(
        label: spec.label,
        icon: spec.icon,
        items: spec.options,
        value: ref.watch(registrationProvider.select((s) => s.values[spec.key])),
        onChanged: (v) => notifier.setValue(spec.key, v),
        validator: validator,
      );
    }
    final (type, formatters, caps) = switch (spec.kind) {
      FieldKind.email => (TextInputType.emailAddress, <TextInputFormatter>[], TextCapitalization.none),
      FieldKind.phone => (TextInputType.phone, [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]'))], TextCapitalization.none),
      FieldKind.postal => (TextInputType.number, [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)], TextCapitalization.none),
      FieldKind.amount => (const TextInputType.numberWithOptions(decimal: true), [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], TextCapitalization.none),
      FieldKind.id => (TextInputType.text, <TextInputFormatter>[], TextCapitalization.characters),
      _ => (TextInputType.text, <TextInputFormatter>[], TextCapitalization.words),
    };
    return BankTextField(
      fieldKey: ValueKey(spec.key),
      controller: _controller(spec.key),
      label: spec.label,
      icon: spec.icon,
      keyboardType: type,
      inputFormatters: formatters,
      textCapitalization: caps,
      textInputAction: TextInputAction.next,
      validator: validator,
      onChanged: (v) => notifier.setValue(spec.key, v),
      onTap: spec.kind == FieldKind.date ? () => _pickDate(spec) : null,
      suffix: spec.kind == FieldKind.date ? Icon(Icons.calendar_month_rounded, color: context.colors.textSecondary) : null,
    );
  }

  @override
  Widget build(BuildContext context) => Form(
    key: widget.formKey,
    child: Column(
      children: [
        for (final spec in registrationSteps[widget.step].fields)
          Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _field(spec)),
      ],
    ),
  );
}

/// Document capture placeholders wired to [IdentityVerificationService].
class IdentityStep extends ConsumerWidget {
  const IdentityStep({super.key});

  static const _docs = [
    (KycDocument.idFront, 'NIC / passport', 'Photo of the front of your document', Icons.badge_rounded),
    (KycDocument.selfie, 'Selfie check', 'A quick photo to match your ID', Icons.face_rounded),
    (KycDocument.addressProof, 'Proof of address', 'A recent utility bill or bank statement', Icons.home_work_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final state = ref.watch(registrationProvider);
    return Column(
      children: [
        for (final (doc, title, subtitle, icon) in _docs)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _DocTile(
              title: title,
              subtitle: subtitle,
              icon: icon,
              done: state.documents.contains(doc),
              busy: state.capturing == doc,
              onTap: () => ref.read(registrationProvider.notifier).capture(doc),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: c.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Prototype: no document is captured or checked. A real identity provider plugs in here.',
                style: AppTypography.caption.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.done,
    required this.busy,
    required this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final bool done, busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '$title, ${done ? 'verified' : 'not yet provided'}. $subtitle',
      child: Material(
        color: c.inputFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: done ? c.success : c.glassBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: done || busy ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Icon(icon, color: done ? c.success : c.accent),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppTypography.title),
                          Text(subtitle, style: AppTypography.caption.copyWith(color: c.textSecondary)),
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: AppAnimations.scaled(context, AppAnimations.fast),
                      child: busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2))
                          : Icon(
                              done ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                              key: ValueKey(done),
                              color: done ? c.success : c.textSecondary,
                            ),
                    ),
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

/// Summary, sign-in credentials and legal consent.
class ReviewStep extends ConsumerStatefulWidget {
  const ReviewStep({super.key});

  @override
  ConsumerState<ReviewStep> createState() => ReviewStepState();
}

class ReviewStepState extends ConsumerState<ReviewStep> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _terms = false, _privacy = false, _showConsentError = false;

  String get username => _username.text.trim();
  String get password => _password.text;

  /// Validates credentials and consent; the page calls this before submitting.
  bool validate() {
    final formOk = _form.currentState!.validate();
    final consent = _terms && _privacy;
    setState(() => _showConsentError = !consent);
    return formOk && consent;
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _mask(String id) => id.length <= 3 ? id : '${'•' * (id.length - 3)}${id.substring(id.length - 3)}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = ref.watch(registrationProvider.select((s) => s.values));
    final deposit = double.tryParse((v['initialDeposit'] ?? '').replaceAll(',', '')) ?? 0;
    final rows = [
      ('Name', v['fullName'] ?? ''),
      ('ID', _mask((v['idNumber'] ?? '').toUpperCase())),
      ('Mobile', v['mobile'] ?? ''),
      ('Email', v['email'] ?? ''),
      ('Account', '${v['accountType'] ?? ''} · ${formatMoney(deposit)}'),
    ];
    Widget consent(bool value, ValueChanged<bool> onChanged, String label) => Semantics(
      container: true,
      child: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
        value: value,
        activeColor: c.primary,
        onChanged: (x) => setState(() => onChanged(x ?? false)),
        title: Text(label, style: AppTypography.bodySmall),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 72, child: Text(label, style: AppTypography.bodySmall.copyWith(color: c.textSecondary))),
                Expanded(child: Text(value, style: AppTypography.body, maxLines: 2, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        Divider(height: AppSpacing.lg, color: c.divider),
        Form(
          key: _form,
          child: Column(
            children: [
              BankTextField(
                fieldKey: const ValueKey('username'),
                controller: _username,
                label: 'Choose a username',
                icon: Icons.alternate_email_rounded,
                autofillHints: const [AutofillHints.newUsername],
                textInputAction: TextInputAction.next,
                validator: Validators.username,
              ),
              const SizedBox(height: AppSpacing.sm),
              BankTextField(
                fieldKey: const ValueKey('newPassword'),
                controller: _password,
                label: 'Create password',
                icon: Icons.lock_rounded,
                secure: true,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                validator: Validators.password,
              ),
              const SizedBox(height: AppSpacing.sm),
              PasswordRules(controller: _password),
              const SizedBox(height: AppSpacing.sm),
              BankTextField(
                fieldKey: const ValueKey('confirmPassword'),
                controller: _confirm,
                label: 'Confirm password',
                icon: Icons.lock_outline_rounded,
                secure: true,
                textInputAction: TextInputAction.done,
                validator: (x) => Validators.matches(x, _password.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        consent(_terms, (x) => _terms = x, 'I accept the Terms & Conditions'),
        consent(_privacy, (x) => _privacy = x, 'I have read the Privacy Policy'),
        AnimatedSize(
          duration: AppAnimations.scaled(context, AppAnimations.fast),
          child: _showConsentError && !(_terms && _privacy)
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      'Please accept both to continue.',
                      style: AppTypography.bodySmall.copyWith(color: c.error),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
