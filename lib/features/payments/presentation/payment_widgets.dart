import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/glass_bottom_sheet.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/models/models.dart';

/// Accounts money can be sent from (deposits are excluded).
List<BankAccount> payableAccounts(List<BankAccount> all) =>
    all.where((a) => a.type == AccountType.savings || a.type == AccountType.current).toList();

Future<String?> pickAccount(BuildContext context, List<BankAccount> accounts, String selectedId, {String title = 'Select account'}) =>
    showGlassSheet<String>(
      context,
      builder: (context) {
        final c = context.colors;
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(title, style: AppTypography.h3)),
              const SizedBox(height: AppSpacing.sm),
              for (final a in accounts)
                ListTile(
                  minTileHeight: 64,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.account_balance_wallet_rounded, color: c.accent),
                  title: Text(a.name, style: AppTypography.title),
                  subtitle: Text('${a.maskedNumber} · ${formatMoney(a.balance)}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                  trailing: a.id == selectedId ? Icon(Icons.check_circle_rounded, color: c.success) : null,
                  onTap: () => Navigator.of(context).pop(a.id),
                ),
            ],
          ),
        );
      },
    );

/// Tappable summary of an account that opens [pickAccount].
class AccountSelector extends StatelessWidget {
  const AccountSelector({super.key, required this.label, required this.account, required this.accounts, required this.onChanged});
  final String label;
  final BankAccount account;
  final List<BankAccount> accounts;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      semanticLabel: '$label: ${account.name}, ${formatMoney(account.balance)} available. Change account',
      onTap: accounts.length < 2
          ? null
          : () async {
              final id = await pickAccount(context, accounts, account.id, title: label);
              if (id != null) onChanged(id);
            },
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(Icons.account_balance_wallet_rounded, color: c.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.caption.copyWith(color: c.textSecondary)),
                  Text(account.name, style: AppTypography.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${account.maskedNumber} · ${formatMoney(account.balance)}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                ],
              ),
            ),
            if (accounts.length > 1) Icon(Icons.unfold_more_rounded, color: c.textSecondary),
          ],
        ),
      ),
    );
  }
}

class SummaryRow extends StatelessWidget {
  const SummaryRow(this.label, this.value, {super.key, this.bold = false});
  final String label, value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 108, child: Text(label, style: AppTypography.body.copyWith(color: c.textSecondary))),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: (bold ? AppTypography.title : AppTypography.body).copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.length == 1 ? parts.first[0].toUpperCase() : '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

/// The account to pre-select: the customer's default if set, otherwise savings, otherwise the first.
BankAccount defaultPayAccount(List<BankAccount> accounts, String? preferredId) {
  final payable = payableAccounts(accounts);
  final pool = payable.isEmpty ? accounts : payable;
  return pool.firstWhere((a) => a.id == preferredId, orElse: () => pool.firstWhere((a) => a.type == AccountType.savings, orElse: () => pool.first));
}
