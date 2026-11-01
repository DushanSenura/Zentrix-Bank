import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/theme/app_animations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/flow_page.dart';
import '../../core/widgets/skeleton.dart';
import '../../shared/models/engagement_models.dart';
import '../../core/widgets/error_view.dart';

String categoryTitle(NotifCategory c) => switch (c) {
  NotifCategory.transactions => 'Transactions',
  NotifCategory.security => 'Security',
  NotifCategory.payments => 'Payments',
  NotifCategory.offers => 'Offers',
  NotifCategory.bankNotices => 'Bank notices',
};

IconData categoryGlyph(NotifCategory c) => switch (c) {
  NotifCategory.transactions => Icons.credit_card_rounded,
  NotifCategory.security => Icons.shield_rounded,
  NotifCategory.payments => Icons.receipt_long_rounded,
  NotifCategory.offers => Icons.local_offer_rounded,
  NotifCategory.bankNotices => Icons.campaign_rounded,
};

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key, this.initial});
  final NotifCategory? initial;

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  late NotifCategory? _filter = widget.initial;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadCountProvider);
    return FlowPage(
      title: 'Notifications',
      trailing: IconButton(
        tooltip: 'Mark all as read',
        constraints: const BoxConstraints(minWidth: AppSpacing.touchTarget, minHeight: AppSpacing.touchTarget),
        onPressed: unread == 0 ? null : ref.read(notificationsProvider.notifier).markAllRead,
        icon: const Icon(Icons.done_all_rounded),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 60, // 48dp chips plus the list's own vertical padding
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: 6),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: ChoiceChip(label: const Text('All'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
                ),
                for (final cat in NotifCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: ChoiceChip(label: Text(categoryTitle(cat)), selected: _filter == cat, onSelected: (_) => setState(() => _filter = cat)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: list.when(
              loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 300, radius: 22)),
              error: (e, _) => ErrorView(error: e, what: 'notifications', onRetry: () => ref.invalidate(notificationsProvider)),
              data: (all) {
                final shown = all.where((n) => _filter == null || n.category == _filter).toList();
                if (shown.isEmpty) {
                  return const EmptyState(icon: Icons.notifications_off_rounded, title: 'No notifications', message: 'You’re all caught up.');
                }
                final now = DateTime.now();
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: c.divider),
                  itemBuilder: (_, i) => _Tile(n: shown[i], now: now, onTap: () => ref.read(notificationsProvider.notifier).markRead(shown[i].id)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.n, required this.now, required this.onTap});
  final AppNotification n;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (sevColor, sevLabel) = switch (n.severity) {
      Severity.critical => (c.error, 'Critical'),
      Severity.warning => (c.warning, 'Warning'),
      Severity.info => (c.accent, 'Info'),
    };
    return Semantics(
      button: true,
      label: '${n.read ? '' : 'Unread. '}${categoryTitle(n.category)}. ${n.title}. ${n.body}. ${timeAgo(n.date, now)}',
      child: InkWell(
        onTap: onTap,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent.withAlpha(36)),
                    child: Icon(categoryGlyph(n.category), size: 22, color: c.accent),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(n.title, style: AppTypography.title.copyWith(fontWeight: n.read ? FontWeight.w500 : FontWeight.w800))),
                            AnimatedScale(
                              scale: n.read ? 0 : 1,
                              duration: AppAnimations.scaled(context, AppAnimations.fast),
                              curve: AppAnimations.spring,
                              child: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(n.body, style: AppTypography.body.copyWith(color: c.textSecondary)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(timeAgo(n.date, now), style: AppTypography.caption.copyWith(color: c.textSecondary)),
                            if (n.category == NotifCategory.security && n.severity != Severity.info) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: sevColor.withAlpha(36)),
                                child: Text(sevLabel, style: AppTypography.caption.copyWith(color: sevColor, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ],
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
    );
  }
}
