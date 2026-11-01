import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/bank_dropdown.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/bank_text_field.dart';
import '../../../core/widgets/glass_bottom_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/payment_models.dart';
import '../domain/banks.dart';

/// Add a beneficiary; or, with [existing], edit its nickname only
/// (bank, number and name are fixed once saved).
Future<bool> showBeneficiarySheet(BuildContext context, {Beneficiary? existing}) async {
  final saved = await showGlassSheet<bool>(context, builder: (_) => _BeneficiaryForm(existing: existing));
  return saved ?? false;
}

class _BeneficiaryForm extends ConsumerStatefulWidget {
  const _BeneficiaryForm({this.existing});
  final Beneficiary? existing;

  @override
  ConsumerState<_BeneficiaryForm> createState() => _BeneficiaryFormState();
}

class _BeneficiaryFormState extends ConsumerState<_BeneficiaryForm> {
  final _form = GlobalKey<FormState>();
  late final _account = TextEditingController(text: widget.existing?.accountNumber);
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _nickname = TextEditingController(text: widget.existing?.nickname);
  late String? _bank = widget.existing?.bank;
  bool _busy = false;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _account.dispose();
    _name.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final notifier = ref.read(beneficiariesProvider.notifier);
    try {
      if (_editing) {
        await notifier.edit(widget.existing!.copyWith(nickname: _nickname.text.trim()));
      } else {
        await notifier.add(
          Beneficiary(
            id: 'b-${DateTime.now().microsecondsSinceEpoch}',
            bank: _bank!,
            accountNumber: _account.text.trim(),
            name: _name.text.trim(),
            nickname: _nickname.text.trim(),
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on PaymentException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      BankSnackbar.show(context, e.message, kind: SnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(AppSpacing.gutter),
    child: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(_editing ? 'Edit nickname' : 'Add beneficiary', style: AppTypography.h3)),
          const SizedBox(height: AppSpacing.md),
          if (_editing)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text('${widget.existing!.name} · ${widget.existing!.bank} ${widget.existing!.masked}', style: AppTypography.body),
            )
          else ...[
            BankDropdown(
              label: 'Bank',
              icon: Icons.account_balance_rounded,
              items: banks,
              value: _bank,
              onChanged: (v) => setState(() => _bank = v),
              validator: (v) => Validators.required(v, 'Bank'),
            ),
            const SizedBox(height: AppSpacing.sm),
            BankTextField(
              fieldKey: const ValueKey('benAccount'),
              controller: _account,
              label: 'Account number',
              icon: Icons.pin_rounded,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(16)],
              textInputAction: TextInputAction.next,
              validator: Validators.accountNumber,
            ),
            const SizedBox(height: AppSpacing.sm),
            BankTextField(
              fieldKey: const ValueKey('benName'),
              controller: _name,
              label: 'Recipient name',
              icon: Icons.person_rounded,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: (v) => Validators.required(v, 'Recipient name'),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          BankTextField(
            fieldKey: const ValueKey('benNickname'),
            controller: _nickname,
            label: 'Nickname (optional)',
            icon: Icons.tag_rounded,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: 'Save', loading: _busy, onPressed: _save),
        ],
      ),
    ),
  );
}
