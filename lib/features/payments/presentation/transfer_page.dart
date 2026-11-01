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
import '../../../core/widgets/bank_dropdown.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/bank_text_field.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/step_progress.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/payment_models.dart';
import '../domain/banks.dart';
import 'beneficiary_form_sheet.dart';
import 'payment_widgets.dart';
import '../../../core/widgets/error_view.dart';

enum TransferType { own, saved, newBeneficiary, otherBank, international }

String _typeLabel(TransferType t) => switch (t) {
  TransferType.own => 'My accounts',
  TransferType.saved => 'Saved',
  TransferType.newBeneficiary => 'New',
  TransferType.otherBank => 'Other bank',
  TransferType.international => 'International',
};

class TransferPage extends ConsumerStatefulWidget {
  const TransferPage({super.key, this.preselected, this.fromAccountId});
  final Beneficiary? preselected;

  /// Pre-selects the account the money leaves (e.g. when opened from an account's detail screen).
  final String? fromAccountId;

  @override
  ConsumerState<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends ConsumerState<TransferPage> {
  final _recipientForm = GlobalKey<FormState>();
  final _amountForm = GlobalKey<FormState>();
  final _account = TextEditingController();
  final _name = TextEditingController();
  final _nickname = TextEditingController();
  final _amount = TextEditingController();
  final _reference = TextEditingController();

  int _step = 0;
  late TransferType _type = widget.preselected != null ? TransferType.saved : TransferType.own;
  late Beneficiary? _selected = widget.preselected;
  late String? _fromId = widget.fromAccountId;
  String? _toOwnId, _bank;
  bool _save = true;
  DateTime? _scheduled;
  Recurrence _recurrence = Recurrence.once;

  @override
  void dispose() {
    for (final c in [_account, _name, _nickname, _amount, _reference]) {
      c.dispose();
    }
    super.dispose();
  }

  double _fee() => switch (_type) {
    TransferType.own || TransferType.international => 0,
    TransferType.saved => _selected == null ? 0 : transferFeeFor(_selected!.bank),
    _ => _bank == null ? 0 : transferFeeFor(_bank!),
  };

  void _setStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
  }

  void _toAmount(String fromId) {
    switch (_type) {
      case TransferType.international:
        return;
      case TransferType.own:
        if (_toOwnId == null || _toOwnId == fromId) {
          BankSnackbar.show(context, 'Choose the account to send to.', kind: SnackKind.warning);
          HapticFeedback.heavyImpact();
          return;
        }
      case TransferType.saved:
        if (_selected == null) {
          BankSnackbar.show(context, 'Choose who to send to.', kind: SnackKind.warning);
          HapticFeedback.heavyImpact();
          return;
        }
      case TransferType.newBeneficiary || TransferType.otherBank:
        if (!_recipientForm.currentState!.validate()) {
          HapticFeedback.heavyImpact();
          return;
        }
    }
    _setStep(1);
  }

  void _review(List<BankAccount> all, BankAccount from) {
    if (!_amountForm.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }
    final amount = double.parse(_amount.text);
    final fee = _fee();
    final ref0 = _reference.text.trim();
    final schedule = _scheduled == null ? null : DateTime(_scheduled!.year, _scheduled!.month, _scheduled!.day, 9);

    final PaymentDraft draft;
    switch (_type) {
      case TransferType.own:
        final to = all.firstWhere((a) => a.id == _toOwnId);
        draft = PaymentDraft(
          kind: PaymentKind.transfer,
          fromAccountId: from.id,
          payee: to.name,
          payeeDetail: '${to.name} ${to.maskedNumber}',
          toAccountId: to.id,
          amount: amount,
          reference: ref0,
          scheduledFor: schedule,
          recurrence: schedule == null ? Recurrence.once : _recurrence,
        );
      case TransferType.saved:
        final b = _selected!;
        draft = PaymentDraft(
          kind: PaymentKind.transfer,
          fromAccountId: from.id,
          payee: b.name,
          payeeDetail: '${b.bank} ${b.masked}',
          amount: amount,
          fee: fee,
          reference: ref0,
          scheduledFor: schedule,
          recurrence: schedule == null ? Recurrence.once : _recurrence,
        );
      default:
        final number = _account.text.trim();
        final masked = '•••• ${number.substring(number.length - 4)}';
        draft = PaymentDraft(
          kind: PaymentKind.transfer,
          fromAccountId: from.id,
          payee: _name.text.trim(),
          payeeDetail: '$_bank $masked',
          amount: amount,
          fee: fee,
          reference: ref0,
          scheduledFor: schedule,
          recurrence: schedule == null ? Recurrence.once : _recurrence,
          beneficiaryToSave: _type == TransferType.newBeneficiary && _save
              ? Beneficiary(
                  id: 'b-${DateTime.now().microsecondsSinceEpoch}',
                  bank: _bank!,
                  accountNumber: number,
                  name: _name.text.trim(),
                  nickname: _nickname.text.trim(),
                )
              : null,
        );
    }
    ref.read(paymentDraftProvider.notifier).set(draft);
    context.push('/pay/confirm');
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _scheduled ?? now.add(const Duration(days: 1)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Send on',
    );
    if (d != null) setState(() => _scheduled = d);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setStep(0);
      },
      child: FlowPage(
        title: 'Send money',
        onBack: _step == 0 ? null : () => _setStep(0),
        child: accounts.when(
          loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 280, radius: 28)),
          error: (e, _) => ErrorView(error: e, what: 'your accounts', onRetry: () => ref.invalidate(accountsProvider)),
          data: (all) {
            final payable = payableAccounts(all);
            final from = payable.firstWhere((a) => a.id == _fromId, orElse: () => defaultPayAccount(payable, ref.read(settingsProvider).defaultAccountId));
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                  child: StepProgress(current: _step, total: 2),
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppAnimations.scaled(context, AppAnimations.normal),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(a), child: child),
                    ),
                    child: _step == 0
                        ? _recipientStep(all, payable, from)
                        : _amountStep(all, from),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _recipientStep(List<BankAccount> all, List<BankAccount> payable, BankAccount from) {
    final c = context.colors;
    return ListView(
      key: const ValueKey('recipientStep'),
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.lg),
      children: [
        AccountSelector(label: 'From', account: from, accounts: payable, onChanged: (id) => setState(() {
          _fromId = id;
          if (_toOwnId == id) _toOwnId = null;
        })),
        const SizedBox(height: AppSpacing.md),
        Text('Send to', style: AppTypography.title.copyWith(color: c.textSecondary)),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final t in TransferType.values)
              ChoiceChip(
                label: Text(_typeLabel(t)),
                selected: _type == t,
                onSelected: (_) => setState(() {
                  _type = t;
                  _bank = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        switch (_type) {
          TransferType.own => _ownBody(all, from),
          TransferType.saved => _savedBody(),
          TransferType.international => GlassCard(
            radius: 20,
            child: Row(
              children: [
                Icon(Icons.public_rounded, color: c.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'International transfers aren’t available in this prototype. They need a payments partner for SWIFT and compliance checks.',
                    style: AppTypography.body.copyWith(color: c.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          _ => _newBody(),
        },
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Continue',
          icon: Icons.arrow_forward_rounded,
          onPressed: _type == TransferType.international ? null : () => _toAmount(from.id),
        ),
      ],
    );
  }

  Widget _ownBody(List<BankAccount> all, BankAccount from) {
    final c = context.colors;
    final targets = all.where((a) => a.id != from.id).toList();
    return Column(
      children: [
        for (final a in targets)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: GlassCard(
              radius: 20,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              onTap: () => setState(() => _toOwnId = a.id),
              semanticLabel: 'Send to ${a.name} ${a.maskedNumber}${_toOwnId == a.id ? ', selected' : ''}',
              child: ExcludeSemantics(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: 56,
                  leading: Icon(Icons.account_balance_wallet_rounded, color: c.accent),
                  title: Text(a.name, style: AppTypography.title),
                  subtitle: Text(a.maskedNumber, style: AppTypography.caption.copyWith(color: c.textSecondary)),
                  trailing: _toOwnId == a.id ? Icon(Icons.check_circle_rounded, color: c.success) : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _savedBody() {
    final c = context.colors;
    return ref.watch(beneficiariesProvider).when(
      loading: () => const Skeleton(height: 160, radius: 20),
      error: (e, _) => ErrorView(error: e, what: 'beneficiaries', onRetry: () => ref.invalidate(beneficiariesProvider)),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: Icons.group_add_rounded,
              title: 'No beneficiaries added',
              message: 'Add someone to send money to.',
              action: FilledButton(onPressed: () => showBeneficiarySheet(context), child: const Text('Add beneficiary')),
            )
          : Column(
              children: [
                for (final b in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: GlassCard(
                      radius: 20,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      onTap: () => setState(() => _selected = b),
                      semanticLabel: 'Send to ${b.displayName}, ${b.bank} ${b.masked}${_selected?.id == b.id ? ', selected' : ''}',
                      child: ExcludeSemantics(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          minTileHeight: 56,
                          leading: CircleAvatar(
                            backgroundColor: c.primary.withAlpha(60),
                            child: Text(initialsOf(b.name), style: AppTypography.bodySmall.copyWith(color: c.textPrimary)),
                          ),
                          title: Text(b.displayName, style: AppTypography.title),
                          subtitle: Text('${b.bank} ${b.masked}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                          trailing: _selected?.id == b.id
                              ? Icon(Icons.check_circle_rounded, color: c.success)
                              : (b.favorite ? Icon(Icons.star_rounded, color: c.warning) : null),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _newBody() => Form(
    key: _recipientForm,
    child: Column(
      children: [
        BankDropdown(
          label: 'Bank',
          icon: Icons.account_balance_rounded,
          items: _type == TransferType.otherBank ? banks.where((b) => b != ownBank).toList() : banks,
          value: _bank,
          onChanged: (v) => setState(() => _bank = v),
          validator: (v) => Validators.required(v, 'Bank'),
        ),
        const SizedBox(height: AppSpacing.sm),
        BankTextField(
          fieldKey: const ValueKey('toAccount'),
          controller: _account,
          label: 'Account number',
          icon: Icons.pin_rounded,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(16)],
          textInputAction: TextInputAction.next,
          validator: Validators.accountNumber,
        ),
        const SizedBox(height: AppSpacing.sm),
        BankTextField(
          fieldKey: const ValueKey('toName'),
          controller: _name,
          label: 'Recipient name',
          icon: Icons.person_rounded,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: (v) => Validators.required(v, 'Recipient name'),
        ),
        if (_type == TransferType.newBeneficiary) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Save as beneficiary', style: AppTypography.body),
            value: _save,
            onChanged: (v) => setState(() => _save = v),
          ),
          if (_save)
            BankTextField(
              fieldKey: const ValueKey('toNickname'),
              controller: _nickname,
              label: 'Nickname (optional)',
              icon: Icons.tag_rounded,
              textCapitalization: TextCapitalization.words,
            ),
        ],
      ],
    ),
  );

  Widget _amountStep(List<BankAccount> all, BankAccount from) {
    final c = context.colors;
    final fee = _fee();
    final recipient = switch (_type) {
      TransferType.own => all.firstWhere((a) => a.id == _toOwnId, orElse: () => from).name,
      TransferType.saved => _selected?.displayName ?? '',
      _ => _name.text.trim(),
    };
    return ListView(
      key: const ValueKey('amountStep'),
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.lg),
      children: [
        Form(
          key: _amountForm,
          child: Column(
            children: [
              Text('Sending to $recipient', style: AppTypography.body.copyWith(color: c.textSecondary)),
              AmountInput(
                fieldKey: const ValueKey('amount'),
                controller: _amount,
                autofocus: true,
                validator: (v) => Validators.amount(v, max: from.balance - fee),
                onChanged: (_) => setState(() {}),
              ),
              Text('Available ${formatMoney(from.balance)}', style: AppTypography.bodySmall.copyWith(color: c.textSecondary)),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                radius: 20,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    SummaryRow('Transfer fee', fee == 0 ? 'Free' : formatMoney(fee)),
                    SummaryRow('Total', formatMoney((double.tryParse(_amount.text) ?? 0) + fee), bold: true),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              BankTextField(
                fieldKey: const ValueKey('reference'),
                controller: _reference,
                label: 'Reference (optional)',
                icon: Icons.edit_note_rounded,
                textInputAction: TextInputAction.done,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Schedule for later', style: AppTypography.body),
                subtitle: _scheduled == null ? null : Text('On ${formatGroupDate(_scheduled!, DateTime.now())}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                value: _scheduled != null,
                onChanged: (on) async {
                  if (on) {
                    await _pickDate();
                  } else {
                    setState(() {
                      _scheduled = null;
                      _recurrence = Recurrence.once;
                    });
                  }
                },
              ),
              if (_scheduled != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Repeat', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                ),
                const SizedBox(height: 6),
                SegmentedButton<Recurrence>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: Recurrence.once, label: Text('Once')),
                    ButtonSegment(value: Recurrence.weekly, label: Text('Weekly')),
                    ButtonSegment(value: Recurrence.monthly, label: Text('Monthly')),
                  ],
                  selected: {_recurrence},
                  onSelectionChanged: (s) => setState(() => _recurrence = s.first),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(label: 'Review', icon: Icons.arrow_forward_rounded, onPressed: () => _review(all, from)),
      ],
    );
  }
}
