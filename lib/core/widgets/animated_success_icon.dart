import 'dart:ui' show PathMetric;
import 'package:flutter/material.dart';
import '../theme/app_animations.dart';
import '../theme/app_colors.dart';

/// Circle that draws itself, then a check mark, with a single soft ripple.
class AnimatedSuccessIcon extends StatefulWidget {
  const AnimatedSuccessIcon({super.key, this.size = 96});
  final double size;

  @override
  State<AnimatedSuccessIcon> createState() => _AnimatedSuccessIconState();
}

class _AnimatedSuccessIconState extends State<AnimatedSuccessIcon> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: AppAnimations.success + const Duration(milliseconds: 200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) return;
    AppAnimations.reduced(context) ? _controller.value = 1 : _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Success',
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, _) => CustomPaint(painter: _SuccessPainter(_controller.value, context.colors.success)),
        ),
      ),
    ),
  );
}

class _SuccessPainter extends CustomPainter {
  _SuccessPainter(this.t, this.color);
  final double t;
  final Color color;

  Path _partial(Path path, double fraction) {
    final out = Path();
    var remaining = path.computeMetrics().fold<double>(0, (s, m) => s + m.length) * fraction;
    for (final PathMetric m in path.computeMetrics()) {
      final take = remaining.clamp(0, m.length).toDouble();
      out.addPath(m.extractPath(0, take), Offset.zero);
      remaining -= take;
      if (remaining <= 0) break;
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final circleT = Curves.easeOutCubic.transform((t / 0.55).clamp(0, 1));
    canvas.drawPath(_partial(Path()..addOval(Rect.fromCircle(center: center, radius: r)), circleT), stroke);

    final checkT = Curves.easeOutCubic.transform(((t - 0.45) / 0.35).clamp(0, 1));
    final w = size.width, h = size.height;
    final check = Path()
      ..moveTo(w * .30, h * .52)
      ..lineTo(w * .45, h * .66)
      ..lineTo(w * .71, h * .38);
    canvas.drawPath(_partial(check, checkT), stroke);

    final rippleT = ((t - 0.7) / 0.3).clamp(0.0, 1.0);
    if (rippleT > 0 && rippleT < 1) {
      canvas.drawCircle(
        center,
        r + rippleT * size.width * 0.12,
        Paint()
          ..color = color.withAlpha(((1 - rippleT) * 90).round())
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_SuccessPainter old) => old.t != t || old.color != color;
}
