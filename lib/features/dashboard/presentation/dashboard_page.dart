import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/fade_slide_in.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/models.dart';
import '../../cards/presentation/card_carousel.dart';
import 'widgets.dart';
import '../../../core/widgets/error_view.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});


  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(accountsProvider);
    ref.invalidate(cardsProvider);
    ref.invalidate(transactionsProvider);
    await Future.wait([
      ref.read(accountsProvider.future),
      ref.read(cardsProvider.future),
      ref.read(transactionsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final visible = ref.watch(balanceVisibleProvider);
    final accounts = ref.watch(accountsProvider);
    final cards = ref.watch(cardsProvider);
    final txs = ref.watch(transactionsProvider);
    final stagger = AppAnimations.stagger;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.navClearance),
          children: [
            FadeSlideIn(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: _Greeting(name: user?.firstName ?? '', onBell: () => context.push('/notifications'), onSearch: () => context.push('/search'), unread: ref.watch(unreadCountProvider)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              delay: stagger,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: accounts.when(
                  loading: () => const _BalanceSkeleton(),
                  error: (e, _) => _InlineError(error: e, onRetry: () => ref.invalidate(accountsProvider)),
                  data: (list) => TotalBalance(
                    total: list.fold(0.0, (s, a) => s + a.balance),
                    visible: visible,
                    onToggle: ref.read(balanceVisibleProvider.notifier).toggle,
                    monthlyChange: _monthlyChange(list, txs.value),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              delay: stagger * 2,
              child: cards.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                  child: Skeleton(height: 200, radius: 28),
                ),
                error: (e, _) => _InlineError(error: e, onRetry: () => ref.invalidate(cardsProvider)),
                data: (list) => CardCarousel(cards: list),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              delay: stagger * 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: Row(
                  children: [
                    Expanded(child: QuickAction(icon: Icons.swap_horiz_rounded, label: 'Transfer', onTap: () => context.push('/transfer'))),
                    Expanded(child: QuickAction(icon: Icons.payments_rounded, label: 'Pay', onTap: () => context.push('/bills'))),
                    Expanded(child: QuickAction(icon: Icons.credit_card_rounded, label: 'My cards', onTap: () => context.push('/cards/manage'))),
                    Expanded(child: QuickAction(icon: Icons.qr_code_scanner_rounded, label: 'Scan', onTap: () => context.push('/qr'))),
                    Expanded(child: QuickAction(icon: Icons.grid_view_rounded, label: 'More', onTap: () => context.go('/payments'))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FadeSlideIn(
              delay: stagger * 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(AppStrings.accounts, actionLabel: 'Open new', onAction: () => context.push('/accounts/open')),
                    const SizedBox(height: AppSpacing.xs),
                    accounts.when(
                      loading: () => const _ListSkeleton(rows: 3, height: 76),
                      error: (e, _) => _InlineError(error: e, onRetry: () => ref.invalidate(accountsProvider)),
                      data: (list) => Column(
                        children: [
                          for (final a in list)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                              child: AccountTile(account: a, balanceVisible: visible, onTap: () => context.push('/accounts/${a.id}')),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              delay: stagger * 5,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(AppStrings.recentTransactions, actionLabel: AppStrings.viewAll, onAction: () => context.push('/transactions')),
                    txs.when(
                      loading: () => const _ListSkeleton(rows: 5, height: 56),
                      error: (e, _) => _InlineError(error: e, onRetry: () => ref.invalidate(transactionsProvider)),
                      data: (list) => list.isEmpty
                          ? const EmptyState(
                              icon: Icons.receipt_long_rounded,
                              title: AppStrings.noTransactions,
                              message: AppStrings.noTransactionsHint,
                            )
                          : GlassCard(
                              radius: 22,
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                              child: Column(
                                children: [
                                  for (final t in list.take(5))
                                    InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () => context.push('/transactions/${t.id}', extra: t),
                                      child: TransactionTile(tx: t, balanceVisible: visible),
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Net movement over the last 30 days relative to the balance 30 days ago.
  double _monthlyChange(List<BankAccount> accounts, List<Transaction>? txs) {
    if (txs == null) return 0;
    final total = accounts.fold(0.0, (s, a) => s + a.balance);
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final net = txs.where((t) => t.date.isAfter(cutoff)).fold(0.0, (s, t) => s + t.amount);
    final before = total - net;
    return before <= 0 ? 0 : net / before * 100;
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.onBell, required this.onSearch, required this.unread});
  final String name;
  final VoidCallback onBell, onSearch;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: c.primary,
          child: Text(
            name.isEmpty ? '?' : name[0].toUpperCase(),
            style: AppTypography.title.copyWith(color: c.onPrimary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greetingFor(DateTime.now()), style: AppTypography.bodySmall.copyWith(color: c.textSecondary)),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.h3),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Search',
          constraints: const BoxConstraints(minWidth: AppSpacing.touchTarget, minHeight: AppSpacing.touchTarget),
          onPressed: onSearch,
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(
          tooltip: unread > 0 ? 'Notifications, $unread unread' : 'Notifications',
          constraints: const BoxConstraints(minWidth: AppSpacing.touchTarget, minHeight: AppSpacing.touchTarget),
          onPressed: onBell,
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.notifications_rounded),
          ),
        ),
      ],
    );
  }
}

class _BalanceSkeleton extends StatelessWidget {
  const _BalanceSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Skeleton(width: 110, height: 16),
      SizedBox(height: 12),
      Skeleton(width: 240, height: 40),
      SizedBox(height: 12),
      Skeleton(width: 140, height: 24, radius: 12),
    ],
  );
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton({required this.rows, required this.height});
  final int rows;
  final double height;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < rows; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Skeleton(height: height, radius: 18),
        ),
    ],
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ErrorView(error: error, what: 'this section', onRetry: onRetry);
}
