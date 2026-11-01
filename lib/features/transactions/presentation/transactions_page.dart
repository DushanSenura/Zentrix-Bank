import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/models.dart';
import '../../dashboard/presentation/widgets.dart';
import '../domain/transaction_filter.dart';
import 'transaction_filter_sheet.dart';
import '../../../core/widgets/error_view.dart';

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  late final _search = TextEditingController(text: ref.read(transactionFilterProvider).query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final filter = ref.watch(transactionFilterProvider);
    final visible = ref.watch(balanceVisibleProvider);
    final list = ref.watch(filteredTransactionsProvider);
    return FlowPage(
      title: 'Transactions',
      trailing: Badge(
        isLabelVisible: filter.filterCount > 0,
        label: Text('${filter.filterCount}'),
        offset: const Offset(-6, 6),
        child: IconButton(
          tooltip: filter.filterCount > 0 ? 'Filters, ${filter.filterCount} active' : 'Filters',
          constraints: const BoxConstraints(minWidth: AppSpacing.touchTarget, minHeight: AppSpacing.touchTarget),
          onPressed: () => showTransactionFilterSheet(context),
          icon: Icon(Icons.tune_rounded, color: filter.hasFilters ? c.accent : null),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xs),
            child: TextField(
              controller: _search,
              onChanged: ref.read(transactionFilterProvider.notifier).setQuery,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search merchant, reference or ID',
                prefixIcon: Icon(Icons.search_rounded, color: c.textSecondary),
                suffixIcon: filter.query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          ref.read(transactionFilterProvider.notifier).setQuery('');
                        },
                      ),
              ),
            ),
          ),
          if (filter.hasFilters)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: Row(
                children: [
                  Expanded(child: Text('${filter.filterCount} ${filter.filterCount == 1 ? 'filter' : 'filters'} applied', style: AppTypography.bodySmall.copyWith(color: c.textSecondary))),
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget)),
                    onPressed: ref.read(transactionFilterProvider.notifier).clearFilters,
                    child: Text('Clear', style: TextStyle(color: c.accent)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(transactionsProvider);
                await ref.read(transactionsProvider.future);
              },
              child: list.when(
                loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 360, radius: 22)),
                error: (e, _) => ErrorView(error: e, what: 'transactions', onRetry: () => ref.invalidate(transactionsProvider)),
                data: (items) {
                  if (items.isEmpty) {
                    final narrowed = filter.hasFilters || filter.query.isNotEmpty;
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 360,
                          child: EmptyState(
                            icon: narrowed ? Icons.search_off_rounded : Icons.receipt_long_rounded,
                            title: narrowed ? 'No matching transactions' : 'No transactions yet',
                            message: narrowed ? 'Try changing or clearing your filters.' : 'Your activity will appear here.',
                            action: narrowed
                                ? TextButton(
                                    onPressed: () {
                                      _search.clear();
                                      ref.read(transactionFilterProvider.notifier).set(const TransactionFilter());
                                    },
                                    child: const Text('Clear all'),
                                  )
                                : null,
                          ),
                        ),
                      ],
                    );
                  }
                  final rows = <Object>[for (final g in groupTransactions(items, DateTime.now())) ...[g.title, ...g.items]];
                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.lg),
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final row = rows[i];
                      if (row is String) {
                        return Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xxs),
                          child: Semantics(header: true, child: Text(row, style: AppTypography.title.copyWith(color: c.textSecondary))),
                        );
                      }
                      final t = row as Transaction;
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => context.push('/transactions/${t.id}', extra: t),
                        child: TransactionTile(tx: t, balanceVisible: visible),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
