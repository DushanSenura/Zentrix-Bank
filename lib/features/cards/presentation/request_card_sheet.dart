import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/bank_dropdown.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/glass_bottom_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/engagement_models.dart';
import '../../../shared/models/models.dart';
import '../../payments/presentation/authorize_sheet.dart';
import '../../payments/presentation/payment_widgets.dart';

Future<void> showRequestCardSheet(BuildContext context) => showGlassSheet<void>(context, builder: (_) => const _RequestCardSheet());

class _RequestCardSheet extends ConsumerStatefulWidget {
  const _RequestCardSheet();

  @override
  ConsumerState<_RequestCardSheet> createState() => _RequestCardSheetState();
}

class _RequestCardSheetState extends ConsumerState<_RequestCardSheet> {
  CardKind _kind = CardKind.virtual;
  String? _accountId;
  String? _branch;
  bool _busy = false;

  Future<void> _submit(List<BankAccount> payable, List<String> branches) async {
    final user = ref.read(authProvider);
    final branch = _kind == CardKind.debit ? (_branch != null && branches.contains(_branch) ? _branch : branches.firstOrNull) : null;
    if (_kind == CardKind.debit && branch == null) {
      BankSnackbar.show(context, 'Choose the branch where you’ll collect your card.', kind: SnackKind.error);
      return;
    }
    final account = payable.firstWhere((a) => a.id == _accountId, orElse: () => payable.first);
    final result = await authorizePayment(
      context,
      title: 'Confirm card request',
      summary: _kind == CardKind.virtual
          ? 'Request a virtual card linked to ${account.name} ${account.maskedNumber}. The bank will activate it.'
          : 'Request a debit card linked to ${account.name} ${account.maskedNumber}, to collect from $branch.',
    );
    if (!mounted) return;
    if (result == AuthResult.locked) {
      BankSnackbar.show(context, 'Too many incorrect PINs. No card was requested.', kind: SnackKind.error);
      return;
    }
    if (result != AuthResult.approved) return;
    setState(() => _busy = true);
    try {
      final card = await ref.read(cardRepositoryProvider).requestCard(kind: _kind, accountId: account.id, holder: user?.fullName ?? '', collectionBranch: branch);
      ref.invalidate(cardsProvider);
      await ref.read(notificationsProvider.notifier).post(
        NotifCategory.security,
        'New card requested',
        _kind == CardKind.virtual
            ? 'A virtual card ending ${card.last4} was requested. It can’t be used until the bank activates it. We’ll tell you when it is.'
            : 'A debit card ending ${card.last4} was ordered for collection from $branch. It takes about $debitCardPreparationDays days, and we’ll tell you when it’s ready.',
        severity: Severity.warning,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      BankSnackbar.show(
        context,
        _kind == CardKind.virtual
            ? 'Virtual card •••• ${card.last4} requested. The bank will activate it.'
            : 'Debit card ordered. We’ll tell you in about $debitCardPreparationDays days when it’s ready to collect.',
        kind: SnackKind.success,
      );
    } on CardException catch (e) {
      if (mounted) BankSnackbar.show(context, e.message, kind: SnackKind.error);
    } catch (_) {
      if (mounted) BankSnackbar.show(context, 'We couldn’t place the request. Nothing was changed — please try again.', kind: SnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accounts = ref.watch(accountsProvider).value ?? const <BankAccount>[];
    final payable = payableAccounts(accounts);
    final branches = [for (final b in ref.watch(branchesProvider).value ?? const <SupportBranch>[]) if (!b.isAtm) b.name];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: const Text('Request a card', style: AppTypography.h3)),
          const SizedBox(height: AppSpacing.xs),
          RadioGroup<CardKind>(
            groupValue: _kind,
            onChanged: (v) => setState(() => _kind = v ?? _kind),
            child: Column(
              children: [
                RadioListTile<CardKind>(
                  contentPadding: EdgeInsets.zero,
                  value: CardKind.virtual,
                  title: const Text('Virtual card', style: AppTypography.body),
                  subtitle: Text('For online payments. The bank reviews it and activates it, and you can’t use it until then. Up to 3.', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                ),
                RadioListTile<CardKind>(
                  contentPadding: EdgeInsets.zero,
                  value: CardKind.debit,
                  title: const Text('Debit card', style: AppTypography.body),
                  subtitle: Text('A physical card made by the bank. Ready to collect from a branch in about $debitCardPreparationDays days. Bring your ID.', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                ),
              ],
            ),
          ),
          if (_kind == CardKind.debit) ...[
            const SizedBox(height: AppSpacing.xs),
            BankDropdown(
              label: 'Collect from',
              icon: Icons.storefront_rounded,
              items: branches,
              value: _branch ?? branches.firstOrNull,
              onChanged: (v) => setState(() => _branch = v),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text('Credit cards need an application. Please visit a branch.', style: AppTypography.caption.copyWith(color: c.textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          if (payable.isNotEmpty)
            AccountSelector(
              label: 'Linked account',
              account: payable.firstWhere((a) => a.id == _accountId, orElse: () => payable.first),
              accounts: payable,
              onChanged: (id) => setState(() => _accountId = id),
            ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(label: 'Request card', loading: _busy, onPressed: payable.isEmpty ? null : () => _submit(payable, branches)),
        ],
      ),
    );
  }
}
