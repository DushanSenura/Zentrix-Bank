import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

class BankDropdown extends StatelessWidget {
  const BankDropdown({
    super.key,
    required this.label,
    required this.icon,
    required this.items,
    required this.value,
    required this.onChanged,
    this.validator,
  });
  final String label;
  final IconData icon;
  final List<String> items;
  final String? value;
  final ValueChanged<String> onChanged;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DropdownButtonFormField<String>(
      initialValue: items.contains(value) ? value : null,
      isExpanded: true,
      borderRadius: AppRadius.mdAll,
      dropdownColor: c.surface,
      icon: Icon(Icons.keyboard_arrow_down_rounded, color: c.textSecondary),
      style: TextStyle(color: c.textPrimary, fontSize: 16, fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: c.textSecondary)),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: validator,
      items: [
        for (final item in items) DropdownMenuItem(value: item, child: Text(item, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}
