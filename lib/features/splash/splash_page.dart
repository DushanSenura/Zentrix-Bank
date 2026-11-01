import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_animations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/bank_logo.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _run();
  }

  Future<void> _run() async {
    // A returning user (stored session + PIN) gets a shorter splash and goes straight to unlock.
    var returning = false;
    try {
      returning = await ref.read(sessionStoreProvider).canUnlock();
    } catch (_) {
      // Unreadable secure storage: fall back to a normal sign-in.
    }
    if (!mounted) return;
    if (returning) {
      _controller.duration = const Duration(milliseconds: 900);
    } else if (AppAnimations.reduced(context)) {
      _controller.duration = const Duration(milliseconds: 300);
    }
    await _controller.forward();
    if (!mounted) return;
    context.go(returning ? '/unlock' : (ref.read(onboardingSeenProvider) ? '/login' : '/onboarding'));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _interval(double begin, double end, [Curve curve = AppAnimations.standard]) =>
      CurvedAnimation(parent: _controller, curve: Interval(begin, end, curve: curve));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final logo = _interval(0.05, 0.45);
    final shine = _interval(0.35, 0.75, Curves.easeInOut);
    final name = _interval(0.45, 0.75);
    final progress = _interval(0.1, 1, Curves.easeInOut);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (_, _) => Opacity(
                opacity: logo.value,
                child: Transform.scale(
                  scale: 0.85 + 0.15 * logo.value,
                  child: ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (rect) => LinearGradient(
                      begin: Alignment(-2 + shine.value * 4, -1),
                      end: Alignment(-1 + shine.value * 4, 1),
                      colors: [Colors.transparent, Colors.white.withAlpha(200), Colors.transparent],
                    ).createShader(rect),
                    child: const BankMark(size: 96),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: name,
              builder: (_, child) => Opacity(
                opacity: name.value,
                child: Transform.translate(offset: Offset(0, (1 - name.value) * 14), child: child),
              ),
              child: Text(AppStrings.bankName, style: AppTypography.h1.copyWith(color: c.textPrimary)),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: 96,
              height: 3,
              child: AnimatedBuilder(
                animation: progress,
                builder: (_, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress.value,
                    backgroundColor: c.divider,
                    color: c.accent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
