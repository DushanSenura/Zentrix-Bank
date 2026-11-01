import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/models/engagement_models.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/service_models.dart';

String disputeStatusLabel(DisputeStatus s) => switch (s) {
  DisputeStatus.received => 'Received',
  DisputeStatus.inReview => 'In review',
};

/// Tell the bank what is wrong with one payment. The bank investigates; nothing is refunded or reversed by this screen.
class DisputeFormPage extends ConsumerStatefulWidget {
  const DisputeFormPage({super.key, required this.transactionId});
  final String transactionId;

  @override
  ConsumerState<DisputeFormPage> createState() => _DisputeFormPageState();
}

class _DisputeFormPageState extends ConsumerState<DisputeFormPage> {
  final _form = GlobalKey<FormState>();
  final _details = TextEditingController();
  DisputeReason _reason = DisputeReason.notMine;
  bool _busy = false;
  Dispute? _done;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit(Transaction tx) async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final d = await ref.read(disputeRepositoryProvider).raise(transaction: tx, reason: _reason, details: _details.text);
      ref.invalidate(disputesProvider);
      await ref.read(notificationsProvider.notifier).post(
        _reason == DisputeReason.notMine ? NotifCategory.security : NotifCategory.transactions,
        'Dispute received',
        'We’ve received your dispute about ${tx.merchant} (${formatMoney(tx.amount.abs())}). Your reference is ${d.id}.',
        severity: _reason == DisputeReason.notMine ? Severity.warning : Severity.info,
      );
      if (mounted) setState(() => _done = d);
    } on DisputeException catch (e) {
      if (mounted) BankSnackbar.show(context, e.message, kind: SnackKind.error);
    } catch (_) {
      if (mounted) BankSnackbar.show(context, 'We couldn’t send your dispute. Nothing was submitted — please try again.', kind: SnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final all = ref.watch(transactionsProvider);
    return FlowPage(
      title: 'Report a problem',
      child: all.when(
        loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 260, radius: 24)),
        error: (e, _) => ErrorView(error: e, what: 'this payment', onRetry: () => ref.invalidate(transactionsProvider)),
        data: (list) {
          final tx = list.where((t) => t.id == widget.transactionId).firstOrNull;
          if (tx == null) {
            return const EmptyState(icon: Icons.search_off_rounded, title: 'Payment not found', message: 'It may have been removed.');
          }
          final blocked = disputeBlockReason(tx);
          if (blocked != null) {
            return EmptyState(icon: Icons.info_outline_rounded, title: 'This can’t be disputed', message: blocked);
          }
          if (_done != null) return _Confirmation(dispute: _done!);
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
            children: [
              GlassCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.receipt_long_rounded, color: c.accent),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tx.merchant, style: AppTypography.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(formatGroupDate(tx.date, DateTime.now()), style: AppTypography.caption.copyWith(color: c.textSecondary)),
                        ],
                      ),
                    ),
                    Text(formatMoney(tx.amount.abs()), style: AppTypography.amountSmall),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Semantics(header: true, child: const Text('What went wrong?', style: AppTypography.h3)),
              RadioGroup<DisputeReason>(
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v ?? _reason),
                child: Column(
                  children: [
                    for (final r in DisputeReason.values)
                      RadioListTile<DisputeReason>(contentPadding: EdgeInsets.zero, value: r, title: Text(disputeReasonLabel(r), style: AppTypography.body)),
                  ],
                ),
              ),
              if (_reason == DisputeReason.notMine)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Semantics(
                    liveRegion: true,
                    child: GlassCard(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      radius: 18,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_rounded, size: 20, color: c.warning),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('If you think someone else used your card or account, protect it now.', style: AppTypography.bodySmall),
                                TextButton(
                                  style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget), padding: EdgeInsets.zero),
                                  onPressed: () => context.push('/cards'),
                                  child: Text('Go to my cards', style: TextStyle(color: c.accent)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Form(
                key: _form,
                child: TextFormField(
                  key: const ValueKey('disputeDetails'),
                  controller: _details,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _reason == DisputeReason.other ? 'Tell us what happened' : 'Anything else we should know? (optional)',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => _reason == DisputeReason.other && (v ?? '').trim().length < 10 ? 'Please give a little more detail (at least 10 characters).' : null,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Submitting this doesn’t refund or reverse the payment. The bank looks into it and contacts you.',
                style: AppTypography.caption.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(label: 'Submit dispute', loading: _busy, onPressed: () => _submit(tx)),
            ],
          );
        },
      ),
    );
  }
}

class _Confirmation extends StatelessWidget {
  const _Confirmation({required this.dispute});
  final Dispute dispute;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mark_email_read_rounded, size: 64, color: c.success),
          const SizedBox(height: AppSpacing.md),
          Semantics(header: true, liveRegion: true, child: const Text('Dispute received', style: AppTypography.h1, textAlign: TextAlign.center)),
          const SizedBox(height: AppSpacing.xs),
          Text('Your reference', style: AppTypography.body.copyWith(color: c.textSecondary)),
          SelectableText(dispute.id, style: AppTypography.h3),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'We’ll review it and contact you. Keep this reference handy if you call us. You can follow it under My disputes.',
            style: AppTypography.body.copyWith(color: c.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: 'View my disputes', onPressed: () => context.pushReplacement('/disputes')),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.touchTarget)),
            onPressed: () => context.pop(),
            child: Text('Done', style: TextStyle(color: c.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// Everything the customer has disputed, with where each one stands.
class DisputesPage extends ConsumerWidget {
  const DisputesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final list = ref.watch(disputesProvider);
    return FlowPage(
      title: 'My disputes',
      child: list.when(
        loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 200, radius: 24)),
        error: (e, _) => ErrorView(error: e, what: 'your disputes', onRetry: () => ref.invalidate(disputesProvider)),
        data: (all) => all.isEmpty
            ? const EmptyState(
                icon: Icons.fact_check_rounded,
                title: 'No disputes',
                message: 'If a payment looks wrong, open it from your history and choose Report.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
                children: [
                  for (final d in all)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: GlassCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        radius: 22,
                        child: Semantics(
                          container: true,
                          label: '${d.merchant}, ${formatMoney(d.amount)}, ${disputeReasonLabel(d.reason)}, ${disputeStatusLabel(d.statusAt(DateTime.now()))}, reference ${d.id}',
                          child: ExcludeSemantics(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(d.merchant, style: AppTypography.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    Text(formatMoney(d.amount), style: AppTypography.amountSmall),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(disputeReasonLabel(d.reason), style: AppTypography.bodySmall.copyWith(color: c.textSecondary)),
                                const SizedBox(height: AppSpacing.xs),
                                Row(
                                  children: [
                                    Icon(Icons.schedule_rounded, size: 16, color: c.accent),
                                    const SizedBox(width: 6),
                                    Text(disputeStatusLabel(d.statusAt(DateTime.now())), style: AppTypography.caption.copyWith(color: c.accent)),
                                    const Spacer(),
                                    Text('${d.id} · ${formatGroupDate(d.createdAt, DateTime.now())}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
