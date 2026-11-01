import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_animations.dart';

/// Wraps a child and shakes it horizontally on demand: `key.currentState?.shake()`.
class Shake extends StatefulWidget {
  const Shake({super.key, required this.child});
  final Widget child;

  @override
  State<Shake> createState() => ShakeState();
}

class ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  void shake() {
    if (!AppAnimations.reduced(context)) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (_, child) => Transform.translate(
      offset: Offset(math.sin(_controller.value * math.pi * 5) * 8 * (1 - _controller.value), 0),
      child: child,
    ),
  );
}
