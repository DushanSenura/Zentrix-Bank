import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';

/// Text input with an animated focus glow. Set [secure] for passwords: it adds
/// the show/hide toggle and disables suggestions and autocorrect.
class BankTextField extends StatefulWidget {
  const BankTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.validator,
    this.keyboardType,
    this.secure = false,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.fieldKey,
    this.onChanged,
    this.onTap,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.suffix,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool secure;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;
  final ValueChanged<String>? onChanged;

  /// When set the field is read-only and acts as a button (e.g. a date picker).
  final VoidCallback? onTap;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final Widget? suffix;

  @override
  State<BankTextField> createState() => _BankTextFieldState();
}

class _BankTextFieldState extends State<BankTextField> {
  bool _focused = false;
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: AppAnimations.scaled(context, AppAnimations.fast),
      decoration: BoxDecoration(
        borderRadius: AppRadius.mdAll,
        boxShadow: _focused ? AppShadows.glow(c.accent) : const [],
      ),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: TextFormField(
          key: widget.fieldKey,
          controller: widget.controller,
          obscureText: widget.secure && _hidden,
          enableSuggestions: !widget.secure,
          autocorrect: !widget.secure,
          keyboardType: widget.secure ? TextInputType.visiblePassword : widget.keyboardType,
          autofillHints: widget.autofillHints,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onSubmitted,
          onChanged: widget.onChanged,
          onTap: widget.onTap,
          readOnly: widget.onTap != null,
          inputFormatters: widget.inputFormatters,
          textCapitalization: widget.textCapitalization,
          validator: widget.validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          style: TextStyle(color: c.textPrimary, fontSize: 16),
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: Icon(widget.icon, color: _focused ? c.accent : c.textSecondary),
            suffixIcon: widget.secure
                ? IconButton(
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _hidden = !_hidden),
                    icon: AnimatedSwitcher(
                      duration: AppAnimations.scaled(context, AppAnimations.fast),
                      child: Icon(
                        _hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        key: ValueKey(_hidden),
                        color: c.textSecondary,
                      ),
                    ),
                  )
                : widget.suffix,
          ),
        ),
      ),
    );
  }
}
