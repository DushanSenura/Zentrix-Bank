import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/bank_dialog.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/glass_bottom_sheet.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/engagement_models.dart';
import '../../../shared/models/models.dart';
import '../../payments/presentation/authorize_sheet.dart';

/// Freezes or unfreezes [card] and tells the customer what happened. The change is applied on screen at once and
/// rolled back if the bank refuses it.
Future<void> toggleCardFreeze(BuildContext context, WidgetRef ref, BankCard card) async {
  HapticFeedback.mediumImpact();
  final ok = await ref.read(cardsProvider.notifier).toggleFreeze(card.id);
  if (!context.mounted) return;
  if (!ok) {
    BankSnackbar.show(context, 'Couldn’t update card •••• ${card.last4}. Nothing was changed — please try again.', kind: SnackKind.error);
    return;
  }
  BankSnackbar.show(
    context,
    card.frozen ? 'Card •••• ${card.last4} unfrozen' : 'Card •••• ${card.last4} frozen',
    kind: card.frozen ? SnackKind.success : SnackKind.info,
  );
}

/// Limits, card PIN and lost/stolen for the selected card.
class CardActions extends ConsumerWidget {
  const CardActions({super.key, required this.card});
  final BankCard card;

  Future<bool> _authorise(BuildContext context, String title, String summary) async {
    final result = await authorizePayment(context, title: title, summary: summary);
    if (!context.mounted) return false;
    if (result == AuthResult.locked) {
      BankSnackbar.show(context, 'Too many incorrect PINs. Nothing was changed.', kind: SnackKind.error);
    }
    return result == AuthResult.approved;
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final confirmed = await showBankDialog(
      context,
      title: 'Report card lost or stolen?',
      message: 'Card •••• ${card.last4} will be blocked permanently and a replacement will be ordered. This can’t be undone.',
      confirmLabel: 'Block card',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    if (!await _authorise(context, 'Confirm block', 'Permanently block card •••• ${card.last4}.') || !context.mounted) return;
    try {
      await ref.read(cardRepositoryProvider).reportLostOrStolen(card.id);
      ref.invalidate(cardsProvider);
      await ref.read(notificationsProvider.notifier).post(
        NotifCategory.security,
        'Card blocked',
        'Your card ending ${card.last4} was reported lost or stolen and blocked. A replacement is on its way.',
        severity: Severity.critical,
      );
      if (context.mounted) BankSnackbar.show(context, 'Card blocked. A replacement has been ordered.', kind: SnackKind.success);
    } on CardException catch (e) {
      if (context.mounted) BankSnackbar.show(context, e.message, kind: SnackKind.error);
    } catch (_) {
      if (context.mounted) BankSnackbar.show(context, 'We couldn’t block the card. If it’s lost, call us now.', kind: SnackKind.error);
    }
  }

  Future<void> _activate(BuildContext context, WidgetRef ref) async {
    if (!await _authorise(context, 'Activate card', 'Activate card •••• ${card.last4} now that it has arrived.') || !context.mounted) return;
    try {
      await ref.read(cardRepositoryProvider).activateCard(card.id);
      ref.invalidate(cardsProvider);
      await ref.read(notificationsProvider.notifier).post(
        NotifCategory.security,
        'Card activated',
        'Your card ending ${card.last4} is now active.',
        severity: Severity.info,
      );
      if (context.mounted) BankSnackbar.show(context, 'Card •••• ${card.last4} is active.', kind: SnackKind.success);
    } on CardException catch (e) {
      if (context.mounted) BankSnackbar.show(context, e.message, kind: SnackKind.error);
    } catch (_) {
      if (context.mounted) BankSnackbar.show(context, 'We couldn’t activate the card. Please try again.', kind: SnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final blocked = card.blocked;
    // Until the bank has activated it (virtual) or the customer has collected and activated it (debit), nothing can be changed.
    final off = blocked || !card.usable;
    final items = <(IconData, String, String, VoidCallback?)>[
      (Icons.speed_rounded, 'Limits & online use', 'Daily limit, online and international payments', off ? null : () => showCardControls(context, card)),
      (Icons.pin_rounded, 'Change card PIN', 'Your 4-digit ATM and point-of-sale PIN', off ? null : () => context.push('/cards/pin/${card.id}')),
      (Icons.report_gmailerrorred_rounded, 'Report lost or stolen', 'Block this card and order a replacement', off ? null : () => _report(context, ref)),
    ];
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      radius: 22,
      child: Column(
        children: [
          if (card.issuance == CardIssuance.pendingApproval)
            _StageNote(
              icon: Icons.hourglass_top_rounded,
              title: 'Waiting for the bank',
              message: 'The bank reviews and activates virtual cards. You can’t use or change this one until then, and you can’t activate it yourself. We’ll notify you when it’s ready.',
            ),
          if (card.issuance == CardIssuance.preparing)
            _StageNote(
              icon: Icons.inventory_2_rounded,
              title: 'Being prepared',
              message: 'The bank is making your debit card. It will be ready to collect from ${card.collectionBranch ?? 'your chosen branch'}'
                  '${card.readyOn == null ? '' : ' on ${formatGroupDate(card.readyOn!, DateTime.now())}'} (about $debitCardPreparationDays days after you asked). We’ll notify you.',
            ),
          if (card.issuance == CardIssuance.readyToCollect)
            _StageNote(
              icon: Icons.storefront_rounded,
              title: 'Ready to collect',
              message: 'Collect your card from ${card.collectionBranch ?? 'your chosen branch'} and bring your ID. Once you have it, activate it here.',
              action: PrimaryButton(label: 'Activate card', icon: Icons.verified_rounded, onPressed: () => _activate(context, ref)),
            ),
          if (blocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.block_rounded, size: 20, color: c.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text('This card is blocked permanently. A replacement is on its way.', style: AppTypography.bodySmall.copyWith(color: c.error))),
                  ],
                ),
              ),
            ),
          for (final (icon, label, hint, onTap) in items)
            ListTile(
              minTileHeight: AppSpacing.touchTarget,
              enabled: onTap != null,
              leading: Icon(icon, color: onTap == null ? c.textSecondary : c.accent),
              title: Text(label, style: AppTypography.body),
              subtitle: Text(hint, style: AppTypography.caption.copyWith(color: c.textSecondary)),
              trailing: Icon(Icons.chevron_right_rounded, color: c.textSecondary),
              onTap: onTap,
            ),
        ],
      ),
    );
  }
}

Future<void> showCardControls(BuildContext context, BankCard card) =>
    showGlassSheet<void>(context, builder: (_) => _ControlsSheet(card: card));

class _ControlsSheet extends ConsumerStatefulWidget {
  const _ControlsSheet({required this.card});
  final BankCard card;

  @override
  ConsumerState<_ControlsSheet> createState() => _ControlsSheetState();
}

class _ControlsSheetState extends ConsumerState<_ControlsSheet> {
  CardControls? _edited;
  bool _busy = false;

  Future<void> _save(CardControls original, CardControls next) async {
    // Anything that makes the card easier to misuse needs the PIN; tightening does not.
    final loosens = next.dailyLimit > original.dailyLimit || (next.internationalEnabled && !original.internationalEnabled) || (next.onlineEnabled && !original.onlineEnabled);
    if (loosens) {
      final result = await authorizePayment(
        context,
        title: 'Confirm card changes',
        summary: 'Update spending controls for card •••• ${widget.card.last4}.',
      );
      if (!mounted) return;
      if (result == AuthResult.locked) {
        BankSnackbar.show(context, 'Too many incorrect PINs. Nothing was changed.', kind: SnackKind.error);
        return;
      }
      if (result != AuthResult.approved) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(cardRepositoryProvider).updateControls(widget.card.id, next);
      ref.invalidate(cardControlsProvider(widget.card.id));
      await ref.read(notificationsProvider.notifier).post(
        NotifCategory.security,
        'Card controls changed',
        'Controls for your card ending ${widget.card.last4} were updated: daily limit ${formatMoney(next.dailyLimit)}, '
            'online ${next.onlineEnabled ? 'on' : 'off'}, international ${next.internationalEnabled ? 'on' : 'off'}.',
        severity: loosens ? Severity.warning : Severity.info,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      BankSnackbar.show(context, 'Card controls saved.', kind: SnackKind.success);
    } on CardException catch (e) {
      if (mounted) BankSnackbar.show(context, e.message, kind: SnackKind.error);
    } catch (_) {
      if (mounted) BankSnackbar.show(context, 'Couldn’t save. Nothing was changed.', kind: SnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(cardControlsProvider(widget.card.id));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: async.when(
        loading: () => const Skeleton(height: 260, radius: 22),
        error: (e, _) => ErrorView(error: e, what: 'card controls', onRetry: () => ref.invalidate(cardControlsProvider(widget.card.id))),
        data: (original) {
          final v = _edited ?? original;
          final divisions = (v.maxDailyLimit / 1000).round().clamp(1, 1000);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text('Card •••• ${widget.card.last4}', style: AppTypography.h3)),
              const SizedBox(height: AppSpacing.md),
              Text('Daily spending limit', style: AppTypography.title.copyWith(color: c.textSecondary)),
              Text(formatMoney(v.dailyLimit), style: AppTypography.h2),
              Semantics(
                label: 'Daily spending limit',
                value: formatMoney(v.dailyLimit),
                child: Slider(
                  min: 0,
                  max: v.maxDailyLimit,
                  divisions: divisions,
                  value: v.dailyLimit.clamp(0, v.maxDailyLimit),
                  label: formatMoney(v.dailyLimit),
                  onChanged: _busy ? null : (x) => setState(() => _edited = v.copyWith(dailyLimit: (x / 1000).round() * 1000.0)),
                ),
              ),
              Text('The bank allows up to ${formatMoney(v.maxDailyLimit)} a day on this card.', style: AppTypography.caption.copyWith(color: c.textSecondary)),
              const SizedBox(height: AppSpacing.xs),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Online payments', style: AppTypography.body),
                subtitle: Text('Websites and apps', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                value: v.onlineEnabled,
                onChanged: _busy ? null : (x) => setState(() => _edited = v.copyWith(onlineEnabled: x)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('International use', style: AppTypography.body),
                subtitle: Text('Purchases and ATMs abroad', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                value: v.internationalEnabled,
                onChanged: _busy ? null : (x) => setState(() => _edited = v.copyWith(internationalEnabled: x)),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: 'Save',
                loading: _busy,
                onPressed: _edited == null ? null : () => _save(original, _edited!),
              ),
            ],
          );
        },
      ),
    );
  }
}

class CardFreezeTile extends StatelessWidget {
  const CardFreezeTile({super.key, required this.card, required this.onChanged});
  final BankCard card;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      radius: 22,
      child: MergeSemantics(
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: AppAnimations.scaled(context, AppAnimations.normal),
              child: Icon(
                card.frozen ? Icons.lock_rounded : Icons.lock_open_rounded,
                key: ValueKey(card.frozen),
                color: card.frozen ? c.accent : c.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Freeze card', style: AppTypography.title),
                  Text(
                    card.frozen ? 'Payments are blocked' : 'Temporarily block all payments',
                    style: AppTypography.bodySmall.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            Switch(value: card.frozen || card.blocked, onChanged: onChanged == null ? null : (_) => onChanged!()),
          ],
        ),
      ),
    );
  }
}

class _StageNote extends StatelessWidget {
  const _StageNote({required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title, message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: '$title. $message',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 22, color: c.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppTypography.title),
                        const SizedBox(height: 2),
                        Text(message, style: AppTypography.bodySmall.copyWith(color: c.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(height: AppSpacing.xs), action!],
          ],
        ),
      ),
    );
  }
}
