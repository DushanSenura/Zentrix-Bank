import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/fade_slide_in.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/models.dart';
import '../../dashboard/presentation/widgets.dart';
import '../domain/analytics.dart';
import '../../../core/widgets/error_view.dart';

Color categoryColor(BuildContext context, TxCategory c) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  const darkPalette = [0xFF5B8DFF, 0xFF22D3EE, 0xFF3DDC97, 0xFFFFB84D, 0xFFFF6B6B, 0xFFB388FF, 0xFFF48FB1, 0xFF90A4AE];
  const lightPalette = [0xFF1F55E0, 0xFF0891B2, 0xFF12805C, 0xFFB45309, 0xFFC62828, 0xFF6A3FD0, 0xFFC2185B, 0xFF546E7A];
  final i = spendingCategories.indexOf(spendingBucket(c));
  return Color((dark ? darkPalette : lightPalette)[i]);
}

enum _Period { month, quarter, half }

class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  _Period _period = _Period.month;

  int get _months => switch (_period) {
    _Period.month => 1,
    _Period.quarter => 3,
    _Period.half => 6,
  };

  @override
  Widget build(BuildContext context) {
    final txs = ref.watch(transactionsProvider);
    final visible = ref.watch(balanceVisibleProvider);
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(transactionsProvider);
          await ref.read(transactionsProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.navClearance),
          children: [
            const Text(AppStrings.navAnalytics, style: AppTypography.h1),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_Period>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Period.month, label: Text('This month')),
                  ButtonSegment(value: _Period.quarter, label: Text('3 months')),
                  ButtonSegment(value: _Period.half, label: Text('6 months')),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            txs.when(
              loading: () => const Column(
                children: [Skeleton(height: 140, radius: 22), SizedBox(height: 12), Skeleton(height: 280, radius: 22)],
              ),
              error: (e, _) => ErrorView(error: e, what: 'analytics', onRetry: () => ref.invalidate(transactionsProvider)),
              data: (list) => _Content(list: list, months: _months, visible: visible),
            ),
          ],
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.list, required this.months, required this.visible});
  final List<Transaction> list;
  final int months;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final c = context.colors;
    final totals = monthlyTotals(list, now);
    final window = totals.sublist(totals.length - months);
    final income = window.fold(0.0, (s, m) => s + m.income);
    final expense = window.fold(0.0, (s, m) => s + m.expense);
    final by = spendingByCategory(list, now, from: DateTime(now.year, now.month - (months - 1)), to: now);
    final insights = buildInsights(list, now);
    String money(double v) => visible ? formatMoney(v) : 'LKR ••••••';
    if (income == 0 && expense == 0) {
      return const EmptyState(icon: Icons.insights_rounded, title: 'No activity in this period', message: 'Charts appear once you have settled transactions. Try a longer period.');
    }
    final saved = income - expense;
    final tiles = [
      ('Income', money(income), Icons.south_west_rounded, c.success),
      ('Expenses', money(expense), Icons.north_east_rounded, c.error),
      ('Savings', money(saved), Icons.savings_rounded, saved >= 0 ? c.accent : c.warning),
      ('Cash flow / month', money(saved / months), Icons.waves_rounded, c.secondary),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeSlideIn(
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: AppSpacing.xs,
            crossAxisSpacing: AppSpacing.xs,
            childAspectRatio: 1.7 / MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5),
            children: [
              for (final (label, value, icon, color) in tiles)
                GlassCard(
                  radius: 20,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Icon(icon, size: 18, color: color),
                            const SizedBox(width: 6),
                            Expanded(child: Text(label, style: AppTypography.caption.copyWith(color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: AppTypography.amountSmall.copyWith(fontSize: 17))),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Section(title: 'Spending by category', child: _SpendingDonut(by: by, visible: visible)),
        const SizedBox(height: AppSpacing.md),
        _Section(title: 'Income vs expenses', child: _IncomeExpenseBars(totals: window, visible: visible)),
        if (window.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          _Section(title: 'Net each month', child: _NetLine(totals: window, visible: visible)),
        ],
        if (insights.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Semantics(header: true, child: const Text('Insights', style: AppTypography.h3)),
          const SizedBox(height: AppSpacing.xs),
          for (final i in insights)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: GlassCard(
                radius: 20,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(i.good ? Icons.trending_down_rounded : Icons.trending_up_rounded, color: i.good ? c.success : c.warning),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(i.text, style: AppTypography.body)),
                  ],
                ),
              ),
            ),
          Text(
            'Calculated from your own transactions. These are simple comparisons, not financial advice.',
            style: AppTypography.caption.copyWith(color: c.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeSlideIn(
    child: GlassCard(
      radius: 24,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: AppTypography.title)),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    ),
  );
}

/// Eases chart values from 0 on first appearance only.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.builder});
  final Widget Function(double t) builder;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: AppAnimations.scaled(context, const Duration(milliseconds: 800)),
    curve: AppAnimations.standard,
    builder: (_, t, _) => builder(t),
  );
}

class _SpendingDonut extends StatelessWidget {
  const _SpendingDonut({required this.by, required this.visible});
  final Map<TxCategory, double> by;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = by.values.fold(0.0, (s, v) => s + v);
    if (total == 0) {
      return Text('No spending in this period.', style: AppTypography.body.copyWith(color: c.textSecondary));
    }
    final entries = [for (final cat in spendingCategories) if ((by[cat] ?? 0) > 0) (cat, by[cat]!)]..sort((a, b) => b.$2.compareTo(a.$2));
    return Column(
      children: [
        Semantics(
          label: 'Spending by category. Largest: ${categoryLabel(entries.first.$1)}, ${(entries.first.$2 / total * 100).round()} percent.',
          child: ExcludeSemantics(
            child: SizedBox(
              height: 200,
              child: _Reveal(
                builder: (t) => Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      duration: AppAnimations.scaled(context, AppAnimations.slow),
                      PieChartData(
                        sectionsSpace: 3,
                        centerSpaceRadius: 62,
                        startDegreeOffset: -90,
                        sections: [
                          for (final (cat, v) in entries)
                            PieChartSectionData(value: v * t + 0.0001, color: categoryColor(context, cat), radius: 26, showTitle: false),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Spent', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                        Text(visible ? formatShortMoney(total * t) : '••••', style: AppTypography.h3),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final (cat, v) in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Semantics(
              label: '${categoryLabel(cat)}, ${(v / total * 100).round()} percent, ${visible ? formatMoney(v) : 'amount hidden'}',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: categoryColor(context, cat))),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(categoryLabel(cat), style: AppTypography.body)),
                    Text('${(v / total * 100).round()}%', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(width: 104, child: Text(visible ? formatMoney(v) : '••••••', textAlign: TextAlign.end, style: AppTypography.amountSmall.copyWith(fontSize: 13))),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// `1.2M`, `85K`, `950`.
String formatShortMoney(double v) {
  if (v >= 1e6) return 'LKR ${(v / 1e6).toStringAsFixed(1)}M';
  if (v >= 1e3) return 'LKR ${(v / 1e3).toStringAsFixed(0)}K';
  return 'LKR ${v.toStringAsFixed(0)}';
}

FlTitlesData _monthTitles(BuildContext context, List<MonthTotals> totals) {
  final c = context.colors;
  return FlTitlesData(
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    leftTitles: const AxisTitles(),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 28,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final i = value.round();
          if (i < 0 || i >= totals.length) return const SizedBox.shrink();
          return SideTitleWidget(
            meta: meta,
            child: Text(DateFormat('MMM').format(totals[i].month), style: AppTypography.caption.copyWith(color: c.textSecondary)),
          );
        },
      ),
    ),
  );
}

class _IncomeExpenseBars extends StatelessWidget {
  const _IncomeExpenseBars({required this.totals, required this.visible});
  final List<MonthTotals> totals;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final peak = totals.fold(0.0, (m, t) => math.max(m, math.max(t.income, t.expense)));
    return Column(
      children: [
        Semantics(
          label: 'Bar chart of income and expenses for ${totals.length} ${totals.length == 1 ? 'month' : 'months'}.',
          child: ExcludeSemantics(
            child: SizedBox(
              height: 190,
              child: _Reveal(
                builder: (t) => BarChart(
                  duration: AppAnimations.scaled(context, AppAnimations.slow),
                  BarChartData(
                    maxY: peak == 0 ? 1 : peak * 1.1,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: _monthTitles(context, totals),
                    barTouchData: BarTouchData(enabled: false),
                    barGroups: [
                      for (var i = 0; i < totals.length; i++)
                        BarChartGroupData(
                          x: i,
                          barsSpace: 4,
                          barRods: [
                            BarChartRodData(toY: totals[i].income * t, color: c.success, width: totals.length == 1 ? 28 : 12, borderRadius: BorderRadius.circular(4)),
                            BarChartRodData(toY: totals[i].expense * t, color: c.error, width: totals.length == 1 ? 28 : 12, borderRadius: BorderRadius.circular(4)),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Legend(color: c.success, label: 'Income'),
            const SizedBox(width: AppSpacing.md),
            _Legend(color: c.error, label: 'Expenses'),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(label, style: AppTypography.caption.copyWith(color: context.colors.textSecondary)),
    ],
  );
}

class _NetLine extends StatelessWidget {
  const _NetLine({required this.totals, required this.visible});
  final List<MonthTotals> totals;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nets = [for (final m in totals) m.net];
    final lo = nets.reduce(math.min), hi = nets.reduce(math.max);
    final pad = math.max((hi - lo).abs() * 0.2, 1000.0);
    return Semantics(
      label: 'Line chart of net savings per month, from ${DateFormat('MMMM').format(totals.first.month)} to ${DateFormat('MMMM').format(totals.last.month)}.',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 170,
          child: _Reveal(
            builder: (t) => LineChart(
              duration: AppAnimations.scaled(context, AppAnimations.slow),
              LineChartData(
                minY: math.min(lo, 0.0) - pad,
                maxY: hi + pad,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: math.max((hi - math.min(lo, 0.0)) / 3, 1.0),
                  getDrawingHorizontalLine: (_) => FlLine(color: c.divider, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: _monthTitles(context, totals),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: c.accent,
                    barWidth: 3,
                    dotData: FlDotData(getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 4, color: c.accent, strokeWidth: 2, strokeColor: c.surface)),
                    belowBarData: BarAreaData(show: true, color: c.accent.withAlpha(36)),
                    spots: [for (var i = 0; i < nets.length; i++) FlSpot(i.toDouble(), nets[i] * t)],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
