import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_animations.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/bank_logo.dart';
import '../core/widgets/primary_button.dart';
import 'providers.dart';

/// Wraps the app to show (1) a banner while the device is offline and (2) a full-screen notice
/// while the bank is in maintenance. The navigator underneath stays mounted, so no screen,
/// form or half-finished payment is lost when either condition clears.
class StatusGate extends ConsumerWidget {
  const StatusGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = !ref.watch(onlineProvider);
    final status = ref.watch(serviceStatusProvider);
    final media = MediaQuery.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: status.maintenance,
          child: ExcludeSemantics(
            excluding: status.maintenance,
            child: Column(
              children: [
                AnimatedSize(
                  duration: AppAnimations.scaled(context, AppAnimations.fast),
                  alignment: Alignment.topCenter,
                  child: offline ? const OfflineBanner() : const SizedBox(width: double.infinity),
                ),
                Expanded(
                  // The banner already sits below the status bar, so the page must not inset for it twice.
                  child: MediaQuery(
                    data: offline ? media.removePadding(removeTop: true) : media,
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (status.maintenance) MaintenanceScreen(message: status.message, retryAfter: status.retryAfter),
      ],
    );
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Pick whichever of black/white reads better on the warning colour in the current theme.
    final fg = ThemeData.estimateBrightnessForColor(c.warning) == Brightness.dark ? Colors.white : Colors.black;
    return Semantics(
      liveRegion: true,
      container: true,
      label: 'You’re offline. Balances may be out of date and payments are paused.',
      child: Material(
        color: c.warning,
        child: SafeArea(
          bottom: false,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(Icons.wifi_off_rounded, size: 18, color: fg),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'You’re offline. Balances may be out of date and payments are paused.',
                      style: AppTypography.bodySmall.copyWith(color: fg, fontWeight: FontWeight.w700),
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

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key, this.message, this.retryAfter});
  final String? message;
  final Duration? retryAfter;

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  bool _checking = false;
  bool _stillDown = false;

  Future<void> _retry() async {
    setState(() {
      _checking = true;
      _stillDown = false;
    });
    final up = await ref.read(serviceStatusProvider.notifier).retry();
    if (mounted) {
      setState(() {
        _checking = false;
        _stillDown = !up;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wait = widget.retryAfter;
    return Material(
      color: c.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Semantics(
                scopesRoute: true,
                explicitChildNodes: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BankLogo(size: 40),
                    const SizedBox(height: AppSpacing.xl),
                    Icon(Icons.construction_rounded, size: 56, color: c.accent),
                    const SizedBox(height: AppSpacing.md),
                    Semantics(header: true, child: const Text('We’ll be right back', style: AppTypography.h1, textAlign: TextAlign.center)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      widget.message ?? 'Zentrix Bank is briefly unavailable while we make improvements.',
                      style: AppTypography.bodyLarge.copyWith(color: c.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Your money and your information are safe. ${wait == null ? '' : 'Please try again in about ${wait.inMinutes < 1 ? 'a minute' : '${wait.inMinutes} minutes'}.'}',
                      style: AppTypography.body.copyWith(color: c.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    if (_stillDown)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Semantics(
                          liveRegion: true,
                          child: Text('Still unavailable. Please try again shortly.', style: AppTypography.bodySmall.copyWith(color: c.error), textAlign: TextAlign.center),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(label: 'Try again', icon: Icons.refresh_rounded, loading: _checking, onPressed: _retry),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
