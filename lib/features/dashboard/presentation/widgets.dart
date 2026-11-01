import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/animated_amount.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../shared/models/models.dart';

IconData categoryIcon(TxCategory c) => switch (c) {
  TxCategory.food => Icons.restaurant_rounded,
  TxCategory.shopping => Icons.shopping_bag_rounded,
  TxCategory.transport => Icons.directions_car_rounded,
  TxCategory.bills => Icons.receipt_long_rounded,
  TxCategory.entertainment => Icons.movie_rounded,
  TxCategory.health => Icons.favorite_rounded,
  TxCategory.education => Icons.school_rounded,
  TxCategory.income => Icons.south_west_rounded,
  TxCategory.transfer => Icons.swap_horiz_rounded,
  TxCategory.other => Icons.category_rounded,
};

String categoryLabel(TxCategory c) => switch (c) {
  TxCategory.food => 'Food',
  TxCategory.shopping => 'Shopping',
  TxCategory.transport => 'Transport',
  TxCategory.bills => 'Bills',
  TxCategory.entertainment => 'Entertainment',
  TxCategory.health => 'Health',
  TxCategory.education => 'Education',
  TxCategory.income => 'Income',
  TxCategory.transfer => 'Transfer',
  TxCategory.other => 'Other',
};

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(header: true, child: Text(title, style: AppTypography.h3)),
      ),
      if (actionLabel != null)
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
          onPressed: onAction,
          child: Text(actionLabel!, style: TextStyle(color: context.colors.accent)),
        ),
    ],
  );
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.tx, required this.balanceVisible});
  final Transaction tx;
  final bool balanceVisible;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final income = tx.amount >= 0;
    final amountText = balanceVisible ? formatMoney(tx.amount, signed: true) : '••••••';
    return Semantics(
      label: '${tx.merchant}, ${categoryLabel(tx.category)}, ${formatShortDate(tx.date)}, '
          '${balanceVisible ? amountText : 'amount hidden'}${tx.status == TxStatus.pending ? ', pending' : ''}',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (income ? c.success : c.textSecondary).withAlpha(36),
                ),
                child: Icon(categoryIcon(tx.category), size: 22, color: income ? c.success : c.textPrimary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx.merchant, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.title),
                    Text(
                      '${categoryLabel(tx.category)} · ${formatShortDate(tx.date)}'
                      '${tx.status == TxStatus.pending ? ' · Pending' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                amountText,
                style: AppTypography.amountSmall.copyWith(color: income ? c.success : c.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AccountTile extends StatelessWidget {
  const AccountTile({super.key, required this.account, required this.balanceVisible, this.onTap});
  final BankAccount account;
  final bool balanceVisible;
  final VoidCallback? onTap;

  IconData get _icon => switch (account.type) {
    AccountType.savings => Icons.savings_rounded,
    AccountType.current => Icons.account_balance_wallet_rounded,
    AccountType.fixedDeposit => Icons.lock_clock_rounded,
    AccountType.foreignCurrency => Icons.currency_exchange_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      semanticLabel: account.name,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent.withAlpha(36)),
            child: Icon(_icon, color: c.accent),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.title),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: account.active ? c.success : c.warning),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${account.maskedNumber} · ${account.currency}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(color: c.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(balanceVisible ? formatMoney(account.balance) : '••••••', style: AppTypography.amountSmall),
            ),
          ),
        ],
      ),
    );
  }
}

class QuickAction extends StatelessWidget {
  const QuickAction({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressableScale(
      semanticLabel: label,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: AppSpacing.touchTarget, minHeight: AppSpacing.touchTarget),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassCard(
              radius: 20,
              padding: const EdgeInsets.all(14),
              child: Icon(icon, color: c.accent, size: 26),
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, style: AppTypography.caption.copyWith(color: c.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Total balance block with privacy toggle and a monthly change chip.
class TotalBalance extends StatelessWidget {
  const TotalBalance({
    super.key,
    required this.total,
    required this.visible,
    required this.onToggle,
    required this.monthlyChange,
  });
  final double total, monthlyChange;
  final bool visible;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final up = monthlyChange >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Total balance', style: AppTypography.body.copyWith(color: c.textSecondary)),
            const Spacer(),
            IconButton(
              tooltip: visible ? 'Hide balances' : 'Show balances',
              constraints: const BoxConstraints(minWidth: AppSpacing.touchTarget, minHeight: AppSpacing.touchTarget),
              onPressed: onToggle,
              icon: Icon(visible ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: c.textSecondary),
            ),
          ],
        ),
        BalanceDisplay(value: total, visible: visible),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: (up ? c.success : c.error).withAlpha(36),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 16, color: up ? c.success : c.error),
              const SizedBox(width: 4),
              Text(
                '${up ? '+' : ''}${monthlyChange.toStringAsFixed(1)}% this month',
                style: AppTypography.caption.copyWith(color: up ? c.success : c.error, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
