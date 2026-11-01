import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/bank_dialog.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/payment_models.dart';
import 'beneficiary_form_sheet.dart';
import 'payment_widgets.dart';
import '../../../core/widgets/error_view.dart';

class BeneficiariesPage extends ConsumerStatefulWidget {
  const BeneficiariesPage({super.key});

  @override
  ConsumerState<BeneficiariesPage> createState() => _BeneficiariesPageState();
}

class _BeneficiariesPageState extends ConsumerState<BeneficiariesPage> {
  String _query = '';

  Future<void> _remove(Beneficiary b) async {
    final ok = await showBankDialog(
      context,
      title: 'Remove ${b.displayName}?',
      message: 'You can add them again later.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(beneficiariesProvider.notifier).remove(b.id);
    if (mounted) BankSnackbar.show(context, '${b.displayName} removed.', kind: SnackKind.info);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = ref.watch(beneficiariesProvider);
    return FlowPage(
      title: 'Beneficiaries',
      trailing: IconButton(
        tooltip: 'Add beneficiary',
        constraints: const BoxConstraints(minWidth: AppSpacing.touchTarget, minHeight: AppSpacing.touchTarget),
        onPressed: () => showBeneficiarySheet(context),
        icon: Icon(Icons.person_add_alt_1_rounded, color: c.accent),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.sm),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search name, nickname or bank',
                prefixIcon: Icon(Icons.search_rounded, color: c.textSecondary),
              ),
            ),
          ),
          Expanded(
            child: list.when(
              loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 240, radius: 22)),
              error: (e, _) => ErrorView(error: e, what: 'beneficiaries', onRetry: () => ref.invalidate(beneficiariesProvider)),
              data: (all) {
                if (all.isEmpty) {
                  return EmptyState(
                    icon: Icons.group_add_rounded,
                    title: 'No beneficiaries added',
                    message: 'Save the people you pay often to send money faster.',
                    action: FilledButton(onPressed: () => showBeneficiarySheet(context), child: const Text('Add beneficiary')),
                  );
                }
                final shown = all
                    .where((b) => _query.isEmpty || '${b.name} ${b.nickname} ${b.bank}'.toLowerCase().contains(_query))
                    .toList();
                if (shown.isEmpty) {
                  return const EmptyState(icon: Icons.search_off_rounded, title: 'No matches', message: 'Try a different name or bank.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.lg),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
                  itemBuilder: (_, i) => _BeneficiaryTile(
                    b: shown[i],
                    onSend: () => context.push('/transfer', extra: shown[i]),
                    onFavorite: () => ref.read(beneficiariesProvider.notifier).edit(shown[i].copyWith(favorite: !shown[i].favorite)),
                    onEdit: () => showBeneficiarySheet(context, existing: shown[i]),
                    onRemove: () => _remove(shown[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BeneficiaryTile extends StatelessWidget {
  const _BeneficiaryTile({required this.b, required this.onSend, required this.onFavorite, required this.onEdit, required this.onRemove});
  final Beneficiary b;
  final VoidCallback onSend, onFavorite, onEdit, onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
      onTap: onSend,
      semanticLabel: 'Send money to ${b.displayName}, ${b.bank} ${b.masked}',
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: c.primary.withAlpha(60),
            child: Text(initialsOf(b.name), style: AppTypography.title.copyWith(color: c.textPrimary)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.displayName, style: AppTypography.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${b.nickname.isEmpty ? '' : '${b.name} · '}${b.bank} ${b.masked}',
                  style: AppTypography.caption.copyWith(color: c.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: b.favorite ? 'Remove from favourites' : 'Add to favourites',
            constraints: const BoxConstraints(minWidth: AppSpacing.touchTarget, minHeight: AppSpacing.touchTarget),
            onPressed: onFavorite,
            icon: AnimatedSwitcher(
              duration: AppAnimations.scaled(context, AppAnimations.fast),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: Icon(
                b.favorite ? Icons.star_rounded : Icons.star_border_rounded,
                key: ValueKey(b.favorite),
                color: b.favorite ? c.warning : c.textSecondary,
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More options',
            icon: Icon(Icons.more_vert_rounded, color: c.textSecondary),
            color: c.surface,
            onSelected: (v) => v == 'edit' ? onEdit() : onRemove(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit nickname')),
              PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
        ],
      ),
    );
  }
}
