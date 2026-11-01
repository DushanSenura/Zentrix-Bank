import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_animations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/primary_button.dart';

const _icons = [
  [Icons.account_balance_wallet_rounded, Icons.trending_up_rounded, Icons.savings_rounded],
  [Icons.swap_horiz_rounded, Icons.credit_card_rounded, Icons.receipt_long_rounded],
  [Icons.shield_rounded, Icons.fingerprint_rounded, Icons.verified_user_rounded],
];

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> with SingleTickerProviderStateMixin {
  final _pages = PageController();
  late final _float = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  int _index = 0;

  bool get _last => _index == AppStrings.onboarding.length - 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppAnimations.reduced(context)) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _float.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(onboardingSeenProvider.notifier).markSeen();
    context.go('/login');
  }

  void _next() => _last
      ? _finish()
      : _pages.nextPage(duration: AppAnimations.scaled(context, AppAnimations.slow), curve: AppAnimations.standard);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedOpacity(
                    opacity: _last ? 0 : 1,
                    duration: AppAnimations.scaled(context, AppAnimations.fast),
                    child: TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
                      onPressed: _last ? null : _finish,
                      child: Text(AppStrings.skip, style: TextStyle(color: c.textSecondary)),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: AppStrings.onboarding.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) => _Slide(
                      title: AppStrings.onboarding[i].$1,
                      body: AppStrings.onboarding[i].$2,
                      icons: _icons[i],
                      float: _float,
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < AppStrings.onboarding.length; i++)
                      AnimatedContainer(
                        duration: AppAnimations.scaled(context, AppAnimations.normal),
                        curve: AppAnimations.standard,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _index ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: i == _index ? c.accent : c.divider,
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.gutter),
                  child: PrimaryButton(
                    label: _last ? AppStrings.getStarted : AppStrings.next,
                    icon: Icons.arrow_forward_rounded,
                    onPressed: _next,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.title, required this.body, required this.icons, required this.float});
  final String title, body;
  final List<IconData> icons;
  final Animation<double> float;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              height: 260,
              child: AnimatedBuilder(
                animation: float,
                builder: (_, _) {
                  final t = float.value * math.pi;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset(-70, -50 + math.sin(t) * 8),
                        child: _Tile(icons[1], 72, c.secondary),
                      ),
                      Transform.translate(
                        offset: Offset(78, 56 + math.cos(t) * 8),
                        child: _Tile(icons[2], 64, c.success),
                      ),
                      Transform.translate(
                        offset: Offset(0, math.sin(t + 1) * 6),
                        child: _Tile(icons[0], 104, c.accent),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(header: true, child: Text(title, style: AppTypography.h1, textAlign: TextAlign.center)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            style: AppTypography.bodyLarge.copyWith(color: c.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.size, this.color);
  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: GlassCard(
      radius: size * 0.3,
      padding: EdgeInsets.zero,
      child: Center(child: Icon(icon, size: size * 0.46, color: color)),
    ),
  );
}
