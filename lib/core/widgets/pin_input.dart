import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Six-dot PIN entry with an on-screen keypad. The PIN is held only in widget state
/// and handed to [onCompleted]; it is never logged or stored here.
///
/// Drive feedback through a `GlobalKey<PinInputState>`: `showError()`, `showSuccess()`, `clear()`.
class PinInput extends StatefulWidget {
  const PinInput({super.key, required this.onCompleted, this.length = 6, this.leading, this.enabled = true});
  final ValueChanged<String> onCompleted;
  final int length;

  /// Optional key shown bottom-left (e.g. a biometric button).
  final Widget? leading;
  final bool enabled;

  @override
  State<PinInput> createState() => PinInputState();
}

class PinInputState extends State<PinInput> with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  String _pin = '';
  bool _error = false;
  bool _success = false;

  void clear() => setState(() {
    _pin = '';
    _error = false;
    _success = false;
  });

  void showError() {
    HapticFeedback.heavyImpact();
    setState(() => _error = true);
    if (!AppAnimations.reduced(context)) _shake.forward(from: 0);
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (mounted) clear();
    });
  }

  void showSuccess() {
    HapticFeedback.lightImpact();
    setState(() => _success = true);
  }

  void _digit(String d) {
    if (!widget.enabled || _pin.length >= widget.length || _error || _success) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == widget.length) widget.onCompleted(_pin);
  }

  void _backspace() {
    if (!widget.enabled || _pin.isEmpty || _error || _success) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dotColor = _error ? c.error : (_success ? c.success : c.accent);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          label: '${_pin.length} of ${widget.length} digits entered',
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _shake,
              builder: (_, child) => Transform.translate(
                offset: Offset(math.sin(_shake.value * math.pi * 5) * 10 * (1 - _shake.value), 0),
                child: child,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.length; i++)
                    AnimatedContainer(
                      duration: AppAnimations.scaled(context, AppAnimations.fast),
                      curve: AppAnimations.spring,
                      margin: const EdgeInsets.symmetric(horizontal: 9),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length ? dotColor : Colors.transparent,
                        border: Border.all(color: i < _pin.length ? dotColor : c.textSecondary, width: 1.6),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            children: [
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(children: [for (final d in row) _Key(label: d, onTap: () => _digit(d))]),
              Row(
                children: [
                  Expanded(child: SizedBox(height: 72, child: Center(child: widget.leading))),
                  _Key(label: '0', onTap: () => _digit('0')),
                  _Key(icon: Icons.backspace_rounded, semantic: 'Delete', onTap: _backspace),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, this.semantic, required this.onTap});
  final String? label, semantic;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: SizedBox(
        height: 72,
        child: Center(
          child: Semantics(
            button: true,
            label: semantic ?? label,
            child: InkResponse(
              onTap: onTap,
              radius: 38,
              child: ExcludeSemantics(
                child: Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: label == null ? Colors.transparent : c.glassFill,
                    border: label == null ? null : Border.all(color: c.glassBorder),
                  ),
                  child: label != null
                      ? Text(label!, style: AppTypography.h2)
                      : Icon(icon, color: c.textSecondary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
