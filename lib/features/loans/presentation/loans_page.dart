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
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/models.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/amount_input.dart';
import '../../../core/widgets/glass_bottom_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/payment_models.dart';
import '../../../shared/models/service_models.dart';
import 'loan_application_page.dart';
import '../../payments/presentation/payment_widgets.dart';
import '../domain/loan_math.dart';
import '../../../core/widgets/error_view.dart';

String loanName(LoanType t) => switch (t) {
  LoanType.personal => 'Personal loan',
  LoanType.vehicle => 'Vehicle loan',
  LoanType.home => 'Home loan',
  LoanType.education => 'Education loan',
};

IconData loanIcon(LoanType t) => switch (t) {
  LoanType.personal => Icons.person_rounded,
  LoanType.vehicle => Icons.directions_car_rounded,
  LoanType.home => Icons.home_rounded,
  LoanType.education => Icons.school_rounded,
};

/// Indicative starting rates used only to pre-fill the calculator.
double typicalRate(LoanType t) => switch (t) {
  LoanType.personal => 15,
  LoanType.vehicle => 13.5,
  LoanType.home => 11,
  LoanType.education => 9,
};

class LoansPage extends ConsumerWidget {
  const LoansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final loans = ref.watch(loansProvider);
    return FlowPage(
      title: 'Loans',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
        children: [
          loans.when(
            loading: () => const Skeleton(height: 240, radius: 24),
            error: (e, _) => ErrorView(error: e, what: 'loans', onRetry: () => ref.invalidate(loansProvider)),
            data: (list) => list.isEmpty
                ? const EmptyState(icon: Icons.account_balance_rounded, title: 'No loans', message: 'Your active loans will appear here.')
                : Column(children: [for (final l in list) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _LoanCard(loan: l))]),
          ),
          PrimaryButton(label: 'Apply for a loan', icon: Icons.request_quote_rounded, onPressed: () => context.push('/loans/apply')),
          const SizedBox(height: AppSpacing.sm),
          const _Applications(),
          GlassCard(
            radius: 22,
            onTap: () => context.push('/loans/calculator'),
            semanticLabel: 'Loan calculator',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Icon(Icons.calculate_rounded, color: c.accent),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text('Loan calculator', style: AppTypography.title), Text('Estimate a monthly payment', style: AppTypography.caption)],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoanCard extends ConsumerStatefulWidget {
  const _LoanCard({required this.loan});
  final Loan loan;

  @override
  ConsumerState<_LoanCard> createState() => _LoanCardState();
}

double _cents(double v) => (v * 100).round() / 100;

class _LoanCardState extends ConsumerState<_LoanCard> {
  bool _open = false;

  Future<void> _pay() async {
    final l = widget.loan;
    final amount = await showGlassSheet<double>(context, builder: (_) => _PayLoanSheet(loan: l));
    if (amount == null || !mounted) return;
    final accounts = ref.read(accountsProvider).value ?? const <BankAccount>[];
    final from = defaultPayAccount(accounts, ref.read(settingsProvider).defaultAccountId);
    ref.read(paymentDraftProvider.notifier).set(
      PaymentDraft(
        kind: PaymentKind.loan,
        fromAccountId: from.id,
        payee: '${loanName(l.type)} instalment',
        payeeDetail: 'Loan ${l.id.toUpperCase()}',
        amount: amount,
        category: TxCategory.bills,
        loanId: l.id,
        details: [
          ('Loan', loanName(l.type)),
          ('Balance after', formatMoney((l.outstanding - (amount - l.monthlyInterest).clamp(0.0, l.outstanding)).clamp(0.0, l.outstanding))),
        ],
      ),
    );
    context.push('/pay/confirm');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = widget.loan;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(loanIcon(l.type), color: c.accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(loanName(l.type), style: AppTypography.h3)),
              Text('${l.annualRate.toStringAsFixed(1)}% p.a.', style: AppTypography.caption.copyWith(color: c.textSecondary)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Outstanding', style: AppTypography.caption.copyWith(color: c.textSecondary)),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(formatMoney(l.outstanding), style: AppTypography.amount.copyWith(fontSize: 28))),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label: '${(l.repaidFraction * 100).round()} percent repaid',
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: l.repaidFraction),
                  duration: AppAnimations.scaled(context, AppAnimations.number),
                  curve: AppAnimations.standard,
                  builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: c.divider, color: c.success),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('${(l.repaidFraction * 100).round()}% repaid of ${formatMoney(l.principal)}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          SummaryRow('Next payment', '${formatMoney(l.monthlyPayment)} on ${formatGroupDate(l.nextPaymentDate, DateTime.now())}'),
          SummaryRow('Remaining term', '${l.remainingMonths} of ${l.totalMonths} months'),
          const SizedBox(height: AppSpacing.xs),
          if (l.closed)
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: c.success, size: 20),
                const SizedBox(width: 8),
                Text('Fully repaid', style: AppTypography.title.copyWith(color: c.success)),
              ],
            )
          else
            PrimaryButton(label: 'Pay instalment', icon: Icons.payments_rounded, onPressed: _pay),
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _open = !_open);
            },
            icon: AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: AppAnimations.scaled(context, AppAnimations.fast),
              child: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            label: Text(_open ? 'Hide payment history' : 'Payment history', style: TextStyle(color: c.accent)),
          ),
          AnimatedSize(
            duration: AppAnimations.scaled(context, AppAnimations.normal),
            curve: AppAnimations.standard,
            child: _open
                ? Column(
                    children: [
                      for (final h in l.history)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_rounded, size: 18, color: c.success),
                              const SizedBox(width: 8),
                              Expanded(child: Text(formatGroupDate(h.date, DateTime.now()), style: AppTypography.body)),
                              Text(formatMoney(h.amount), style: AppTypography.amountSmall),
                            ],
                          ),
                        ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class LoanCalculatorPage extends StatefulWidget {
  const LoanCalculatorPage({super.key});

  @override
  State<LoanCalculatorPage> createState() => _LoanCalculatorPageState();
}

class _LoanCalculatorPageState extends State<LoanCalculatorPage> {
  LoanType _type = LoanType.personal;
  double _amount = 500000;
  double _rate = typicalRate(LoanType.personal);
  double _months = 36;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = estimateLoan(_amount, _rate, _months.round());
    Widget slider(String label, String value, double v, double min, double max, int? div, ValueChanged<double> on) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Expanded(child: Text(label, style: AppTypography.body.copyWith(color: c.textSecondary))), Text(value, style: AppTypography.title)]),
        Slider(value: v, min: min, max: max, divisions: div, label: value, semanticFormatterCallback: (_) => '$label $value', onChanged: on),
      ],
    );
    return FlowPage(
      title: 'Loan calculator',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final t in LoanType.values)
                ChoiceChip(
                  label: Text(loanName(t)),
                  selected: _type == t,
                  onSelected: (_) => setState(() {
                    _type = t;
                    _rate = typicalRate(t);
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          GlassCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                slider('Amount', formatMoney(_amount).replaceAll('.00', ''), _amount, 50000, 10000000, 199, (v) => setState(() => _amount = (v / 50000).round() * 50000.0)),
                slider('Interest rate', '${_rate.toStringAsFixed(1)}% p.a.', _rate, 5, 30, 50, (v) => setState(() => _rate = v)),
                slider('Term', '${_months.round()} months', _months, 6, 360, 59, (v) => setState(() => _months = (v / 6).round() * 6.0)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          GlassCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Semantics(
              liveRegion: true,
              child: Column(
                children: [
                  Text('Estimated monthly payment', style: AppTypography.body.copyWith(color: c.textSecondary)),
                  FittedBox(fit: BoxFit.scaleDown, child: Text(formatMoney(e.monthly), style: AppTypography.amount)),
                  const SizedBox(height: AppSpacing.sm),
                  SummaryRow('Total interest', formatMoney(e.totalInterest)),
                  SummaryRow('Total payable', formatMoney(e.totalPayable), bold: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: c.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Estimate only. Uses a standard reducing-balance formula; actual rates, fees and approval are decided by the bank.',
                  style: AppTypography.caption.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _Choice { instalment, custom, settle }

/// Choose what to pay: the regular instalment, any other amount, or the whole loan.
class _PayLoanSheet extends StatefulWidget {
  const _PayLoanSheet({required this.loan});
  final Loan loan;

  @override
  State<_PayLoanSheet> createState() => _PayLoanSheetState();
}

class _PayLoanSheetState extends State<_PayLoanSheet> {
  final _form = GlobalKey<FormState>();
  final _custom = TextEditingController();
  _Choice _choice = _Choice.instalment;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = widget.loan;
    final instalment = _cents(l.monthlyPayment < l.payoffAmount ? l.monthlyPayment : l.payoffAmount);
    final payoff = (l.payoffAmount * 100).ceil() / 100;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text('Pay ${loanName(l.type).toLowerCase()}', style: AppTypography.h3)),
            const SizedBox(height: AppSpacing.xs),
            RadioGroup<_Choice>(
              groupValue: _choice,
              onChanged: (v) => setState(() => _choice = v ?? _choice),
              child: Column(
                children: [
                  RadioListTile<_Choice>(
                    contentPadding: EdgeInsets.zero,
                    value: _Choice.instalment,
                    title: Text('Monthly instalment · ${formatMoney(instalment)}', style: AppTypography.body),
                    subtitle: Text('Interest this month is ${formatMoney(l.monthlyInterest)}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                  ),
                  RadioListTile<_Choice>(
                    contentPadding: EdgeInsets.zero,
                    value: _Choice.custom,
                    title: const Text('Another amount', style: AppTypography.body),
                    subtitle: Text('Extra payments reduce what you owe', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                  ),
                  RadioListTile<_Choice>(
                    contentPadding: EdgeInsets.zero,
                    value: _Choice.settle,
                    title: Text('Settle in full · ${formatMoney(payoff)}', style: AppTypography.body),
                    subtitle: Text('Closes this loan', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                  ),
                ],
              ),
            ),
            if (_choice == _Choice.custom)
              AmountInput(
                fieldKey: const ValueKey('loanAmount'),
                controller: _custom,
                autofocus: true,
                validator: (v) =>
                    Validators.amount(v) ?? (double.parse(v!.replaceAll(',', '').trim()) > payoff ? 'That is more than is needed to settle this loan.' : null),
              ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Continue',
              icon: Icons.arrow_forward_rounded,
              onPressed: () {
                if (_choice == _Choice.custom && !_form.currentState!.validate()) return;
                Navigator.of(context).pop(switch (_choice) {
                  _Choice.instalment => instalment,
                  _Choice.settle => payoff,
                  _Choice.custom => _cents(double.parse(_custom.text)),
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Applications sent for review, so a customer can see they went through.
class _Applications extends ConsumerWidget {
  const _Applications();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final apps = ref.watch(loanApplicationsProvider).value ?? const <LoanApplication>[];
    if (apps.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: const Text('Your applications', style: AppTypography.h3)),
        const SizedBox(height: AppSpacing.xs),
        for (final a in apps)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: GlassCard(
              radius: 20,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Semantics(
                container: true,
                label: '${loanName(a.type)}, ${formatMoney(a.amount)}, ${loanApplicationStatusLabel(a.statusAt(DateTime.now()))}, reference ${a.id}',
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      Icon(loanIcon(a.type), color: c.accent),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(loanName(a.type), style: AppTypography.title),
                            Text('${loanApplicationStatusLabel(a.statusAt(DateTime.now()))} · ${a.id}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                          ],
                        ),
                      ),
                      Text(formatMoney(a.amount), style: AppTypography.amountSmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}
