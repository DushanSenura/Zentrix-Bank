import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/bank_dialog.dart';
import '../../../core/widgets/fade_slide_in.dart';
import '../../../core/widgets/glass_card.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  static const _links = [
    (Icons.person_rounded, 'Personal details', '/profile/edit'),
    (Icons.notifications_rounded, 'Notifications', '/notifications'),
    (Icons.shield_rounded, 'Security center', '/security'),
    (Icons.settings_rounded, 'Settings', '/settings'),
    (Icons.support_agent_rounded, 'Help & support', '/support'),
  ];

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await showBankDialog(
      context,
      title: AppStrings.logout,
      message: AppStrings.logoutConfirm,
      confirmLabel: AppStrings.logout,
      destructive: true,
    );
    if (ok) await ref.read(authProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final user = ref.watch(authProvider);
    final unread = ref.watch(unreadCountProvider);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.navClearance),
        children: [
          const Text(AppStrings.navProfile, style: AppTypography.h1),
          const SizedBox(height: AppSpacing.md),
          FadeSlideIn(
            child: GlassCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: c.primary,
                    child: Text((user?.firstName ?? '?')[0].toUpperCase(), style: AppTypography.h2.copyWith(color: c.onPrimary)),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.fullName ?? '', style: AppTypography.h3),
                        Text('Customer ${user?.customerNumber ?? ''}', style: AppTypography.bodySmall.copyWith(color: c.textSecondary)),
                        if ((user?.email ?? '').isNotEmpty) Text(user!.email, style: AppTypography.caption.copyWith(color: c.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: GlassCard(
              radius: 22,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
              child: Column(
                children: [
                  for (final (icon, label, route) in _links)
                    ListTile(
                      minTileHeight: 56,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(icon, color: c.accent),
                      title: Text(label, style: AppTypography.title),
                      trailing: label == 'Notifications' && unread > 0
                          ? Badge(label: Text('$unread'), child: const Icon(Icons.chevron_right_rounded))
                          : Icon(Icons.chevron_right_rounded, color: c.textSecondary),
                      onTap: () => context.push(route),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FadeSlideIn(
            delay: const Duration(milliseconds: 120),
            child: GlassCard(
              radius: 22,
              onTap: () => _logout(context, ref),
              semanticLabel: AppStrings.logout,
              child: Row(
                children: [
                  Icon(Icons.logout_rounded, color: c.error),
                  const SizedBox(width: AppSpacing.sm),
                  Text(AppStrings.logout, style: AppTypography.title.copyWith(color: c.error)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
