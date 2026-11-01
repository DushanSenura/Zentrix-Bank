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
import '../../../core/widgets/bank_dropdown.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/engagement_models.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/service_models.dart';
import '../../payments/presentation/payment_widgets.dart';
import '../domain/loan_math.dart';
import 'loans_page.dart';

const employmentOptions = ['Employed', 'Self-employed', 'Retired', 'Student', 'Other'];

String loanApplicationStatusLabel(LoanApplicationStatus s) => switch (s) {
  LoanApplicationStatus.received => 'Received',
  LoanApplicationStatus.underReview => 'Under review',
};

/// Apply for a loan. This sends the application for the bank to review; it is not an approval, and the app never decides one.
class LoanApplicationPage extends ConsumerStatefulWidget {
  const LoanApplicationPage({super.key});

  @override
  ConsumerState<LoanApplicationPage> createState() => _LoanApplicationPageState();
}

class _LoanApplicationPageState extends ConsumerState<LoanApplicationPage> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _income = TextEditingController();
  final _purpose = TextEditingController();
  LoanType _type = LoanType.personal;
  double _months = 36;
  String? _employment;
  bool _consent = false;
  bool _showConsentError = false;
  bool _busy = false;
  LoanApplication? _sent;

  @override
  void dispose() {
    _amount.dispose();
    _income.dispose();
    _purpose.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim());

  ({double min, double max, int minMonths, int maxMonths}) get _lim => loanLimits(_type);

  Future<void> _submit() async {
    final valid = _form.currentState!.validate();
    setState(() => _showConsentError = !_consent);
    if (!valid || !_consent || _busy) {
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _busy = true);
    try {
      final app = await ref.read(loanRepositoryProvider).apply(
        LoanApplicationRequest(
          type: _type,
          amount: _num(_amount)!,
          termMonths: _months.round(),
          monthlyIncome: _num(_income)!,
          employment: _employment!,
          purpose: _purpose.text,
        ),
      );
      ref.invalidate(loanApplicationsProvider);
      await ref.read(notificationsProvider.notifier).post(
        NotifCategory.bankNotices,
        'Loan application received',
        'We’ve received your ${loanName(_type).toLowerCase()} application for ${formatMoney(app.amount)}. Your reference is ${app.id}.',
      );
      if (mounted) setState(() => _sent = app);
    } on LoanApplicationException catch (e) {
      if (mounted) BankSnackbar.show(context, e.message, kind: SnackKind.error);
    } catch (_) {
      if (mounted) BankSnackbar.show(context, 'We couldn’t send your application. Nothing was submitted — please try again.', kind: SnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_sent != null) return FlowPage(title: 'Loan application', child: _Sent(application: _sent!));
    final lim = _lim;
    final months = _months.clamp(lim.minMonths.toDouble(), lim.maxMonths.toDouble());
    final amount = _num(_amount) ?? 0;
    final income = _num(_income) ?? 0;
    final estimate = amount >= lim.min && amount <= lim.max ? estimateLoan(amount, typicalRate(_type), months.round()) : null;
    final hint = estimate == null || income <= 0 ? null : affordabilityOf(estimate.monthly, income);
    return FlowPage(
      title: 'Apply for a loan',
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
                    final l = loanLimits(t);
                    _months = _months.clamp(l.minMonths.toDouble(), l.maxMonths.toDouble());
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AmountInput(
                  fieldKey: const ValueKey('loanApplyAmount'),
                  controller: _amount,
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final base = Validators.amount(v);
                    if (base != null) return base;
                    final n = double.parse(v!.replaceAll(',', '').trim());
                    if (n < lim.min) return 'The minimum is ${formatMoney(lim.min).replaceAll('.00', '')}.';
                    if (n > lim.max) return 'The maximum is ${formatMoney(lim.max).replaceAll('.00', '')}.';
                    return null;
                  },
                ),
                Center(child: Text('${formatMoney(lim.min).replaceAll('.00', '')} – ${formatMoney(lim.max).replaceAll('.00', '')}', style: AppTypography.caption.copyWith(color: c.textSecondary))),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: Text('Term', style: AppTypography.body.copyWith(color: c.textSecondary))),
                    Text(_termLabel(months.round()), style: AppTypography.title),
                  ],
                ),
                Slider(
                  value: months,
                  min: lim.minMonths.toDouble(),
                  max: lim.maxMonths.toDouble(),
                  divisions: lim.maxMonths - lim.minMonths,
                  label: _termLabel(months.round()),
                  semanticFormatterCallback: (_) => 'Term ${_termLabel(months.round())}',
                  onChanged: (v) => setState(() => _months = v),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('Monthly income', style: AppTypography.title.copyWith(color: c.textSecondary)),
                AmountInput(
                  fieldKey: const ValueKey('loanApplyIncome'),
                  controller: _income,
                  onChanged: (_) => setState(() {}),
                  validator: (v) => Validators.amount(v),
                ),
                const SizedBox(height: AppSpacing.xs),
                BankDropdown(
                  label: 'Employment',
                  icon: Icons.work_rounded,
                  items: employmentOptions,
                  value: _employment,
                  onChanged: (v) => setState(() => _employment = v),
                  validator: (v) => v == null ? 'Choose one.' : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const ValueKey('loanApplyPurpose'),
                  controller: _purpose,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'What is it for? (optional)'),
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
          ),
          if (estimate != null) ...[
            const SizedBox(height: AppSpacing.xs),
            GlassCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              radius: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SummaryRow('Estimated monthly', formatMoney(estimate.monthly), bold: true),
                  SummaryRow('Indicative rate', '${typicalRate(_type).toStringAsFixed(1)}% a year'),
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Semantics(
                        liveRegion: true,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              hint == Affordability.comfortable ? Icons.check_circle_rounded : Icons.info_rounded,
                              size: 18,
                              color: hint == Affordability.comfortable ? c.success : (hint == Affordability.stretched ? c.warning : c.error),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                switch (hint) {
                                  Affordability.comfortable => 'This instalment is about ${(estimate.monthly / income * 100).round()}% of your income, which is usually comfortable.',
                                  Affordability.stretched => 'This instalment is about ${(estimate.monthly / income * 100).round()}% of your income, which may be a stretch.',
                                  Affordability.unlikely => 'This instalment is about ${(estimate.monthly / income * 100).round()}% of your income. A smaller amount or longer term may suit you better.',
                                },
                                style: AppTypography.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text('A guide only, not an offer or a decision. The bank sets the real rate and decides after reviewing your application.', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _consent,
            onChanged: (v) => setState(() {
              _consent = v ?? false;
              _showConsentError = false;
            }),
            title: Text('I confirm these details are correct, and the bank may check my credit history.', style: AppTypography.bodySmall),
          ),
          if (_showConsentError)
            Semantics(liveRegion: true, child: Text('Please confirm to continue.', style: AppTypography.bodySmall.copyWith(color: c.error))),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(label: 'Send application', icon: Icons.send_rounded, loading: _busy, onPressed: _submit),
        ],
      ),
    );
  }

  static String _termLabel(int months) {
    if (months < 24 || months % 12 != 0) return '$months months';
    return '${months ~/ 12} years';
  }
}

class _Sent extends StatelessWidget {
  const _Sent({required this.application});
  final LoanApplication application;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forward_to_inbox_rounded, size: 64, color: c.accent),
          const SizedBox(height: AppSpacing.md),
          Semantics(header: true, liveRegion: true, child: const Text('Application received', style: AppTypography.h1, textAlign: TextAlign.center)),
          const SizedBox(height: AppSpacing.xs),
          Text('Your reference', style: AppTypography.body.copyWith(color: c.textSecondary)),
          SelectableText(application.id, style: AppTypography.h3),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This isn’t an approval. The bank will review your application and contact you with a decision.',
            style: AppTypography.body.copyWith(color: c.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: 'Back to loans', onPressed: () => context.pop()),
        ],
      ),
    );
  }
}
