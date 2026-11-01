import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Large centred amount entry: `LKR` above an oversized, tabular-figure field.
class AmountInput extends StatelessWidget {
  const AmountInput({
    super.key,
    required this.controller,
    this.validator,
    this.onChanged,
    this.currency = 'LKR',
    this.fieldKey,
    this.autofocus = false,
  });
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final String currency;
  final Key? fieldKey;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Text(currency, style: AppTypography.title.copyWith(color: c.textSecondary)),
        TextFormField(
          key: fieldKey,
          controller: controller,
          autofocus: autofocus,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}(\.\d{0,2})?')),
          ],
          style: AppTypography.amount.copyWith(color: c.textPrimary, fontSize: 44),
          cursorColor: c.accent,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: validator,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: '0.00',
            hintStyle: AppTypography.amount.copyWith(color: c.textSecondary.withAlpha(110), fontSize: 44),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            errorMaxLines: 2,
          ),
        ),
      ],
    );
  }
}
