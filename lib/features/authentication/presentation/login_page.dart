import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/bank_logo.dart';
import '../../../core/widgets/bank_text_field.dart';
import '../../../core/widgets/fade_slide_in.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/shake.dart';
import '../domain/auth_repository.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _shake = GlobalKey<ShakeState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _remember = false;
  bool _busy = false;
  bool _leaving = false;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy || !_form.currentState!.validate()) {
      _shake.currentState?.shake();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .signIn(_identifier.text, _password.text);
      if (!mounted) return;
      ref.read(authNoticeProvider.notifier).set(null);
      HapticFeedback.lightImpact();
      // Fade the card out before the router swaps in the dashboard.
      setState(() => _leaving = true);
      await Future<void>.delayed(
        AppAnimations.scaled(context, AppAnimations.normal),
      );
      if (!mounted) return;
      final auth = ref.read(authProvider.notifier);
      _remember ? await auth.startAndRemember(user) : auth.start(user);
    } on AuthException catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _shake.currentState?.shake();
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AnimatedOpacity(
                opacity: _leaving ? 0 : 1,
                duration: AppAnimations.scaled(context, AppAnimations.normal),
                child: AnimatedScale(
                  scale: _leaving ? 0.96 : 1,
                  duration: AppAnimations.scaled(context, AppAnimations.normal),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const FadeSlideIn(child: BankLogo()),
                      const SizedBox(height: AppSpacing.lg),
                      FadeSlideIn(
                        delay: AppAnimations.stagger,
                        child: Shake(
                          key: _shake,
                          child: GlassCard(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: AutofillGroup(
                              child: Form(
                                key: _form,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (ref.watch(authNoticeProvider)
                                        case final notice?)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: AppSpacing.sm,
                                        ),
                                        child: Semantics(
                                          liveRegion: true,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.lock_clock_rounded,
                                                size: 18,
                                                color: c.warning,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  notice,
                                                  style: AppTypography.bodySmall
                                                      .copyWith(
                                                        color: c.textSecondary,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    Semantics(
                                      header: true,
                                      child: const Text(
                                        AppStrings.welcomeBack,
                                        style: AppTypography.h1,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      AppStrings.loginSubtitle,
                                      style: AppTypography.bodyLarge.copyWith(
                                        color: c.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    BankTextField(
                                      fieldKey: const ValueKey('identifier'),
                                      controller: _identifier,
                                      label: AppStrings.identifierLabel,
                                      icon: Icons.person_rounded,
                                      autofillHints: const [
                                        AutofillHints.username,
                                      ],
                                      textInputAction: TextInputAction.next,
                                      validator: (v) =>
                                          Validators.required(v, 'Username'),
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    BankTextField(
                                      fieldKey: const ValueKey('password'),
                                      controller: _password,
                                      label: AppStrings.passwordLabel,
                                      icon: Icons.lock_rounded,
                                      secure: true,
                                      autofillHints: const [
                                        AutofillHints.password,
                                      ],
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) => _signIn(),
                                      validator: (v) =>
                                          Validators.required(v, 'Password'),
                                    ),
                                    AnimatedSize(
                                      duration: AppAnimations.scaled(
                                        context,
                                        AppAnimations.fast,
                                      ),
                                      child: _error == null
                                          ? const SizedBox(
                                              width: double.infinity,
                                            )
                                          : Padding(
                                              padding: const EdgeInsets.only(
                                                top: AppSpacing.sm,
                                              ),
                                              child: Semantics(
                                                liveRegion: true,
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.error_rounded,
                                                      size: 18,
                                                      color: c.error,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        _error!,
                                                        style: AppTypography
                                                            .bodySmall
                                                            .copyWith(
                                                              color: c.error,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: MergeSemantics(
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              onTap: () => setState(
                                                () => _remember = !_remember,
                                              ),
                                              child: ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                      minHeight: AppSpacing
                                                          .touchTarget,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    Checkbox(
                                                      value: _remember,
                                                      onChanged: (v) =>
                                                          setState(
                                                            () => _remember =
                                                                v ?? false,
                                                          ),
                                                      activeColor: c.primary,
                                                      side: BorderSide(
                                                        color: c.textSecondary,
                                                      ),
                                                    ),
                                                    Flexible(
                                                      child: Text(
                                                        AppStrings.rememberMe,
                                                        style: AppTypography
                                                            .bodySmall,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Flexible(
                                          child: TextButton(
                                            style: TextButton.styleFrom(
                                              minimumSize: const Size(
                                                0,
                                                AppSpacing.touchTarget,
                                              ),
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : () => context.push(
                                                    '/forgot-password',
                                                  ),
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                AppStrings.forgotPassword,
                                                style: TextStyle(
                                                  color: c.accent,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    PrimaryButton(
                                      label: AppStrings.signIn,
                                      loading: _busy,
                                      onPressed: _signIn,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FadeSlideIn(
                        delay: AppAnimations.stagger * 2,
                        child: Column(
                          children: [
                            Text(
                              AppStrings.newHere,
                              style: AppTypography.body.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(
                                  0,
                                  AppSpacing.touchTarget,
                                ),
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => context.push('/register'),
                              child: Text(
                                AppStrings.createAccount,
                                style: AppTypography.title.copyWith(
                                  color: c.accent,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Demo: dushan / Dushan@123',
                              style: AppTypography.caption.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
