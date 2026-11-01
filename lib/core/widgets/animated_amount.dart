import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_animations.dart';
import '../theme/app_typography.dart';
import '../utils/formatters.dart';

/// Counts up to [value] on first build and whenever [value] changes —
/// never on an unrelated rebuild.
class AnimatedAmount extends StatelessWidget {
  const AnimatedAmount({
    super.key,
    required this.value,
    this.style,
    this.currency = 'LKR',
    this.signed = false,
    this.animateFromZero = true,
  });
  final double value;
  final bool animateFromZero;
  final TextStyle? style;
  final String currency;
  final bool signed;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: animateFromZero ? 0 : value, end: value),
    duration: AppAnimations.scaled(context, AppAnimations.number),
    curve: AppAnimations.standard,
    builder: (_, v, _) => Text(
      formatMoney(v, currency: currency, signed: signed),
      style: style ?? AppTypography.amount,
      maxLines: 1,
    ),
  );
}

/// An amount that can be masked; the switch fades and blurs between states.
/// The count-up plays once; revealing the balance again shows it instantly.
class BalanceDisplay extends StatefulWidget {
  const BalanceDisplay({super.key, required this.value, required this.visible, this.style, this.currency = 'LKR'});
  final double value;
  final bool visible;
  final TextStyle? style;
  final String currency;

  @override
  State<BalanceDisplay> createState() => _BalanceDisplayState();
}

class _BalanceDisplayState extends State<BalanceDisplay> {
  bool _countUp = true;

  @override
  void didUpdateWidget(BalanceDisplay old) {
    super.didUpdateWidget(old);
    if (old.visible && !widget.visible) _countUp = false;
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = widget.style ?? AppTypography.amount;
    return AnimatedSwitcher(
      duration: AppAnimations.scaled(context, AppAnimations.normal),
      transitionBuilder: (child, animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (_, child) {
          final blur = (1 - animation.value) * 8;
          return Opacity(
            opacity: animation.value,
            child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: child),
          );
        },
      ),
      child: widget.visible
          ? FittedBox(
              key: const ValueKey('shown'),
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AnimatedAmount(
                value: widget.value,
                style: textStyle,
                currency: widget.currency,
                animateFromZero: _countUp,
              ),
            )
          : Semantics(
              key: const ValueKey('hidden'),
              label: 'Balance hidden',
              child: ExcludeSemantics(child: Text('${widget.currency} ••••••••', style: textStyle, maxLines: 1)),
            ),
    );
  }
}
