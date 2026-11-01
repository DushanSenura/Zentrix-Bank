import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/amount_input.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/bank_text_field.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/engagement_models.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/payment_models.dart';
import '../../../shared/models/service_models.dart';
import '../../payments/presentation/authorize_sheet.dart';
import '../../payments/presentation/payment_widgets.dart';
import 'account_detail_page.dart';

/// Open another savings or current account, or lock money away in a fixed deposit. The money comes from one of your
/// existing accounts, so it needs your PIN, like any other payment.
class OpenAccountPage extends ConsumerStatefulWidget {
  const OpenAccountPage({super.key});

  @override
  ConsumerState<OpenAccountPage> createState() => _OpenAccountPageState();
}

class _OpenAccountPageState extends ConsumerState<OpenAccountPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  AccountType _type = AccountType.savings;
  String? _fromId;
  bool _busy = false;
  BankAccount? _opened;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  double get _minimum => minNewAccountDeposit;

  Future<void> _open(List<BankAccount> payable) async {
    if (_busy) return;
    if (!_form.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }
    final from = payable.firstWhere((a) => a.id == _fromId, orElse: () => payable.first);
    final amount = double.parse(_amount.text.replaceAll(',', ''));
    final what = 'a new ${_type == AccountType.current ? 'current' : 'savings'} account';
    final result = await authorizePayment(
      context,
      title: 'Confirm new account',
      summary: 'Move ${formatMoney(amount)} from ${from.name} ${from.maskedNumber} to open $what.',
    );
    if (!mounted) return;
    if (result == AuthResult.locked) {
      BankSnackbar.show(context, 'Too many incorrect PINs. No account was opened.', kind: SnackKind.error);
      return;
    }
    if (result != AuthResult.approved) return;
    setState(() => _busy = true);
    try {
      final account = await ref.read(accountRepositoryProvider).open(
        type: _type,
        name: _name.text,
        fromAccountId: from.id,
        amount: amount,
      );
      ref.invalidate(accountsProvider);
      ref.invalidate(transactionsProvider);
      await ref.read(notificationsProvider.notifier).post(
        NotifCategory.transactions,
        'New account opened',
        '${account.name} ${account.maskedNumber} was opened with ${formatMoney(amount)} from ${from.name}.',
      );
      if (mounted) setState(() => _opened = account);
    } on PaymentException catch (e) {
      if (mounted) BankSnackbar.show(context, e.message, kind: SnackKind.error);
    } catch (_) {
      if (mounted) BankSnackbar.show(context, 'We couldn’t open the account. Nothing was changed — please check your balance and try again.', kind: SnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accountsAsync = ref.watch(accountsProvider);
    return FlowPage(
      title: 'Open an account',
      child: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyState(icon: Icons.cloud_off_rounded, title: 'Couldn’t load your accounts', message: 'Please go back and try again.'),
        data: (all) {
          if (_opened != null) return _Opened(account: _opened!);
          final payable = payableAccounts(all);
          if (payable.isEmpty) {
            return const EmptyState(icon: Icons.account_balance_wallet_rounded, title: 'No account to fund it from', message: 'You need a savings or current account with money in it.');
          }
          if (all.length >= maxAccountsPerCustomer) {
            return const EmptyState(icon: Icons.layers_rounded, title: 'You have the maximum', message: 'You can have up to $maxAccountsPerCustomer accounts. Close one at a branch to open another.');
          }
          final from = payable.firstWhere((a) => a.id == _fromId, orElse: () => payable.first);
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
            children: [
              SegmentedButton<AccountType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: AccountType.savings, label: Text('Savings')),
                  ButtonSegment(value: AccountType.current, label: Text('Current')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _type == AccountType.current
                    ? 'For everyday spending and bills. You can pay from it any time.'
                    : 'A place to put money aside. You can pay from it any time.',
                style: AppTypography.caption.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Form(
                key: _form,
                child: Column(
                  children: [
                    BankTextField(
                      fieldKey: const ValueKey('accountName'),
                      controller: _name,
                      label: 'Nickname (optional)',
                      icon: Icons.label_rounded,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => (v ?? '').trim().length > 30 ? 'Keep it to 30 characters or fewer.' : null,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AccountSelector(label: 'Pay from', account: from, accounts: payable, onChanged: (id) => setState(() => _fromId = id)),
                    const SizedBox(height: AppSpacing.sm),
                    AmountInput(
                      fieldKey: const ValueKey('openAmount'),
                      controller: _amount,
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final base = Validators.amount(v);
                        if (base != null) return base;
                        final n = double.parse(v!.replaceAll(',', '').trim());
                        if (n < _minimum) return 'The minimum is ${formatMoney(_minimum).replaceAll('.00', '')}.';
                        if (n > from.balance) return 'That is more than is in ${from.name}.';
                        return null;
                      },
                    ),
                    Text('Minimum ${formatMoney(_minimum).replaceAll('.00', '')}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
                  onPressed: () => context.push('/fixed-deposits/open'),
                  icon: Icon(Icons.lock_clock_rounded, color: c.accent),
                  label: Text('Want to lock money away? Open a fixed deposit', style: TextStyle(color: c.accent)),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: 'Open account', icon: Icons.lock_rounded, loading: _busy, onPressed: () => _open(payable)),
            ],
          );
        },
      ),
    );
  }
}

class _Opened extends StatelessWidget {
  const _Opened({required this.account});
  final BankAccount account;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, size: 72, color: c.success),
          const SizedBox(height: AppSpacing.md),
          Semantics(header: true, liveRegion: true, child: const Text('Account opened', style: AppTypography.h1, textAlign: TextAlign.center)),
          const SizedBox(height: AppSpacing.md),
          GlassCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                SummaryRow('Account', account.name),
                SummaryRow('Type', accountTypeLabel(account.type)),
                SummaryRow('Number', account.maskedNumber),
                SummaryRow('Balance', formatMoney(account.balance), bold: true),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: 'View account', onPressed: () => context.pushReplacement('/accounts/${account.id}')),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.touchTarget)),
            onPressed: () => context.pop(),
            child: Text('Done', style: TextStyle(color: c.textSecondary)),
          ),
        ],
      ),
    );
  }
}
