import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/bank_dropdown.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/models.dart';
import '../../dashboard/presentation/widgets.dart';
import '../../payments/presentation/payment_widgets.dart';
import '../domain/statement.dart';
import '../domain/statement_pdf.dart';
import '../../../core/widgets/error_view.dart';

class StatementsPage extends ConsumerStatefulWidget {
  const StatementsPage({super.key, this.accountId});
  final String? accountId;

  @override
  ConsumerState<StatementsPage> createState() => _StatementsPageState();
}

class _StatementsPageState extends ConsumerState<StatementsPage> {
  late String? _accountId = widget.accountId;
  int _monthsAgo = 0;

  DateTime get _month {
    final now = DateTime.now();
    return DateTime(now.year, now.month - _monthsAgo);
  }

  List<String> get _monthLabels => [for (var i = 0; i < 6; i++) DateFormat('MMMM yyyy').format(DateTime(DateTime.now().year, DateTime.now().month - i))];

  Future<void> _export(BankAccount account, List<Transaction> list, {required bool share}) async {
    final exporter = ref.read(statementExporterProvider);
    final csv = statementCsv(list, account);
    final name = statementFileName(account, _month);
    try {
      if (share) {
        await exporter.shareCsv(name, csv);
      } else {
        await exporter.saveCsv(name, csv);
        if (mounted) BankSnackbar.show(context, 'Saved $name to this device.', kind: SnackKind.success);
      }
    } catch (_) {
      if (mounted) BankSnackbar.show(context, 'Couldn’t export the statement.', kind: SnackKind.error);
    }
  }

  Future<void> _exportPdf(BankAccount account, List<Transaction> list, {required bool share}) async {
    final exporter = ref.read(statementExporterProvider);
    final name = statementPdfFileName(account, _month);
    try {
      final bytes = await ref.read(statementPdfBuilderProvider)(
        account: account,
        month: _month,
        transactions: list,
        customerName: ref.read(authProvider)?.fullName ?? '',
        generatedAt: DateTime.now(),
      );
      if (share) {
        await exporter.sharePdf(name, bytes);
      } else {
        await exporter.savePdf(name, bytes);
        if (mounted) BankSnackbar.show(context, 'Saved $name to this device.', kind: SnackKind.success);
      }
    } catch (_) {
      if (mounted) BankSnackbar.show(context, 'Couldn’t create the PDF statement.', kind: SnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accounts = ref.watch(accountsProvider);
    final txs = ref.watch(transactionsProvider);
    return FlowPage(
      title: 'Statements',
      child: accounts.when(
        loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 300, radius: 24)),
        error: (e, _) => ErrorView(error: e, what: 'statements', onRetry: () => ref.invalidate(accountsProvider)),
        data: (all) {
          final payable = payableAccounts(all);
          final account = payable.firstWhere((a) => a.id == _accountId, orElse: () => payable.first);
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
            children: [
              AccountSelector(label: 'Account', account: account, accounts: payable, onChanged: (id) => setState(() => _accountId = id)),
              const SizedBox(height: AppSpacing.sm),
              BankDropdown(
                label: 'Month',
                icon: Icons.calendar_month_rounded,
                items: _monthLabels,
                value: _monthLabels[_monthsAgo],
                onChanged: (v) => setState(() => _monthsAgo = _monthLabels.indexOf(v)),
              ),
              const SizedBox(height: AppSpacing.md),
              txs.when(
                loading: () => const Skeleton(height: 220, radius: 22),
                error: (e, _) => ErrorView(error: e, what: 'transactions', onRetry: () => ref.invalidate(transactionsProvider)),
                data: (all) {
                  final list = statementTransactions(all, account.id, _month);
                  if (list.isEmpty) {
                    return const EmptyState(icon: Icons.description_rounded, title: 'No activity', message: 'There are no settled transactions for this account and month.');
                  }
                  final s = summarize(list);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GlassCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          children: [
                            SummaryRow('Money in', formatMoney(s.moneyIn)),
                            SummaryRow('Money out', formatMoney(s.moneyOut)),
                            SummaryRow('Net', formatMoney(s.net, signed: true), bold: true),
                            SummaryRow('Transactions', '${s.count}'),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.touchTarget), side: BorderSide(color: c.glassBorder), foregroundColor: c.textPrimary),
                              onPressed: () => _export(account, list, share: true),
                              icon: const Icon(Icons.table_chart_rounded),
                              label: const Text('Share CSV'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          IconButton.outlined(
                            tooltip: 'Save CSV',
                            style: IconButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget), side: BorderSide(color: c.glassBorder)),
                            onPressed: () => _export(account, list, share: false),
                            icon: const Icon(Icons.download_rounded),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          PopupMenuButton<bool>(
                            tooltip: 'PDF statement',
                            onSelected: (share) => _exportPdf(account, list, share: share),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: true, child: Text('Share PDF')),
                              PopupMenuItem(value: false, child: Text('Save PDF')),
                            ],
                            child: Container(
                              width: AppSpacing.touchTarget,
                              height: AppSpacing.touchTarget,
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.glassBorder)),
                              child: const Icon(Icons.picture_as_pdf_rounded),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Semantics(header: true, child: const Text('Transactions', style: AppTypography.h3)),
                      for (final t in list) TransactionTile(tx: t, balanceVisible: true),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
