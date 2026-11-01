import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/models.dart';
import '../../payments/presentation/payment_widgets.dart';
import 'bank_card_widget.dart';
import 'card_actions.dart';
import 'request_card_sheet.dart';

enum CardStatus { active, frozen, blocked, pendingApproval, preparing, readyToCollect }

CardStatus cardStatusOf(BankCard c) {
  if (c.blocked) return CardStatus.blocked;
  switch (c.issuance) {
    case CardIssuance.pendingApproval:
      return CardStatus.pendingApproval;
    case CardIssuance.preparing:
      return CardStatus.preparing;
    case CardIssuance.readyToCollect:
      return CardStatus.readyToCollect;
    case CardIssuance.active:
      return c.frozen ? CardStatus.frozen : CardStatus.active;
  }
}

String cardStatusLabel(CardStatus s) => switch (s) {
  CardStatus.active => 'Active',
  CardStatus.frozen => 'Frozen',
  CardStatus.blocked => 'Blocked',
  CardStatus.pendingApproval => 'Awaiting bank approval',
  CardStatus.preparing => 'Being prepared',
  CardStatus.readyToCollect => 'Ready to collect',
};

Color _statusColor(AppColors c, CardStatus s) => switch (s) {
  CardStatus.active => c.success,
  CardStatus.frozen => c.warning,
  CardStatus.blocked => c.error,
  CardStatus.pendingApproval || CardStatus.preparing => c.textSecondary,
  CardStatus.readyToCollect => c.accent,
};

IconData _statusIcon(CardStatus s) => switch (s) {
  CardStatus.active => Icons.check_circle_rounded,
  CardStatus.frozen => Icons.ac_unit_rounded,
  CardStatus.blocked => Icons.block_rounded,
  CardStatus.pendingApproval => Icons.hourglass_top_rounded,
  CardStatus.preparing => Icons.inventory_2_rounded,
  CardStatus.readyToCollect => Icons.storefront_rounded,
};

/// Status as text and an icon, never colour alone.
class CardStatusChip extends StatelessWidget {
  const CardStatusChip({super.key, required this.status});
  final CardStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context.colors, status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_statusIcon(status), size: 16, color: color),
        const SizedBox(width: 4),
        Text(cardStatusLabel(status), style: AppTypography.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// All your cards in one place, each with its status; open one to freeze it, set limits, change its PIN or report it.
class CardManagementPage extends ConsumerWidget {
  const CardManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final cards = ref.watch(cardsProvider);
    return FlowPage(
      title: 'Card management',
      child: RefreshIndicator(
        onRefresh: () async => ref.refresh(cardsProvider.future),
        child: cards.when(
          loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 220, radius: 24)),
          error: (e, _) => ErrorView(error: e, what: 'your cards', onRetry: () => ref.invalidate(cardsProvider)),
          data: (list) {
            final needAttention = list.where((k) => cardStatusOf(k) != CardStatus.active).length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
              children: [
                if (list.isEmpty)
                  EmptyState(
                    icon: Icons.credit_card_rounded,
                    title: 'No cards yet',
                    message: 'Request a virtual card to pay online straight away, or order a debit card.',
                    action: FilledButton(onPressed: () => showRequestCardSheet(context), child: const Text('Request a card')),
                  )
                else ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '${list.length} ${list.length == 1 ? 'card' : 'cards'}'
                      '${needAttention == 0 ? ' · all active' : ' · $needAttention ${needAttention == 1 ? 'needs' : 'need'} attention'}',
                      style: AppTypography.body.copyWith(color: c.textSecondary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final card in list) _CardRow(card: card),
                  const SizedBox(height: AppSpacing.sm),
                  PrimaryButton(label: 'Request a new card', icon: Icons.add_card_rounded, onPressed: () => showRequestCardSheet(context)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.card});
  final BankCard card;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = cardStatusOf(card);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: GlassCard(
        radius: 22,
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: () => context.push('/cards/manage/${card.id}'),
        semanticLabel: '${cardKindLabel(card.kind)} card ending ${card.last4}, ${cardStatusLabel(status)}. Manage',
        child: ExcludeSemantics(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent.withAlpha(36)),
                child: Icon(card.kind == CardKind.virtual ? Icons.cloud_rounded : Icons.credit_card_rounded, color: c.accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${cardKindLabel(card.kind)} •••• ${card.last4}', style: AppTypography.title),
                    Text('${card.network == CardNetwork.visa ? 'Visa' : 'Mastercard'} · expires ${card.expiry}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                    const SizedBox(height: 4),
                    CardStatusChip(status: status),
                    if (card.issuance == CardIssuance.preparing && card.readyOn != null)
                      Text('Ready ${formatGroupDate(card.readyOn!, DateTime.now())}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                    if (card.issuance == CardIssuance.readyToCollect && card.collectionBranch != null)
                      Text('Collect from ${card.collectionBranch}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// One card: how it looks, whether it is switched on, and everything you can do with it.
class CardDetailPage extends ConsumerWidget {
  const CardDetailPage({super.key, required this.cardId});
  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final cards = ref.watch(cardsProvider);
    return FlowPage(
      title: 'Manage card',
      child: cards.when(
        loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 260, radius: 28)),
        error: (e, _) => ErrorView(error: e, what: 'this card', onRetry: () => ref.invalidate(cardsProvider)),
        data: (list) {
          final card = list.where((k) => k.id == cardId).firstOrNull;
          if (card == null) {
            return const EmptyState(icon: Icons.search_off_rounded, title: 'Card not found', message: 'It may have been replaced or removed.');
          }
          final status = cardStatusOf(card);
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
            children: [
              BankCardWidget(card: card),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                radius: 22,
                child: Column(
                  children: [
                    SummaryRow('Status', cardStatusLabel(status)),
                    SummaryRow('Type', '${cardKindLabel(card.kind)} card'),
                    SummaryRow('Network', card.network == CardNetwork.visa ? 'Visa' : 'Mastercard'),
                    SummaryRow('Number', '•••• ${card.last4}'),
                    SummaryRow('Expires', card.expiry),
                    SummaryRow('Name on card', card.holder),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              CardFreezeTile(card: card, onChanged: card.blocked || !card.usable ? null : () => toggleCardFreeze(context, ref, card)),
              if (!card.usable && !card.blocked)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('A card can only be frozen once it is active.', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                ),
              const SizedBox(height: AppSpacing.sm),
              CardActions(card: card),
            ],
          );
        },
      ),
    );
  }
}
