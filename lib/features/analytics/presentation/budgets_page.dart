import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/amount_input.dart';
import '../../../core/widgets/bank_dialog.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_bottom_sheet.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/models.dart';
import '../../dashboard/presentation/widgets.dart';
import '../domain/budgets.dart';

/// Set a monthly limit per category and watch month-to-date spending against it.
/// These are the customer's own targets: nothing is blocked when a limit is passed.
class BudgetsPage extends ConsumerWidget {
  const BudgetsPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, {TxCategory? category, required List<Budget> existing}) async {
    final txs = ref.read(transactionsProvider).value ?? const <Transaction>[];
    await showGlassSheet<void>(
      context,
      builder: (_) => _BudgetSheet(existing: existing, editing: category, transactions: txs),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final budgets = ref.watch(budgetsProvider);
    final txs = ref.watch(transactionsProvider);
    return FlowPage(
      title: 'Budgets',
      child: budgets.when(
        loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 220, radius: 24)),
        error: (e, _) => ErrorView(error: e, what: 'budgets', onRetry: () => ref.invalidate(budgetsProvider)),
        data: (list) {
          final progress = budgetProgress(list, txs.value ?? const [], DateTime.now());
          final spent = progress.fold(0.0, (s, p) => s + p.spent);
          final limit = progress.fold(0.0, (s, p) => s + p.budget.monthlyLimit);
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
            children: [
              if (list.isEmpty)
                const EmptyState(
                  icon: Icons.donut_small_rounded,
                  title: 'No budgets yet',
                  message: 'Set a monthly limit for food, shopping or anything else, and see how you’re doing as the month goes on.',
                )
              else ...[
                GlassCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('This month', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                      Semantics(
                        label: 'Spent ${formatMoney(spent)} of ${formatMoney(limit)} budgeted',
                        child: ExcludeSemantics(child: Text('${formatMoney(spent)} of ${formatMoney(limit)}', style: AppTypography.h3)),
                      ),
                      const SizedBox(height: 4),
                      Text('Spending in categories you’ve set a budget for.', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final p in progress) _BudgetTile(progress: p, onTap: () => _edit(context, ref, category: p.budget.category, existing: list)),
              ],
              const SizedBox(height: AppSpacing.md),
              if (list.length < budgetCategories.length)
                PrimaryButton(label: 'Add a budget', icon: Icons.add_rounded, onPressed: () => _edit(context, ref, existing: list))
              else
                Text('You have a budget for every category.', style: AppTypography.caption.copyWith(color: c.textSecondary), textAlign: TextAlign.center),
            ],
          );
        },
      ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({required this.progress, required this.onTap});
  final BudgetProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = progress;
    final color = switch (p.state) {
      BudgetState.onTrack => c.success,
      BudgetState.nearLimit => c.warning,
      BudgetState.over => c.error,
    };
    final status = switch (p.state) {
      BudgetState.onTrack => '${formatMoney(p.remaining)} left',
      BudgetState.nearLimit => 'Nearly there · ${formatMoney(p.remaining)} left',
      BudgetState.over => 'Over by ${formatMoney(-p.remaining)}',
    };
    final name = categoryLabel(p.budget.category);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: GlassCard(
        radius: 22,
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: onTap,
        semanticLabel: '$name budget. ${(p.fraction * 100).round()} percent used. Spent ${formatMoney(p.spent)} of ${formatMoney(p.budget.monthlyLimit)}. $status. Edit',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(categoryIcon(p.budget.category), color: c.accent),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(name, style: AppTypography.title)),
                  Text('${formatMoney(p.spent)} / ${formatMoney(p.budget.monthlyLimit)}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: p.fraction.clamp(0.0, 1.0)),
                  duration: AppAnimations.scaled(context, AppAnimations.number),
                  curve: AppAnimations.standard,
                  builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: c.divider, color: color),
                ),
              ),
              const SizedBox(height: 4),
              Text(status, style: AppTypography.caption.copyWith(color: p.state == BudgetState.onTrack ? c.textSecondary : color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetSheet extends ConsumerStatefulWidget {
  const _BudgetSheet({required this.existing, required this.editing, required this.transactions});
  final List<Budget> existing;
  final TxCategory? editing;
  final List<Transaction> transactions;

  @override
  ConsumerState<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<_BudgetSheet> {
  final _form = GlobalKey<FormState>();
  late final _limit = TextEditingController(
    text: widget.editing == null ? '' : widget.existing.firstWhere((b) => b.category == widget.editing).monthlyLimit.toStringAsFixed(0),
  );
  late TxCategory? _category = widget.editing ?? _free.firstOrNull;
  bool _busy = false;

  List<TxCategory> get _free => [for (final c in budgetCategories) if (!widget.existing.any((b) => b.category == c)) c];

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_category == null || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(budgetRepositoryProvider).save(Budget(category: _category!, monthlyLimit: double.parse(_limit.text.replaceAll(',', '').trim())));
      ref.invalidate(budgetsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) BankSnackbar.show(context, 'Couldn’t save the budget. Please try again.', kind: SnackKind.error);
      setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final ok = await showBankDialog(
      context,
      title: 'Remove this budget?',
      message: 'Your ${categoryLabel(_category!).toLowerCase()} budget will be deleted. Your spending isn’t affected.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(budgetRepositoryProvider).remove(_category!);
      ref.invalidate(budgetsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) BankSnackbar.show(context, 'Couldn’t remove the budget. Please try again.', kind: SnackKind.error);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final editing = widget.editing != null;
    final suggestion = _category == null ? null : suggestedBudget(widget.transactions, DateTime.now(), _category!);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text(editing ? '${categoryLabel(_category!)} budget' : 'Add a budget', style: AppTypography.h3)),
            const SizedBox(height: AppSpacing.xs),
            if (!editing)
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final cat in _free)
                    ChoiceChip(label: Text(categoryLabel(cat)), selected: _category == cat, onSelected: (_) => setState(() => _category = cat)),
                ],
              ),
            AmountInput(
              fieldKey: const ValueKey('budgetLimit'),
              controller: _limit,
              autofocus: !editing,
              onChanged: (_) => setState(() {}),
              validator: (v) => Validators.amount(v),
            ),
            Center(child: Text('per month', style: AppTypography.caption.copyWith(color: c.textSecondary))),
            if (suggestion != null)
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
                  onPressed: () => setState(() => _limit.text = suggestion.toStringAsFixed(0)),
                  child: Text('You usually spend about ${formatMoney(suggestion).replaceAll('.00', '')} · use it', style: TextStyle(color: c.accent)),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(label: 'Save', loading: _busy, onPressed: _category == null ? null : _save),
            if (editing)
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.touchTarget)),
                onPressed: _busy ? null : _remove,
                child: Text('Remove budget', style: TextStyle(color: c.error)),
              ),
          ],
        ),
      ),
    );
  }
}
