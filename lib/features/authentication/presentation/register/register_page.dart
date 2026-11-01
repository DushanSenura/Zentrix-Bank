import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/theme/app_animations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/animated_success_icon.dart';
import '../../../../core/widgets/bank_snackbar.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/step_progress.dart';
import 'register_steps.dart';
import 'registration_controller.dart';
import 'registration_fields.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _scroll = ScrollController();
  final _review = GlobalKey<ReviewStepState>();
  // One form key per data step so each step validates independently.
  final _forms = List.generate(3, (_) => GlobalKey<FormState>());

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: AppAnimations.scaled(context, AppAnimations.normal), curve: AppAnimations.standard);
    }
  }

  void _back() {
    FocusScope.of(context).unfocus();
    ref.read(registrationProvider.notifier).back();
    _toTop();
  }

  Future<void> _continue() async {
    final s = ref.read(registrationProvider);
    final notifier = ref.read(registrationProvider.notifier);
    FocusScope.of(context).unfocus();

    if (s.step < identityStep) {
      if (!_forms[s.step].currentState!.validate()) {
        HapticFeedback.heavyImpact();
        return;
      }
    } else if (s.step == identityStep) {
      if (!s.identityComplete) {
        BankSnackbar.show(context, 'Please complete all three verification items.', kind: SnackKind.warning);
        return;
      }
    } else {
      final review = _review.currentState!;
      if (!review.validate()) {
        HapticFeedback.heavyImpact();
        return;
      }
      final error = await notifier.submit(username: review.username, password: review.password);
      if (!mounted) return;
      if (error != null) {
        HapticFeedback.heavyImpact();
        BankSnackbar.show(context, error, kind: SnackKind.error);
      } else {
        HapticFeedback.mediumImpact();
      }
      return;
    }
    notifier.next();
    _toTop();
  }

  Widget _stepBody(int step) {
    if (step < identityStep) return FormStep(key: ValueKey(step), step: step, formKey: _forms[step]);
    if (step == identityStep) return const IdentityStep(key: ValueKey('identity'));
    return ReviewStep(key: _review);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(registrationProvider);
    if (state.created != null) return _Success(name: state.created!.firstName, customer: state.created!.customerNumber);

    final c = context.colors;
    final info = registrationSteps[state.step];
    final dx = state.forward ? 0.06 : -0.06;
    return PopScope(
      canPop: state.step == 0 && !state.submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !state.submitting) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, AppSpacing.gutter, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: state.step == 0 ? 'Back to sign in' : 'Previous step',
                          constraints: const BoxConstraints(minWidth: AppSpacing.touchTarget, minHeight: AppSpacing.touchTarget),
                          onPressed: state.submitting ? null : (state.step == 0 ? context.pop : _back),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        Expanded(child: StepProgress(current: state.step, total: registrationSteps.length)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(header: true, child: Text(info.title, style: AppTypography.h1)),
                          const SizedBox(height: 4),
                          Text(info.subtitle, style: AppTypography.bodyLarge.copyWith(color: c.textSecondary)),
                          const SizedBox(height: AppSpacing.md),
                          GlassCard(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: AnimatedSwitcher(
                              duration: AppAnimations.scaled(context, AppAnimations.normal),
                              switchInCurve: AppAnimations.standard,
                              transitionBuilder: (child, animation) => FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(animation),
                                  child: child,
                                ),
                              ),
                              layoutBuilder: (current, previous) => Stack(
                                alignment: Alignment.topCenter,
                                children: [...previous, ?current],
                              ),
                              child: KeyedSubtree(key: ValueKey(state.step), child: _stepBody(state.step)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.md),
                    child: PrimaryButton(
                      label: state.step == reviewStep ? 'Create Account' : 'Continue',
                      icon: state.step == reviewStep ? Icons.check_rounded : Icons.arrow_forward_rounded,
                      loading: state.submitting,
                      onPressed: _continue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Success extends ConsumerWidget {
  const _Success({required this.name, required this.customer});
  final String name, customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AnimatedSuccessIcon(size: 112),
                  const SizedBox(height: AppSpacing.lg),
                  Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text('Welcome, $name', style: AppTypography.h1, textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Your account is open. Customer number $customer.',
                    style: AppTypography.bodyLarge.copyWith(color: c.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Next, set a PIN for quick and secure sign-in.',
                    style: AppTypography.body.copyWith(color: c.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Continue',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () => ref.read(authProvider.notifier).startAndRemember(ref.read(registrationProvider).created!),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
