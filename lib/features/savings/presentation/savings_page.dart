import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_animations.dart';
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
import '../../../core/widgets/glass_bottom_sheet.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/payment_models.dart';
import '../../payments/presentation/authorize_sheet.dart';
import '../../payments/presentation/payment_widgets.dart';
import '../../../core/widgets/error_view.dart';

/// Whole months from [from] until [to], never negative.
int monthsUntil(DateTime from, DateTime to) => math.max(0, (to.year - from.year) * 12 + to.month - from.month);

class SavingsPage extends ConsumerWidget {
  const SavingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final goals = ref.watch(goalsProvider);
    return FlowPage(
      title: 'Savings goals',
      trailing: IconButton(
        tooltip: 'New goal',
        constraints: const BoxConstraints(minWidth: AppSpacing.touchTarget, minHeight: AppSpacing.touchTarget),
        onPressed: () => showGlassSheet<void>(context, builder: (_) => const _NewGoalSheet()),
        icon: Icon(Icons.add_circle_rounded, color: c.accent),
      ),
      child: goals.when(
        loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 220, radius: 24)),
        error: (e, _) => ErrorView(error: e, what: 'goals', onRetry: () => ref.invalidate(goalsProvider)),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.savings_rounded,
                title: 'No savings goals yet',
                message: 'Set a target and watch it grow.',
                action: FilledButton(onPressed: () => showGlassSheet<void>(context, builder: (_) => const _NewGoalSheet()), child: const Text('Create a goal')),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) => _GoalCard(goal: list[i]),
              ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});
  final SavingsGoal goal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final remaining = math.max(0.0, goal.target - goal.saved);
    final months = monthsUntil(now, goal.targetDate);
    final done = goal.saved >= goal.target;
    final hint = done
        ? 'Goal reached.'
        : months == 0
        ? 'Target date is this month — ${formatMoney(remaining)} to go.'
        : 'Save about ${formatMoney((remaining / months).ceilToDouble())} a month to finish by ${formatGroupDate(goal.targetDate, now)}.';
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: '${goal.name}: ${(goal.progress * 100).round()} percent. ${formatMoney(goal.saved)} saved of ${formatMoney(goal.target)}.',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  _ProgressRing(progress: goal.progress),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(goal.name, style: AppTypography.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('${formatMoney(goal.saved)} / ${formatMoney(goal.target)}', style: AppTypography.bodySmall.copyWith(color: c.textSecondary)),
                        Text('Target ${formatGroupDate(goal.targetDate, now)}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(hint, style: AppTypography.bodySmall),
          if (goal.autoMonthly != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Automatic: ${formatMoney(goal.autoMonthly!)} a month (a saved instruction — the prototype doesn’t run it).',
                style: AppTypography.caption.copyWith(color: c.textSecondary),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.touchTarget), backgroundColor: c.primary, foregroundColor: c.onPrimary),
                  onPressed: () => showGlassSheet<void>(context, builder: (_) => _MoveSheet(goal: goal, deposit: true)),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add money'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.touchTarget), side: BorderSide(color: c.glassBorder), foregroundColor: c.textPrimary),
                  onPressed: goal.saved <= 0 ? null : () => showGlassSheet<void>(context, builder: (_) => _MoveSheet(goal: goal, deposit: false)),
                  icon: const Icon(Icons.remove_rounded),
                  label: const Text('Withdraw'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress),
      duration: AppAnimations.scaled(context, const Duration(milliseconds: 900)),
      curve: AppAnimations.standard,
      builder: (_, v, _) => SizedBox.square(
        dimension: 76,
        child: CustomPaint(
          painter: _RingPainter(v, c.accent, c.divider),
          child: Center(child: Text('${(v * 100).round()}%', style: AppTypography.title)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track);
  final double value;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.13;
    final arc = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, 0, math.pi * 2, false, paint..color = track);
    canvas.drawArc(arc, -math.pi / 2, math.pi * 2 * value, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track;
}

class _MoveSheet extends ConsumerStatefulWidget {
  const _MoveSheet({required this.goal, required this.deposit});
  final SavingsGoal goal;
  final bool deposit;

  @override
  ConsumerState<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends ConsumerState<_MoveSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  String? _accountId;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit(BankAccount account) async {
    if (!_form.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }
    final value = double.parse(_amount.text);
    final result = await authorizePayment(
      context,
      summary: widget.deposit
          ? 'Move ${formatMoney(value)} from ${account.name} to ${widget.goal.name}.'
          : 'Move ${formatMoney(value)} from ${widget.goal.name} to ${account.name}.',
    );
    if (!mounted) return;
    if (result == AuthResult.locked) {
      BankSnackbar.show(context, 'Too many incorrect PINs. Nothing was moved.', kind: SnackKind.error);
      return;
    }
    if (result != AuthResult.approved) return;
    setState(() => _busy = true);
    try {
      await ref.read(goalsProvider.notifier).move(widget.goal.id, account.id, widget.deposit ? value : -value);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(widget.deposit ? 'Added ${formatMoney(value)} to ${widget.goal.name}.' : 'Withdrew ${formatMoney(value)} from ${widget.goal.name}.')));
    } on PaymentException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      HapticFeedback.heavyImpact();
      BankSnackbar.show(context, e.message, kind: SnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = payableAccounts(ref.watch(accountsProvider).value ?? const []);
    if (accounts.isEmpty) return const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator()));
    final account = accounts.firstWhere((a) => a.id == _accountId, orElse: () => accounts.first);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(header: true, child: Text(widget.deposit ? 'Add to ${widget.goal.name}' : 'Withdraw from ${widget.goal.name}', style: AppTypography.h3)),
            const SizedBox(height: AppSpacing.sm),
            AccountSelector(label: widget.deposit ? 'From' : 'To', account: account, accounts: accounts, onChanged: (id) => setState(() => _accountId = id)),
            const SizedBox(height: AppSpacing.sm),
            AmountInput(
              fieldKey: const ValueKey('goalAmount'),
              controller: _amount,
              autofocus: true,
              validator: (v) => Validators.amount(v, max: widget.deposit ? account.balance : widget.goal.saved),
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(label: widget.deposit ? 'Add money' : 'Withdraw', loading: _busy, onPressed: () => _submit(account)),
          ],
        ),
      ),
    );
  }
}

class _NewGoalSheet extends ConsumerStatefulWidget {
  const _NewGoalSheet();

  @override
  ConsumerState<_NewGoalSheet> createState() => _NewGoalSheetState();
}

class _NewGoalSheetState extends ConsumerState<_NewGoalSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _auto = TextEditingController();
  final _dateText = TextEditingController();
  DateTime? _date;
  bool _autoOn = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _auto.dispose();
    _dateText.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: now.add(const Duration(days: 30)),
      lastDate: DateTime(now.year + 30),
      helpText: 'Target date',
    );
    if (d != null) {
      setState(() {
        _date = d;
        _dateText.text = formatGroupDate(d, DateTime.now());
      });
    }
  }

  Future<void> _create() async {
    final dateOk = _date != null;
    if (!_form.currentState!.validate() || !dateOk) {
      if (!dateOk) BankSnackbar.show(context, 'Choose a target date.', kind: SnackKind.warning);
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _busy = true);
    await ref.read(goalsProvider.notifier).create(
      SavingsGoal(
        id: 'g-${DateTime.now().microsecondsSinceEpoch}',
        name: _name.text.trim(),
        target: double.parse(_target.text),
        saved: 0,
        targetDate: _date!,
        autoMonthly: _autoOn ? double.tryParse(_auto.text) : null,
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: const Text('New savings goal', style: AppTypography.h3)),
            const SizedBox(height: AppSpacing.md),
            BankTextField(
              fieldKey: const ValueKey('goalName'),
              controller: _name,
              label: 'Goal name',
              icon: Icons.flag_rounded,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              validator: (v) => Validators.required(v, 'Goal name'),
            ),
            const SizedBox(height: AppSpacing.sm),
            BankTextField(
              fieldKey: const ValueKey('goalTarget'),
              controller: _target,
              label: 'Target amount (LKR)',
              icon: Icons.track_changes_rounded,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              textInputAction: TextInputAction.next,
              validator: (v) => Validators.amount(v),
            ),
            const SizedBox(height: AppSpacing.sm),
            BankTextField(
              fieldKey: const ValueKey('goalDate'),
              controller: _dateText,
              label: 'Target date',
              icon: Icons.event_rounded,
              onTap: _pickDate,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Automatic monthly contribution', style: AppTypography.body),
              subtitle: Text('Saved as an instruction. The prototype doesn’t run it.', style: AppTypography.caption.copyWith(color: c.textSecondary)),
              value: _autoOn,
              onChanged: (v) => setState(() => _autoOn = v),
            ),
            if (_autoOn)
              BankTextField(
                fieldKey: const ValueKey('goalAuto'),
                controller: _auto,
                label: 'Amount per month (LKR)',
                icon: Icons.autorenew_rounded,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                validator: (v) => Validators.amount(v),
              ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Create goal', loading: _busy, onPressed: _create),
          ],
        ),
      ),
    );
  }
}
