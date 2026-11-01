import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import 'card_actions.dart';
import 'card_carousel.dart';
import 'request_card_sheet.dart';
import '../../../core/widgets/error_view.dart';

class CardsPage extends ConsumerStatefulWidget {
  const CardsPage({super.key});

  @override
  ConsumerState<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends ConsumerState<CardsPage> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider);
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async => ref.refresh(cardsProvider.future),
        child: ListView(
          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.navClearance),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: Text(AppStrings.navCards, style: AppTypography.h1),
            ),
            const SizedBox(height: AppSpacing.md),
            cards.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: Skeleton(height: 210, radius: 28),
              ),
              error: (e, _) => ErrorView(error: e, what: 'cards', onRetry: () => ref.invalidate(cardsProvider)),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.credit_card_rounded,
                    title: 'No cards yet',
                    message: 'Request a virtual card to pay online straight away, or order a debit card.',
                    action: FilledButton(onPressed: () => showRequestCardSheet(context), child: const Text('Request a card')),
                  );
                }
                final card = list[_selected.clamp(0, list.length - 1)];
                return Column(
                  children: [
                    CardCarousel(cards: list, onChanged: (i) => setState(() => _selected = i)),
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                      child: CardFreezeTile(card: card, onChanged: card.blocked ? null : () => toggleCardFreeze(context, ref, card)),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                      child: CardActions(card: card),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.touchTarget), side: BorderSide(color: context.colors.glassBorder), foregroundColor: context.colors.textPrimary),
                        onPressed: () => showRequestCardSheet(context),
                        icon: const Icon(Icons.add_card_rounded),
                        label: const Text('Request a new card'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                      child: TextButton(
                        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.touchTarget)),
                        onPressed: () => context.push('/cards/manage'),
                        child: Text('Manage all cards', style: TextStyle(color: context.colors.accent)),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
