import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/bank_snackbar.dart';
import '../../core/widgets/flow_page.dart';
import '../../core/widgets/glass_card.dart';
import '../../shared/models/engagement_models.dart';
import '../../shared/models/models.dart';
import '../dashboard/data/mock_banking_repositories.dart';
import '../notifications/notifications_page.dart';
import '../payments/presentation/payment_widgets.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Widget _section(BuildContext context, String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.xs),
          child: Semantics(header: true, child: Text(title, style: AppTypography.title.copyWith(color: context.colors.textSecondary))),
        ),
        GlassCard(radius: 22, padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs), child: Column(children: children)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final mode = ref.watch(themeModeProvider);
    final timeout = ref.watch(lockTimeoutProvider);
    final visible = ref.watch(balanceVisibleProvider);
    final accounts = payableAccounts(ref.watch(accountsProvider).value ?? const []);
    final defaultAccount = accounts.where((a) => a.id == settings.defaultAccountId).firstOrNull ?? accounts.firstOrNull;

    return FlowPage(
      title: 'Settings',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
        children: [
          _section(context, 'Appearance', [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('Auto')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
                ),
              ),
            ),
          ]),
          _section(context, 'Language', [
            const ListTile(
              minTileHeight: AppSpacing.touchTarget,
              contentPadding: EdgeInsets.zero,
              title: Text('English', style: AppTypography.body),
              trailing: Icon(Icons.check_rounded),
            ),
            for (final l in const ['සිංහල', 'தமிழ்'])
              ListTile(
                enabled: false,
                minTileHeight: AppSpacing.touchTarget,
                contentPadding: EdgeInsets.zero,
                title: Text(l, style: AppTypography.body),
                trailing: Text('Coming soon', style: AppTypography.caption.copyWith(color: c.textSecondary)),
              ),
          ]),
          _section(context, 'Notifications', [
            for (final cat in NotifCategory.values)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(categoryTitle(cat), style: AppTypography.body),
                subtitle: cat == NotifCategory.security ? Text('Always on for your protection', style: AppTypography.caption.copyWith(color: c.textSecondary)) : null,
                value: cat == NotifCategory.security || !settings.mutedCategories.contains(cat),
                onChanged: cat == NotifCategory.security ? null : (on) => notifier.setMuted(cat, muted: !on),
              ),
          ]),
          _section(context, 'Privacy & security', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show balances', style: AppTypography.body),
              subtitle: Text('Applies until you sign out', style: AppTypography.caption.copyWith(color: c.textSecondary)),
              value: visible,
              onChanged: (_) => ref.read(balanceVisibleProvider.notifier).toggle(),
            ),
            ListTile(
              minTileHeight: AppSpacing.touchTarget,
              contentPadding: EdgeInsets.zero,
              title: const Text('Lock after', style: AppTypography.body),
              subtitle: Text('Ask for your PIN after being idle or in the background', style: AppTypography.caption.copyWith(color: c.textSecondary)),
              trailing: DropdownButton<int>(
                value: timeout.inMinutes,
                underline: const SizedBox.shrink(),
                dropdownColor: c.surface,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 min')),
                  DropdownMenuItem(value: 2, child: Text('2 min')),
                  DropdownMenuItem(value: 5, child: Text('5 min')),
                  DropdownMenuItem(value: 15, child: Text('15 min')),
                ],
                onChanged: (m) => m == null ? null : ref.read(lockTimeoutProvider.notifier).set(Duration(minutes: m)),
              ),
            ),
            ListTile(
              minTileHeight: AppSpacing.touchTarget,
              contentPadding: EdgeInsets.zero,
              title: const Text('Security center', style: AppTypography.body),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/security'),
            ),
          ]),
          _section(context, 'Accessibility', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reduce motion', style: AppTypography.body),
              subtitle: Text('Shortens or removes animations. Your device setting is respected too.', style: AppTypography.caption.copyWith(color: c.textSecondary)),
              value: settings.reduceMotion,
              onChanged: notifier.setReduceMotion,
            ),
          ]),
          if (defaultAccount != null)
            _section(context, 'Payments', [
              ListTile(
                minTileHeight: AppSpacing.touchTarget,
                contentPadding: EdgeInsets.zero,
                title: const Text('Default account', style: AppTypography.body),
                subtitle: Text('${defaultAccount.name} ${defaultAccount.maskedNumber}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final id = await pickAccount(context, accounts, defaultAccount.id, title: 'Default account');
                  if (id != null) notifier.setDefaultAccount(id);
                },
              ),
              ListTile(
                enabled: false,
                minTileHeight: AppSpacing.touchTarget,
                contentPadding: EdgeInsets.zero,
                title: const Text('Currency display', style: AppTypography.body),
                trailing: Text('LKR', style: AppTypography.caption.copyWith(color: c.textSecondary)),
              ),
            ]),
          // Only when running on the built-in mock bank. With a real server these things happen in the bank's own systems.
          if (ref.watch(apiConfigProvider) == null) _section(context, 'Prototype tools', [_PrototypeTools()]),
        ],
      ),
    );
  }
}

/// Stand-ins for what bank staff and the passing of time do, so the card flows can be tried without a real bank.
/// Not part of a customer-facing app: it exists only while the app runs on its mock bank.
class _PrototypeTools extends ConsumerWidget {
  void _say(BuildContext context, String message) => BankSnackbar.show(context, message, kind: SnackKind.info);

  Future<void> _refreshCards(WidgetRef ref) async {
    ref.invalidate(cardsProvider);
    ref.invalidate(notificationsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final repo = ref.watch(cardRepositoryProvider);
    if (repo is! MockCardRepository) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            'Prototype only. These play the part of the bank’s staff and of time passing; a real bank does them in its own systems.',
            style: AppTypography.caption.copyWith(color: c.textSecondary),
          ),
        ),
        ListTile(
          minTileHeight: AppSpacing.touchTarget,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.admin_panel_settings_rounded, color: c.accent),
          title: const Text('Bank: approve waiting virtual cards', style: AppTypography.body),
          subtitle: Text('Activates every virtual card that is waiting for the bank.', style: AppTypography.caption.copyWith(color: c.textSecondary)),
          onTap: () async {
            final n = repo.approvePendingVirtualCards();
            await _refreshCards(ref);
            if (context.mounted) _say(context, n == 0 ? 'No virtual cards are waiting.' : '$n virtual ${n == 1 ? 'card' : 'cards'} approved.');
          },
        ),
        ListTile(
          minTileHeight: AppSpacing.touchTarget,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.fast_forward_rounded, color: c.accent),
          title: const Text('Time: skip 5 days', style: AppTypography.body),
          subtitle: Text('A debit card being prepared becomes ready to collect.', style: AppTypography.caption.copyWith(color: c.textSecondary)),
          onTap: () async {
            repo.skipDays(debitCardPreparationDays);
            await _refreshCards(ref);
            if (context.mounted) _say(context, 'Moved the bank’s clock forward $debitCardPreparationDays days.');
          },
        ),
      ],
    );
  }
}
