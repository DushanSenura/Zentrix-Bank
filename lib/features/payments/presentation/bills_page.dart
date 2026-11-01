import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/amount_input.dart';
import '../../../core/widgets/bank_text_field.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/payment_models.dart';
import 'payment_widgets.dart';

class BillCategory {
  const BillCategory(this.name, this.icon, this.providers, {this.referenceLabel = 'Account number', this.category = TxCategory.bills});
  final String name, referenceLabel;
  final IconData icon;
  final List<String> providers;
  final TxCategory category;
}

const billCategories = [
  BillCategory('Electricity', Icons.bolt_rounded, ['Ceylon Electricity Board', 'LECO']),
  BillCategory('Water', Icons.water_drop_rounded, ['National Water Supply & Drainage Board']),
  BillCategory('Internet', Icons.wifi_rounded, ['SLT Fibre', 'Dialog Broadband', 'Lanka Bell']),
  BillCategory('Mobile', Icons.smartphone_rounded, ['Dialog', 'Mobitel', 'Hutch', 'Airtel'], referenceLabel: 'Mobile number'),
  BillCategory('TV', Icons.tv_rounded, ['Dialog TV', 'PEO TV'], referenceLabel: 'Subscriber ID'),
  BillCategory('Insurance', Icons.health_and_safety_rounded, ['Ceylinco Life', 'AIA Insurance', 'Allianz'], referenceLabel: 'Policy number'),
  BillCategory('Government', Icons.account_balance_rounded, ['Inland Revenue', 'Dept. of Motor Traffic', 'Immigration & Emigration'], referenceLabel: 'Reference number'),
  BillCategory('Education', Icons.school_rounded, ['University fees', 'School fees', 'Tuition institute'], referenceLabel: 'Student ID', category: TxCategory.education),
  BillCategory('Credit Cards', Icons.credit_card_rounded, ['Commercial Bank card', 'Sampath Bank card', 'HNB card'], referenceLabel: 'Card number (last 4 digits)'),
  BillCategory('Other', Icons.more_horiz_rounded, ['Other biller'], referenceLabel: 'Reference'),
];

class BillsPage extends ConsumerStatefulWidget {
  const BillsPage({super.key});

  @override
  ConsumerState<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends ConsumerState<BillsPage> {
  final _form = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _amount = TextEditingController();
  BillCategory? _category;
  String? _provider;

  @override
  void dispose() {
    _reference.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// 0 category, 1 provider, 2 details.
  int get _stage => _category == null ? 0 : (_provider == null ? 1 : 2);

  void _back() => setState(() {
    if (_provider != null) {
      _provider = null;
    } else {
      _category = null;
    }
  });

  void _review() {
    if (!_form.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }
    final accounts = ref.read(accountsProvider).value ?? const <BankAccount>[];
    final from = defaultPayAccount(accounts, ref.read(settingsProvider).defaultAccountId);
    final cat = _category!;
    ref.read(paymentDraftProvider.notifier).set(
      PaymentDraft(
        kind: PaymentKind.bill,
        fromAccountId: from.id,
        payee: _provider!,
        payeeDetail: '${cat.referenceLabel}: ${_reference.text.trim()}',
        amount: double.parse(_amount.text),
        category: cat.category,
        details: [('Category', cat.name)],
      ),
    );
    context.push('/pay/confirm');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: _stage == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: FlowPage(
        title: switch (_stage) {
          0 => 'Pay bills',
          1 => _category!.name,
          _ => _provider!,
        },
        onBack: _stage == 0 ? null : _back,
        child: AnimatedSwitcher(
          duration: AppAnimations.scaled(context, AppAnimations.normal),
          child: switch (_stage) {
            0 => GridView.count(
              key: const ValueKey('categories'),
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 1.9,
              children: [
                for (final cat in billCategories)
                  GlassCard(
                    radius: 20,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    onTap: () => setState(() => _category = cat),
                    semanticLabel: cat.name,
                    child: ExcludeSemantics(
                      child: Row(
                        children: [
                          Icon(cat.icon, color: c.accent),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: Text(cat.name, style: AppTypography.title, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            1 => ListView(
              key: const ValueKey('providers'),
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
              children: [
                for (final p in _category!.providers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: GlassCard(
                      radius: 20,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      onTap: () => setState(() => _provider = p),
                      semanticLabel: p,
                      child: ExcludeSemantics(
                        child: Row(
                          children: [
                            Expanded(child: Text(p, style: AppTypography.title)),
                            Icon(Icons.chevron_right_rounded, color: c.textSecondary),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            _ => ListView(
              key: const ValueKey('details'),
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
              children: [
                Form(
                  key: _form,
                  child: Column(
                    children: [
                      BankTextField(
                        fieldKey: const ValueKey('billReference'),
                        controller: _reference,
                        label: _category!.referenceLabel,
                        icon: Icons.tag_rounded,
                        textInputAction: TextInputAction.next,
                        validator: (v) => Validators.required(v, _category!.referenceLabel),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AmountInput(
                        fieldKey: const ValueKey('billAmount'),
                        controller: _amount,
                        validator: (v) => Validators.amount(v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(label: 'Review', icon: Icons.arrow_forward_rounded, onPressed: _review),
              ],
            ),
          },
        ),
      ),
    );
  }
}
