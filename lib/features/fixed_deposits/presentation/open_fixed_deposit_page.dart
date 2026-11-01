import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/amount_input.dart';
import '../../../core/widgets/bank_snackbar.dart';
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
import '../domain/fixed_deposit.dart';

/// Lock money away for a fixed term at a set rate. You choose the term, which account the money comes from,
/// and what should happen when the term ends.
class OpenFixedDepositPage extends ConsumerStatefulWidget {
  const OpenFixedDepositPage({super.key});

  @override
  ConsumerState<OpenFixedDepositPage> createState() => _OpenFixedDepositPageState();
}

class _OpenFixedDepositPageState extends ConsumerState<OpenFixedDepositPage> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _months = TextEditingController();
  int _quick = 12;
  bool _longer = false;
  FdRenewal _renewal = FdRenewal.renewWithInterest;
  String? _fromId;
  bool _busy = false;
  FixedDeposit? _opened;

  @override
  void dispose() {
    _amount.dispose();
    _months.dispose();
    super.dispose();
  }

  /// The term in months, or null while the "more than 12 months" box holds something unusable.
  int? get _termMonths {
    if (!_longer) return _quick;
    return validateLongFdMonths(_months.text) == null ? int.parse(_months.text.trim()) : null;
  }

  Future<void> _open(List<BankAccount> payable) async {
    if (_busy) return;
    if (!_form.currentState!.validate() || _termMonths == null) {
      HapticFeedback.heavyImpact();
      return;
    }
    final from = payable.firstWhere((a) => a.id == _fromId, orElse: () => payable.first);
    final amount = double.parse(_amount.text.replaceAll(',', '').trim());
    final term = _termMonths!;
    final result = await authorizePayment(
      context,
      title: 'Confirm fixed deposit',
      summary: 'Move ${formatMoney(amount)} from ${from.name} ${from.maskedNumber} into a ${fdTermLabel(term)} fixed deposit that will ${fdRenewalLabel(_renewal).toLowerCase()} at maturity. This can’t be changed afterwards.',
    );
    if (!mounted) return;
    if (result == AuthResult.locked) {
      BankSnackbar.show(context, 'Too many incorrect PINs. No deposit was opened.', kind: SnackKind.error);
      return;
    }
    if (result != AuthResult.approved) return;
    setState(() => _busy = true);
    try {
      final fd = await ref.read(fixedDepositRepositoryProvider).open(fromAccountId: from.id, amount: amount, termMonths: term, renewal: _renewal);
      ref.invalidate(accountsProvider);
      ref.invalidate(transactionsProvider);
      ref.invalidate(fixedDepositsProvider);
      await ref.read(notificationsProvider.notifier).post(
        NotifCategory.transactions,
        'Fixed deposit opened',
        '${formatMoney(fd.principal)} for ${fdTermLabel(fd.termMonths)} at ${fd.rate}% a year, maturing ${formatGroupDate(fd.maturityDate, DateTime.now())}.',
      );
      if (mounted) setState(() => _opened = fd);
    } on PaymentException catch (e) {
      if (mounted) BankSnackbar.show(context, e.message, kind: SnackKind.error);
    } catch (_) {
      if (mounted) BankSnackbar.show(context, 'We couldn’t open the deposit. Nothing was changed — please check your balance and try again.', kind: SnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accounts = ref.watch(accountsProvider);
    return FlowPage(
      title: 'Open a fixed deposit',
      child: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyState(icon: Icons.cloud_off_rounded, title: 'Couldn’t load your accounts', message: 'Please go back and try again.'),
        data: (all) {
          if (_opened != null) return _Opened(deposit: _opened!);
          final payable = payableAccounts(all);
          if (payable.isEmpty) {
            return const EmptyState(icon: Icons.account_balance_wallet_rounded, title: 'No account to fund it from', message: 'You need a savings or current account with money in it.');
          }
          if (all.length >= maxAccountsPerCustomer) {
            return const EmptyState(icon: Icons.layers_rounded, title: 'You have the maximum', message: 'You can have up to $maxAccountsPerCustomer accounts. Close one at a branch to open another.');
          }
          final from = payable.firstWhere((a) => a.id == _fromId, orElse: () => payable.first);
          final amount = double.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;
          final term = _termMonths;
          final rate = term == null ? null : fixedDepositRateFor(term);
          final maturity = term == null ? null : addMonths(DateTime.now(), term);
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
            children: [
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(header: true, child: const Text('Pay from', style: AppTypography.h3)),
                    const SizedBox(height: AppSpacing.xs),
                    AccountSelector(label: 'Account', account: from, accounts: payable, onChanged: (id) => setState(() => _fromId = id)),
                    const SizedBox(height: AppSpacing.md),
                    Center(child: Text('Amount to deposit', style: AppTypography.title.copyWith(color: c.textSecondary))),
                    AmountInput(
                      fieldKey: const ValueKey('fdAmount'),
                      controller: _amount,
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final base = Validators.amount(v);
                        if (base != null) return base;
                        final n = double.parse(v!.replaceAll(',', '').trim());
                        if (n < minFixedDeposit) return 'The minimum is ${formatMoney(minFixedDeposit).replaceAll('.00', '')}.';
                        if (n > from.balance) return 'That is more than is in ${from.name}.';
                        return null;
                      },
                    ),
                    Center(child: Text('Minimum ${formatMoney(minFixedDeposit).replaceAll('.00', '')}', style: AppTypography.caption.copyWith(color: c.textSecondary))),
                    const SizedBox(height: AppSpacing.md),
                    Semantics(header: true, child: const Text('How long?', style: AppTypography.h3)),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final m in fdQuickTerms)
                          ChoiceChip(
                            label: Text('$m months'),
                            selected: !_longer && _quick == m,
                            onSelected: (_) => setState(() {
                              _longer = false;
                              _quick = m;
                            }),
                          ),
                        ChoiceChip(label: const Text('More than 12 months'), selected: _longer, onSelected: (_) => setState(() => _longer = true)),
                      ],
                    ),
                    AnimatedSize(
                      duration: AppAnimations.scaled(context, AppAnimations.normal),
                      child: !_longer
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: AppSpacing.sm),
                              child: TextFormField(
                                key: const ValueKey('fdMonths'),
                                controller: _months,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Number of months',
                                  helperText: 'Whole years in months: 24, 36, 48 … up to 120',
                                  prefixIcon: Icon(Icons.calendar_month_rounded),
                                ),
                                validator: validateLongFdMonths,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Semantics(header: true, child: const Text('When it matures', style: AppTypography.h3)),
              RadioGroup<FdRenewal>(
                groupValue: _renewal,
                onChanged: (v) => setState(() => _renewal = v ?? _renewal),
                child: Column(
                  children: [
                    for (final r in fdRenewalChoices)
                      RadioListTile<FdRenewal>(
                        contentPadding: EdgeInsets.zero,
                        value: r,
                        title: Text(fdRenewalLabel(r), style: AppTypography.body),
                        subtitle: Text(fdRenewalHint(r), style: AppTypography.caption.copyWith(color: c.textSecondary)),
                      ),
                  ],
                ),
              ),
              Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: c.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This can’t be changed after you open the deposit, so choose carefully. The same goes for the amount and the term.',
                        style: AppTypography.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                radius: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SummaryRow('Indicative rate', rate == null ? '—' : '$rate% a year'),
                    SummaryRow('Matures on', maturity == null ? '—' : formatGroupDate(maturity, DateTime.now())),
                    if (term != null && rate != null && amount >= minFixedDeposit) ...[
                      SummaryRow('Interest at maturity', formatMoney(fixedDepositInterest(amount, rate, term))),
                      SummaryRow('Total at maturity', formatMoney(amount + fixedDepositInterest(amount, rate, term)), bold: true),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'An estimate: the bank confirms the actual rate when it opens the deposit. These sample rates are for the prototype. You can’t pay from a fixed deposit, and taking money out early needs a branch visit.',
                      style: AppTypography.caption.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: 'Open fixed deposit', icon: Icons.lock_rounded, loading: _busy, onPressed: () => _open(payable)),
            ],
          );
        },
      ),
    );
  }
}

class _Opened extends StatelessWidget {
  const _Opened({required this.deposit});
  final FixedDeposit deposit;

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
          Semantics(header: true, liveRegion: true, child: const Text('Fixed deposit opened', style: AppTypography.h1, textAlign: TextAlign.center)),
          const SizedBox(height: AppSpacing.md),
          GlassCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                SummaryRow('Deposit', formatMoney(deposit.principal), bold: true),
                SummaryRow('Number', deposit.maskedNumber),
                SummaryRow('Term', fdTermLabel(deposit.termMonths)),
                SummaryRow('Rate', '${deposit.rate}% a year'),
                SummaryRow('Matures on', formatGroupDate(deposit.maturityDate, DateTime.now())),
                SummaryRow('Total at maturity', formatMoney(deposit.valueAtMaturity)),
                SummaryRow('Then', fdRenewalLabel(deposit.renewal)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: 'View my fixed deposits', onPressed: () => context.pushReplacement('/fixed-deposits')),
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
