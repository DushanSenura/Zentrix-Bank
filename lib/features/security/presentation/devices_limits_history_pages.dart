import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/bank_dialog.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/engagement_models.dart';
import '../../../shared/models/payment_models.dart';
import '../../payments/presentation/authorize_sheet.dart';
import '../../../core/widgets/error_view.dart';

class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final sessions = ref.watch(sessionsProvider);
    final repo = ref.read(securityRepositoryProvider);

    Future<void> logOut(DeviceSession s) async {
      final ok = await showBankDialog(context, title: 'Log out ${s.name}?', message: 'That device will need your password to sign in again.', confirmLabel: 'Log out', destructive: true);
      if (!ok) return;
      await repo.revoke(s.id);
      ref.invalidate(sessionsProvider);
      await ref.read(notificationsProvider.notifier).post(NotifCategory.security, 'Device logged out', '${s.name} was signed out of your account.');
    }

    Future<void> logOutOthers() async {
      final ok = await showBankDialog(context, title: 'Log out all other devices?', message: 'You’ll stay signed in here. Every other device will be signed out.', confirmLabel: 'Log out all', destructive: true);
      if (!ok) return;
      await repo.revokeOthers();
      ref.invalidate(sessionsProvider);
      await ref.read(notificationsProvider.notifier).post(NotifCategory.security, 'Other devices logged out', 'All other devices were signed out of your account.', severity: Severity.warning);
      if (context.mounted) BankSnackbar.show(context, 'All other devices were logged out.', kind: SnackKind.success);
    }

    return FlowPage(
      title: 'Trusted devices',
      child: sessions.when(
        loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 240, radius: 22)),
        error: (e, _) => ErrorView(error: e, what: 'devices', onRetry: () => ref.invalidate(sessionsProvider)),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
          children: [
            for (final s in list)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: GlassCard(
                  radius: 20,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Icon(s.platform.contains('iPad') ? Icons.tablet_mac_rounded : Icons.smartphone_rounded, color: s.current ? c.success : c.accent),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: AppTypography.title),
                            Text(
                              s.current ? 'Active now · ${s.approxLocation}' : 'Last active ${timeAgo(s.lastActive, DateTime.now())} · ${s.approxLocation}',
                              style: AppTypography.caption.copyWith(color: c.textSecondary),
                            ),
                            Text('Approximate location', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                          ],
                        ),
                      ),
                      if (s.current)
                        Text('This device', style: AppTypography.caption.copyWith(color: c.success, fontWeight: FontWeight.w700))
                      else
                        TextButton(
                          style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
                          onPressed: () => logOut(s),
                          child: Text('Log out', style: TextStyle(color: c.error)),
                        ),
                    ],
                  ),
                ),
              ),
            if (list.any((s) => !s.current)) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.touchTarget), foregroundColor: c.error, side: BorderSide(color: c.error.withAlpha(120))),
                onPressed: logOutOthers,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Log out all other devices'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LimitsPage extends ConsumerStatefulWidget {
  const LimitsPage({super.key});

  @override
  ConsumerState<LimitsPage> createState() => _LimitsPageState();
}

class _LimitsPageState extends ConsumerState<LimitsPage> {
  double? _value;
  bool _busy = false;

  Future<void> _save(TransferLimits limits) async {
    final value = _value!;
    final result = await authorizePayment(
      context,
      title: 'Confirm limit change',
      summary: 'Set your daily transfer limit to ${formatMoney(value)}.',
    );
    if (!mounted) return;
    if (result == AuthResult.locked) {
      BankSnackbar.show(context, 'Too many incorrect PINs. Your limit wasn’t changed.', kind: SnackKind.error);
      return;
    }
    if (result != AuthResult.approved) return;
    setState(() => _busy = true);
    try {
      await ref.read(limitsRepositoryProvider).setDaily(value);
      ref.invalidate(limitsProvider);
      await ref.read(notificationsProvider.notifier).post(
        NotifCategory.security,
        'Transfer limit changed',
        'Your daily transfer limit is now ${formatMoney(value)}.',
        severity: value > limits.daily ? Severity.warning : Severity.info,
      );
      if (!mounted) return;
      BankSnackbar.show(context, 'Daily limit saved.', kind: SnackKind.success);
    } on PaymentException catch (e) {
      if (mounted) BankSnackbar.show(context, e.message, kind: SnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final limits = ref.watch(limitsProvider);
    return FlowPage(
      title: 'Transaction limits',
      child: limits.when(
        loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 220, radius: 22)),
        error: (e, _) => ErrorView(error: e, what: 'limits', onRetry: () => ref.invalidate(limitsProvider)),
        data: (l) {
          final value = _value ?? l.daily;
          final changed = value != l.daily;
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
            children: [
              GlassCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Daily transfers', style: AppTypography.body.copyWith(color: c.textSecondary)),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(formatMoney(value), style: AppTypography.amount)),
                    Slider(
                      value: value,
                      max: l.bankMaximum,
                      divisions: (l.bankMaximum / 10000).round(),
                      label: formatWhole(value),
                      semanticFormatterCallback: (v) => '${formatWhole(v)} rupees',
                      onChanged: (v) => setState(() => _value = v),
                    ),
                    Text(
                      'You can set any limit up to the bank’s maximum of ${formatMoney(l.bankMaximum)}. Raising your limit asks for your PIN.',
                      style: AppTypography.caption.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(label: 'Save limit', loading: _busy, onPressed: changed ? () => _save(l) : null),
            ],
          );
        },
      ),
    );
  }
}

class LoginHistoryPage extends ConsumerWidget {
  const LoginHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final history = ref.watch(loginHistoryProvider);
    return FlowPage(
      title: 'Login history',
      child: history.when(
        loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 240, radius: 22)),
        error: (e, _) => ErrorView(error: e, what: 'history', onRetry: () => ref.invalidate(loginHistoryProvider)),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
          itemCount: list.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: c.divider),
          itemBuilder: (_, i) {
            final e = list[i];
            return Semantics(
              label: '${e.success ? 'Successful' : 'Failed'} sign-in on ${e.device}, ${e.approxLocation}, ${DateFormat('d MMMM, h:mm a').format(e.date)}',
              child: ExcludeSemantics(
                child: ListTile(
                  minTileHeight: 64,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(e.success ? Icons.check_circle_rounded : Icons.cancel_rounded, color: e.success ? c.success : c.error),
                  title: Text('${e.success ? 'Signed in' : 'Failed sign-in'} · ${e.device}', style: AppTypography.title),
                  subtitle: Text('${DateFormat('d MMM, h:mm a').format(e.date)} · ${e.approxLocation}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
