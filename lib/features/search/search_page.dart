import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/theme/app_animations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/empty_state.dart';
import '../../shared/models/models.dart';
import '../../shared/models/payment_models.dart';
import 'domain/search.dart';

/// Recent searches live for the session only.
class RecentSearchesController extends Notifier<List<String>> {
  @override
  List<String> build() => const [];
  void add(String q) {
    final t = q.trim();
    if (t.isNotEmpty) state = [t, ...state.where((x) => x != t)].take(5).toList();
  }

  void clear() => state = const [];
}

final recentSearchesProvider = NotifierProvider<RecentSearchesController, List<String>>(RecentSearchesController.new);

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(SearchHit hit) {
    ref.read(recentSearchesProvider.notifier).add(_query);
    hit.extra == null ? context.push(hit.route) : context.push(hit.route, extra: hit.extra);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final recents = ref.watch(recentSearchesProvider);
    final txs = ref.watch(transactionsProvider).value ?? const <Transaction>[];
    final people = ref.watch(beneficiariesProvider).value ?? const <Beneficiary>[];
    final sections = searchAll(_query, transactions: txs, beneficiaries: people);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, AppSpacing.gutter, AppSpacing.xs),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        constraints: const BoxConstraints(minWidth: AppSpacing.touchTarget, minHeight: AppSpacing.touchTarget),
                        onPressed: context.pop,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      Expanded(
                        // The field grows out of the icon it replaced on the dashboard.
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.4, end: 1),
                          duration: AppAnimations.scaled(context, AppAnimations.normal),
                          curve: AppAnimations.standard,
                          builder: (_, t, child) => Align(alignment: Alignment.centerRight, widthFactor: 1, child: FractionallySizedBox(widthFactor: t, child: child)),
                          child: TextField(
                            controller: _controller,
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            onChanged: (v) => setState(() => _query = v),
                            style: TextStyle(color: c.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Search transactions, people, features…',
                              prefixIcon: Icon(Icons.search_rounded, color: c.textSecondary),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      icon: const Icon(Icons.close_rounded),
                                      onPressed: () {
                                        _controller.clear();
                                        setState(() => _query = '');
                                      },
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _query.trim().isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(AppSpacing.gutter),
                          children: [
                            if (recents.isNotEmpty) ...[
                              Row(
                                children: [
                                  Expanded(child: Semantics(header: true, child: const Text('Recent searches', style: AppTypography.title))),
                                  TextButton(onPressed: ref.read(recentSearchesProvider.notifier).clear, child: Text('Clear', style: TextStyle(color: c.accent))),
                                ],
                              ),
                              for (final r in recents)
                                ListTile(
                                  minTileHeight: AppSpacing.touchTarget,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.history_rounded, color: c.textSecondary),
                                  title: Text(r, style: AppTypography.body),
                                  onTap: () {
                                    _controller.text = r;
                                    setState(() => _query = r);
                                  },
                                ),
                            ] else
                              Text('Try “bills”, “pin”, a merchant name or a person.', style: AppTypography.body.copyWith(color: c.textSecondary)),
                          ],
                        )
                      : sections.isEmpty
                      ? EmptyState(icon: Icons.search_off_rounded, title: 'No results', message: 'Nothing matches “${_query.trim()}”.')
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.lg),
                          children: [
                            for (final s in sections) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: AppSpacing.md),
                                child: Semantics(header: true, child: Text(s.title, style: AppTypography.title.copyWith(color: c.textSecondary))),
                              ),
                              for (final hit in s.hits)
                                ListTile(
                                  minTileHeight: 56,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(hit.icon, color: c.accent),
                                  title: Text(hit.title, style: AppTypography.body),
                                  subtitle: Text(hit.subtitle, style: AppTypography.caption.copyWith(color: c.textSecondary)),
                                  trailing: Icon(Icons.chevron_right_rounded, color: c.textSecondary),
                                  onTap: () => _open(hit),
                                ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
