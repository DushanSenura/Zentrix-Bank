import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/bank_dialog.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/models/engagement_models.dart';

class SecurityCenterPage extends ConsumerWidget {
  const SecurityCenterPage({super.key});

  Widget _nav(BuildContext context, IconData icon, String title, String subtitle, String route) {
    final c = context.colors;
    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      onTap: () => context.push(route),
      semanticLabel: '$title. $subtitle',
      child: ExcludeSemantics(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: 60,
          leading: Icon(icon, color: c.accent),
          title: Text(title, style: AppTypography.title),
          subtitle: Text(subtitle, style: AppTypography.caption.copyWith(color: c.textSecondary)),
          trailing: Icon(Icons.chevron_right_rounded, color: c.textSecondary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final settings = ref.watch(securityProvider).value;
    final twoFactor = ref.watch(twoFactorProvider).value ?? false;
    final limits = ref.watch(limitsProvider).value;
    final alerts = (ref.watch(notificationsProvider).value ?? const <AppNotification>[]).where((n) => n.category == NotifCategory.security).take(3).toList();
    Widget gap() => const SizedBox(height: AppSpacing.xs);

    return FlowPage(
      title: 'Security center',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
        children: [
          _nav(context, Icons.password_rounded, 'Change password', 'Confirm your current password first', '/security/password'),
          gap(),
          _nav(context, Icons.pin_rounded, 'Change transaction PIN', settings?.hasPin == true ? 'Confirm your current PIN first' : 'Create your PIN', '/security/pin'),
          gap(),
          if (settings != null && settings.hasPin && settings.biometricAvailable) ...[
            GlassCard(
              radius: 20,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              child: MergeSemantics(
                child: Row(
                  children: [
                    Icon(Icons.fingerprint_rounded, color: c.accent),
                    const SizedBox(width: AppSpacing.sm),
                    const Expanded(child: Text('Biometric login', style: AppTypography.title)),
                    Switch(
                      value: settings.biometricEnabled,
                      onChanged: (on) async {
                        final ok = await ref.read(securityProvider.notifier).setBiometric(on, reason: 'Confirm biometric unlock');
                        if (!ok && context.mounted) BankSnackbar.show(context, 'Biometric unlock wasn’t changed.', kind: SnackKind.warning);
                      },
                    ),
                  ],
                ),
              ),
            ),
            gap(),
          ],
          GlassCard(
            radius: 20,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: MergeSemantics(
              child: Row(
                children: [
                  Icon(Icons.verified_user_rounded, color: c.accent),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Two-factor authentication', style: AppTypography.title),
                        Text('Prototype setting — no codes are sent.', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                      ],
                    ),
                  ),
                  Switch(
                    value: twoFactor,
                    onChanged: (on) async {
                      final ok = await showBankDialog(
                        context,
                        title: on ? 'Turn on two-factor?' : 'Turn off two-factor?',
                        message: on ? 'You’ll be asked for a second step when signing in on a new device.' : 'Your account will be less protected.',
                        confirmLabel: on ? 'Turn on' : 'Turn off',
                        destructive: !on,
                      );
                      if (!ok) return;
                      await ref.read(securityRepositoryProvider).setTwoFactor(on);
                      ref.invalidate(twoFactorProvider);
                      await ref.read(notificationsProvider.notifier).post(
                        NotifCategory.security,
                        on ? 'Two-factor turned on' : 'Two-factor turned off',
                        on ? 'Extra verification is now required on new devices.' : 'Extra verification was switched off.',
                        severity: on ? Severity.info : Severity.warning,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          gap(),
          _nav(context, Icons.devices_rounded, 'Trusted devices & sessions', 'See where you’re signed in', '/security/devices'),
          gap(),
          _nav(context, Icons.speed_rounded, 'Transaction limits', limits == null ? 'Set your daily transfer limit' : 'Daily transfers up to ${formatMoney(limits.daily)}', '/security/limits'),
          gap(),
          _nav(context, Icons.history_toggle_off_rounded, 'Login history', 'Recent sign-in attempts', '/security/history'),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(child: Semantics(header: true, child: const Text('Security alerts', style: AppTypography.h3))),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
                onPressed: () => context.push('/notifications', extra: NotifCategory.security),
                child: Text('See all', style: TextStyle(color: c.accent)),
              ),
            ],
          ),
          for (final a in alerts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: GlassCard(
                radius: 20,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      a.severity == Severity.info ? Icons.info_rounded : Icons.warning_amber_rounded,
                      color: switch (a.severity) {
                        Severity.critical => c.error,
                        Severity.warning => c.warning,
                        Severity.info => c.accent,
                      },
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.title, style: AppTypography.title),
                          Text(a.body, style: AppTypography.bodySmall.copyWith(color: c.textSecondary)),
                          Text(timeAgo(a.date, DateTime.now()), style: AppTypography.caption.copyWith(color: c.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
