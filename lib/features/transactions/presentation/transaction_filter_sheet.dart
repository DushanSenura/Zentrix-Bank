import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/glass_bottom_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/models.dart';
import '../../dashboard/presentation/widgets.dart';
import '../domain/transaction_filter.dart';

Future<void> showTransactionFilterSheet(BuildContext context) =>
    showGlassSheet<void>(context, builder: (_) => const _FilterSheet());

enum _Preset { any, week, month, quarter, custom }

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late final TransactionFilter _initial = ref.read(transactionFilterProvider);
  late DateTimeRange? _range = _initial.range;
  late final Set<TxCategory> _categories = {..._initial.categories};
  late Direction _direction = _initial.direction;
  late String? _account = _initial.accountId;
  late final _min = TextEditingController(text: _initial.minAmount?.toStringAsFixed(0) ?? '');
  late final _max = TextEditingController(text: _initial.maxAmount?.toStringAsFixed(0) ?? '');
  _Preset? _preset;

  @override
  void initState() {
    super.initState();
    _preset = _range == null ? _Preset.any : _Preset.custom;
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _setPreset(_Preset p, DateTime now) {
    setState(() {
      _preset = p;
      _range = switch (p) {
        _Preset.any || _Preset.custom => null,
        _Preset.week => DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
        _Preset.month => DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
        _Preset.quarter => DateTimeRange(start: now.subtract(const Duration(days: 90)), end: now),
      };
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() {
        _preset = _Preset.custom;
        _range = picked;
      });
    }
  }

  void _apply() {
    ref.read(transactionFilterProvider.notifier).set(
      ref.read(transactionFilterProvider).withFilters(
        range: _range,
        categories: _categories,
        direction: _direction,
        minAmount: double.tryParse(_min.text),
        maxAmount: double.tryParse(_max.text),
        accountId: _account,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accounts = ref.watch(accountsProvider).value ?? const <BankAccount>[];
    final now = DateTime.now();
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Text(t, style: AppTypography.title.copyWith(color: c.textSecondary)),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Semantics(header: true, child: const Text('Filter transactions', style: AppTypography.h3))),
              TextButton(
                onPressed: () {
                  ref.read(transactionFilterProvider.notifier).clearFilters();
                  Navigator.of(context).pop();
                },
                child: Text('Reset', style: TextStyle(color: c.accent)),
              ),
            ],
          ),
          label('Date'),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final (p, text) in [(_Preset.any, 'Any time'), (_Preset.week, '7 days'), (_Preset.month, '30 days'), (_Preset.quarter, '90 days')])
                ChoiceChip(label: Text(text), selected: _preset == p, onSelected: (_) => _setPreset(p, now)),
              ChoiceChip(
                label: Text(_preset == _Preset.custom && _range != null ? '${formatShortDate(_range!.start)} – ${formatShortDate(_range!.end)}' : 'Custom range'),
                selected: _preset == _Preset.custom,
                onSelected: (_) => _pickRange(),
              ),
            ],
          ),
          label('Type'),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<Direction>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: Direction.all, label: Text('All')),
                ButtonSegment(value: Direction.income, label: Text('Income')),
                ButtonSegment(value: Direction.expense, label: Text('Expenses')),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
          ),
          label('Category'),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final cat in TxCategory.values)
                FilterChip(
                  label: Text(categoryLabel(cat)),
                  selected: _categories.contains(cat),
                  onSelected: (on) => setState(() => on ? _categories.add(cat) : _categories.remove(cat)),
                ),
            ],
          ),
          label('Amount (LKR)'),
          Row(
            children: [
              for (final (ctrl, hint) in [(_min, 'Min'), (_max, 'Max')]) ...[
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(color: c.textPrimary),
                    decoration: InputDecoration(labelText: hint),
                  ),
                ),
                if (hint == 'Min') const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
          if (accounts.isNotEmpty) ...[
            label('Account'),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                ChoiceChip(label: const Text('All accounts'), selected: _account == null, onSelected: (_) => setState(() => _account = null)),
                for (final a in accounts.where((a) => a.type != AccountType.fixedDeposit))
                  ChoiceChip(label: Text(a.name), selected: _account == a.id, onSelected: (_) => setState(() => _account = a.id)),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: 'Apply filters', onPressed: _apply),
        ],
      ),
    );
  }
}
