import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/models.dart';
import '../../payments/presentation/payment_widgets.dart';
import '../../statements/domain/statement.dart';
import '../../transactions/domain/transaction_filter.dart';
import 'widgets.dart';

String accountTypeLabel(AccountType t) => switch (t) {
  AccountType.savings => 'Savings account',
  AccountType.current => 'Current account',
  AccountType.fixedDeposit => 'Fixed deposit',
  AccountType.foreignCurrency => 'Foreign currency account',
};

/// One account: its balance, this month's flow, the latest activity and the things you can do with it.
class AccountDetailPage extends ConsumerWidget {
  const AccountDetailPage({super.key, required this.accountId});
  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final txs = ref.watch(transactionsProvider);
    final visible = ref.watch(balanceVisibleProvider);
    return FlowPage(
      title: 'Account',
      child: accounts.when(
        loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 260, radius: 28)),
        error: (e, _) => ErrorView(error: e, what: 'this account', onRetry: () => ref.invalidate(accountsProvider)),
        data: (all) {
          final account = all.where((a) => a.id == accountId).firstOrNull;
          if (account == null) {
            return const EmptyState(icon: Icons.search_off_rounded, title: 'Account not found', message: 'It may have been closed, or the link is out of date.');
          }
          return _Body(account: account, txs: txs, visible: visible);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.account, required this.txs, required this.visible});
  final BankAccount account;
  final AsyncValue<List<Transaction>> txs;
  final bool visible;

  void _showAllTransactions(BuildContext context, WidgetRef ref) {
    ref.read(transactionFilterProvider.notifier).set(const TransactionFilter().withFilters(accountId: account.id));
    context.push('/transactions');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final payable = account.type == AccountType.savings || account.type == AccountType.current;
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(account.name, style: AppTypography.h3)),
              Text('${accountTypeLabel(account.type)} · ${account.maskedNumber}', style: AppTypography.body.copyWith(color: c.textSecondary)),
              const SizedBox(height: AppSpacing.md),
              Text('Available balance', style: AppTypography.caption.copyWith(color: c.textSecondary)),
              Semantics(
                label: visible ? 'Balance ${formatMoney(account.balance)}' : 'Balance hidden',
                child: ExcludeSemantics(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(visible ? formatMoney(account.balance) : 'LKR ••••••', style: AppTypography.amount),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(account.active ? Icons.check_circle_rounded : Icons.pause_circle_rounded, size: 18, color: account.active ? c.success : c.warning),
                  const SizedBox(width: 6),
                  Text(account.active ? 'Active' : 'Inactive', style: AppTypography.bodySmall),
                  const SizedBox(width: AppSpacing.md),
                  Text(account.currency, style: AppTypography.bodySmall.copyWith(color: c.textSecondary)),
                ],
              ),
              if (account.interestRate != null || account.maturityDate != null) ...[
                const SizedBox(height: AppSpacing.xs),
                if (account.interestRate != null) Text('Interest: ${account.interestRate}% a year', style: AppTypography.bodySmall.copyWith(color: c.textSecondary)),
                if (account.maturityDate != null) Text('Pays out on ${formatGroupDate(account.maturityDate!, DateTime.now())}', style: AppTypography.bodySmall.copyWith(color: c.textSecondary)),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (payable)
          Row(
            children: [
              Expanded(child: _Action(icon: Icons.north_east_rounded, label: 'Send', onTap: () => context.push('/transfer?from=${account.id}'))),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: _Action(icon: Icons.description_rounded, label: 'Statement', onTap: () => context.push('/statements?account=${account.id}'))),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: _Action(icon: Icons.receipt_long_rounded, label: 'History', onTap: () => _showAllTransactions(context, ref))),
            ],
          )
        else ...[
          if (account.type == AccountType.fixedDeposit)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _Action(icon: Icons.lock_clock_rounded, label: 'Fixed deposit details', onTap: () => context.push('/fixed-deposits')),
            ),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: c.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Money can’t be sent from a ${accountTypeLabel(account.type).toLowerCase()}. Move funds to a savings or current account first.',
                  style: AppTypography.caption.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        txs.when(
          loading: () => const Skeleton(height: 200, radius: 22),
          error: (e, _) => ErrorView(error: e, what: 'transactions', onRetry: () => ref.invalidate(transactionsProvider)),
          data: (all) {
            final mine = all.where((t) => t.accountId == account.id).toList()..sort((a, b) => b.date.compareTo(a.date));
            final month = summarize(statementTransactions(all, account.id, DateTime(now.year, now.month)));
            if (mine.isEmpty) {
              return const EmptyState(icon: Icons.receipt_long_rounded, title: 'No activity yet', message: 'Payments and deposits on this account will appear here.');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: const Text('This month', style: AppTypography.h3)),
                const SizedBox(height: AppSpacing.xs),
                GlassCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      SummaryRow('Money in', visible ? formatMoney(month.moneyIn) : 'LKR ••••••'),
                      SummaryRow('Money out', visible ? formatMoney(month.moneyOut) : 'LKR ••••••'),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: Semantics(header: true, child: const Text('Recent activity', style: AppTypography.h3))),
                    TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
                      onPressed: () => _showAllTransactions(context, ref),
                      child: Text('See all', style: TextStyle(color: c.accent)),
                    ),
                  ],
                ),
                GlassCard(
                  radius: 22,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  child: Column(children: [for (final t in mine.take(6)) TransactionTile(tx: t, balanceVisible: visible)]),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      onTap: onTap,
      semanticLabel: label,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, color: c.accent), const SizedBox(height: 4), Text(label, style: AppTypography.caption)],
        ),
      ),
    );
  }
}
