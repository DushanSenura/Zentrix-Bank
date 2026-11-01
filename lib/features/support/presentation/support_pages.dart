import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_bottom_sheet.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/device/device_services.dart';
import '../../../core/device/geo.dart';
import '../../../shared/models/engagement_models.dart';
import '../domain/support_content.dart';
import '../../../core/widgets/error_view.dart';

class SupportPage extends ConsumerWidget {
  const SupportPage({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, Uri uri, String failure) async {
    final ok = await ref.read(linkLauncherProvider).open(uri);
    if (!ok && context.mounted) BankSnackbar.show(context, failure, kind: SnackKind.warning);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    Widget tile(IconData icon, String title, String subtitle, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: GlassCard(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        onTap: onTap,
        semanticLabel: '$title. $subtitle',
        child: ExcludeSemantics(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 60,
            leading: Icon(icon, color: c.accent),
            title: Text(title, style: AppTypography.title),
            subtitle: Text(subtitle, style: AppTypography.caption.copyWith(color: c.textSecondary)),
            trailing: Icon(Icons.chevron_right_rounded, color: c.textSecondary),
          ),
        ),
      ),
    );

    return FlowPage(
      title: 'Help & support',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
        children: [
          tile(Icons.chat_bubble_rounded, 'Chat with us', 'Automated assistant (prototype)', () => context.push('/support/chat')),
          tile(Icons.call_rounded, 'Call the bank', supportPhone, () => _open(context, ref, Uri(scheme: 'tel', path: supportPhone), 'Couldn’t open the phone app. Call $supportPhone.')),
          tile(Icons.mail_rounded, 'Email support', supportEmail, () => _open(context, ref, Uri(scheme: 'mailto', path: supportEmail), 'Couldn’t open your mail app. Write to $supportEmail.')),
          tile(Icons.location_on_rounded, 'Branches & ATMs', 'Find one near you', () => context.push('/support/branches')),
          tile(Icons.fact_check_rounded, 'My disputes', 'Payments you’ve reported', () => context.push('/disputes')),
          tile(Icons.flag_rounded, 'Report a problem', 'Tell us what went wrong', () => _report(context)),
          const SizedBox(height: AppSpacing.md),
          Semantics(header: true, child: const Text('Frequently asked questions', style: AppTypography.h3)),
          const SizedBox(height: AppSpacing.xs),
          GlassCard(
            radius: 22,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Column(
              children: [
                for (final f in faqs)
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.sm),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      title: Text(f.question, style: AppTypography.title),
                      children: [Text(f.answer, style: AppTypography.body.copyWith(color: c.textSecondary))],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _report(BuildContext context) async {
    final sent = await showGlassSheet<bool>(
      context,
      builder: (context) {
        final controller = TextEditingController();
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: const Text('Report a problem', style: AppTypography.h3)),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: controller,
                maxLines: 4,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: const InputDecoration(hintText: 'Describe what happened'),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(label: 'Submit', onPressed: () => Navigator.of(context).pop(true)),
            ],
          ),
        );
      },
    );
    if (sent == true && context.mounted) {
      BankSnackbar.show(context, 'Noted. In this prototype the report isn’t sent to the bank.', kind: SnackKind.info);
    }
  }
}

class _Message {
  const _Message(this.text, this.mine, this.at);
  final String text;
  final bool mine;
  final DateTime at;
}

/// Chat with a rule-based assistant. It says what it is, and never poses as a person.
class SupportChatPage extends StatefulWidget {
  const SupportChatPage({super.key});

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Message>[
    _Message('Hi, I’m the automated assistant. I can answer questions about cards, limits, fees and passwords. For anything else, call $supportPhone.', false, DateTime.now()),
  ];
  bool _typing = false;
  Timer? _reply;

  @override
  void dispose() {
    _reply?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: AppAnimations.scaled(context, AppAnimations.normal), curve: AppAnimations.standard);
  });

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty || _typing) return;
    _input.clear();
    setState(() {
      _messages.add(_Message(text, true, DateTime.now()));
      _typing = true;
    });
    _toEnd();
    _reply = Timer(AppAnimations.scaled(context, const Duration(milliseconds: 900)), () {
      if (!mounted) return;
      setState(() {
        _typing = false;
        _messages.add(_Message(botReply(text), false, DateTime.now()));
      });
      _toEnd();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FlowPage(
      title: 'Chat',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: c.success)),
                const SizedBox(width: 6),
                Expanded(child: Text('Automated assistant · not a person · prototype', style: AppTypography.caption.copyWith(color: c.textSecondary))),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(AppSpacing.gutter),
              itemCount: _messages.length + (_typing ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length) return const _TypingBubble();
                final m = _messages[i];
                return Align(
                  alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                    child: Semantics(
                      label: '${m.mine ? 'You' : 'Assistant'}: ${m.text}. ${DateFormat('h:mm a').format(m.at)}',
                      child: ExcludeSemantics(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: m.mine ? c.primary : c.glassFill,
                            border: m.mine ? null : Border.all(color: c.glassBorder),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(m.mine ? 18 : 4),
                              bottomRight: Radius.circular(m.mine ? 4 : 18),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Align(alignment: Alignment.centerLeft, child: Text(m.text, style: AppTypography.body.copyWith(color: m.mine ? c.onPrimary : c.textPrimary))),
                              const SizedBox(height: 2),
                              Text(DateFormat('h:mm a').format(m.at), style: AppTypography.caption.copyWith(fontSize: 10.5, color: m.mine ? c.onPrimary.withAlpha(190) : c.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.sm),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Attach a file',
                  constraints: const BoxConstraints(minWidth: AppSpacing.touchTarget, minHeight: AppSpacing.touchTarget),
                  onPressed: () => BankSnackbar.show(context, 'Attachments aren’t available in the prototype.', kind: SnackKind.info),
                  icon: Icon(Icons.attach_file_rounded, color: c.textSecondary),
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: TextStyle(color: c.textPrimary),
                    decoration: const InputDecoration(hintText: 'Type a message'),
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Send',
                  constraints: const BoxConstraints(minWidth: AppSpacing.touchTarget, minHeight: AppSpacing.touchTarget),
                  onPressed: _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppAnimations.reduced(context) ? _c.value = 0.5 : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      label: 'Assistant is typing',
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
          decoration: BoxDecoration(color: c.glassFill, border: Border.all(color: c.glassBorder), borderRadius: BorderRadius.circular(18)),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.textSecondary.withAlpha((90 + 165 * (((_c.value + i / 3) % 1) < 0.5 ? 1 : 0)).round())),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BranchesPage extends ConsumerStatefulWidget {
  const BranchesPage({super.key});

  @override
  ConsumerState<BranchesPage> createState() => _BranchesPageState();
}

class _BranchesPageState extends ConsumerState<BranchesPage> {
  GeoPoint? _me;
  bool _locating = false;

  Future<void> _findMe() async {
    setState(() => _locating = true);
    final here = await ref.read(locationServiceProvider).current();
    if (!mounted) return;
    setState(() {
      _me = here;
      _locating = false;
    });
    if (here == null) {
      BankSnackbar.show(context, 'We couldn’t get your location. Check that location is on and allowed, or use the list as it is.', kind: SnackKind.warning);
    }
  }

  /// With a position, real distances (nearest first); without one, the listed reference distances.
  List<SupportBranch> _arranged(List<SupportBranch> list) {
    final me = _me;
    if (me == null) return list;
    final withDistance = [
      for (final b in list) b.hasLocation ? b.withDistance(double.parse(distanceKm(me.latitude, me.longitude, b.latitude!, b.longitude!).toStringAsFixed(1))) : b,
    ]..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return withDistance;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final branches = ref.watch(branchesProvider);
    return FlowPage(
      title: 'Branches & ATMs',
      child: branches.when(
        loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.gutter), child: Skeleton(height: 260, radius: 22)),
        error: (e, _) => ErrorView(error: e, what: 'locations', onRetry: () => ref.invalidate(branchesProvider)),
        data: (raw) {
          final list = _arranged(raw);
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.touchTarget), side: BorderSide(color: c.glassBorder), foregroundColor: c.textPrimary),
                onPressed: _locating ? null : _findMe,
                icon: _locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location_rounded),
                label: Text(_me == null ? 'Sort by distance from me' : 'Update my location'),
              ),
              const SizedBox(height: 6),
              Text(
                _me == null
                    ? 'Sample locations. Distances are from a reference point until you share where you are. Your location is used on this screen only and is never stored or sent.'
                    : 'Distances are in a straight line from where you are now.',
                style: AppTypography.caption.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final b in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: GlassCard(
                    radius: 20,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                    semanticLabel: '${b.name}, ${b.address}, ${b.distanceKm} kilometres. Get directions',
                    onTap: () async {
                      final uri = b.hasLocation ? directionsUri(b.latitude!, b.longitude!) : Uri.parse('geo:0,0?q=${Uri.encodeComponent(b.address)}');
                      final ok = await ref.read(linkLauncherProvider).open(uri);
                      if (!ok && context.mounted) BankSnackbar.show(context, 'No maps app available.', kind: SnackKind.warning);
                    },
                    child: ExcludeSemantics(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        minTileHeight: 64,
                        leading: Icon(b.isAtm ? Icons.atm_rounded : Icons.account_balance_rounded, color: c.accent),
                        title: Text(b.name, style: AppTypography.title),
                        subtitle: Text(b.address, style: AppTypography.caption.copyWith(color: c.textSecondary)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${b.distanceKm} km', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                            Icon(Icons.directions_rounded, size: 20, color: c.accent),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
