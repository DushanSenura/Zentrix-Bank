import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_animations.dart';

/// One-shot entrance: fade + small upward slide, optionally delayed for staggering.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero, this.offset = 16});
  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: AppAnimations.slow);
  late final _curve = CurvedAnimation(parent: _controller, curve: AppAnimations.standard);
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted || _timer != null) return;
    if (AppAnimations.reduced(context)) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () => mounted ? _controller.forward() : null);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    child: widget.child,
    builder: (_, child) => Opacity(
      opacity: _curve.value,
      child: Transform.translate(offset: Offset(0, (1 - _curve.value) * widget.offset), child: child),
    ),
  );
}
