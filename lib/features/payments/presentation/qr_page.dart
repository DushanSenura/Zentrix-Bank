import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/amount_input.dart';
import '../../../core/widgets/bank_snackbar.dart';
import '../../../core/widgets/flow_page.dart';
import '../../../core/widgets/glass_bottom_sheet.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/payment_models.dart';
import 'payment_widgets.dart';
import '../domain/qr_payload.dart';

class QrPage extends ConsumerStatefulWidget {
  const QrPage({super.key, this.showMyQr = false});
  final bool showMyQr;

  @override
  ConsumerState<QrPage> createState() => _QrPageState();
}

class _QrPageState extends ConsumerState<QrPage> {
  late bool _mine = widget.showMyQr;

  bool _handling = false;

  Future<void> _scanned(String label, String payload) async {
    if (_handling) return; // the camera keeps reporting while the amount sheet is open
    _handling = true;
    try {
      await _handle(label, payload);
    } finally {
      _handling = false;
    }
  }

  Future<void> _handle(String label, String payload) async {
    HapticFeedback.mediumImpact();
    final merchant = parseMerchantQr(payload);
    if (merchant == null) {
      BankSnackbar.show(context, 'That isn’t a Zentrix payment code, so nothing was started.', kind: SnackKind.error);
      return;
    }
    final amount = await showGlassSheet<double>(context, builder: (_) => _MerchantSheet(merchant: merchant));
    if (amount == null || !mounted) return;
    final accounts = ref.read(accountsProvider).value ?? const <BankAccount>[];
    final from = defaultPayAccount(accounts, ref.read(settingsProvider).defaultAccountId);
    ref.read(paymentDraftProvider.notifier).set(
      PaymentDraft(
        kind: PaymentKind.qr,
        fromAccountId: from.id,
        payee: merchant.name,
        payeeDetail: 'Merchant ID ${merchant.id}',
        amount: amount,
        category: merchant.category,
        details: const [('Method', 'QR payment (simulated)')],
      ),
    );
    context.push('/pay/confirm');
  }

  @override
  Widget build(BuildContext context) => FlowPage(
    title: _mine ? 'My QR' : 'Scan to pay',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Scan'), icon: Icon(Icons.qr_code_scanner_rounded)),
            ButtonSegment(value: true, label: Text('My QR'), icon: Icon(Icons.qr_code_2_rounded)),
          ],
          selected: {_mine},
          onSelectionChanged: (s) => setState(() => _mine = s.first),
        ),
        const SizedBox(height: AppSpacing.md),
        AnimatedSwitcher(
          duration: AppAnimations.scaled(context, AppAnimations.normal),
          child: _mine ? const _MyQr(key: ValueKey('mine')) : _Scanner(key: const ValueKey('scan'), onScanned: _scanned),
        ),
      ],
    ),
  );
}

class _Scanner extends ConsumerWidget {
  const _Scanner({super.key, required this.onScanned});
  final void Function(String label, String payload) onScanned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final scanner = ref.watch(qrScannerBuilderProvider);
    return Column(
      children: [
        GlassCard(
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: 300,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  scanner(context, (code) => onScanned('Camera', code)),
                  IgnorePointer(child: ExcludeSemantics(child: CustomPaint(painter: _ViewfinderPainter(color: c.accent)))),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: c.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Point the camera at a Zentrix payment QR code. No real payment network is connected in this prototype, so only Zentrix codes are accepted.',
                style: AppTypography.caption.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Align(alignment: Alignment.centerLeft, child: Semantics(header: true, child: const Text('No code to hand? Try a sample', style: AppTypography.title))),
        const SizedBox(height: AppSpacing.xs),
        for (final (label, payload) in sampleScans)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: GlassCard(
              radius: 20,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              onTap: () => onScanned(label, payload),
              semanticLabel: 'Simulate scanning $label',
              child: ExcludeSemantics(
                child: ListTile(
                  minTileHeight: 56,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.qr_code_scanner_rounded, color: c.accent),
                  title: Text(label, style: AppTypography.title),
                  trailing: Icon(Icons.chevron_right_rounded, color: c.textSecondary),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.62;
    final box = Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 28.0;
    for (final (corner, dx, dy) in [
      (box.topLeft, 1.0, 1.0),
      (box.topRight, -1.0, 1.0),
      (box.bottomLeft, 1.0, -1.0),
      (box.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(corner, corner.translate(len * dx, 0), paint);
      canvas.drawLine(corner, corner.translate(0, len * dy), paint);
    }
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => old.color != color;
}

class _MyQr extends ConsumerWidget {
  const _MyQr({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final user = ref.watch(authProvider);
    if (user == null) return const SizedBox.shrink();
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Semantics(
            label: 'QR code for ${user.fullName}',
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: QrImageView(
                data: receiveQr(user.customerNumber, user.fullName),
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0A1B3D)),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0A1B3D)),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(user.fullName, style: AppTypography.h3),
          Text('Customer ${user.customerNumber}', style: AppTypography.body.copyWith(color: c.textSecondary)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Anyone with a Zentrix Pay-enabled app can scan this to find you. It contains no balances or card details.',
            style: AppTypography.caption.copyWith(color: c.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MerchantSheet extends StatefulWidget {
  const _MerchantSheet({required this.merchant});
  final QrMerchant merchant;

  @override
  State<_MerchantSheet> createState() => _MerchantSheetState();
}

class _MerchantSheetState extends State<_MerchantSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_rounded, size: 40, color: c.accent),
            const SizedBox(height: AppSpacing.xs),
            Semantics(header: true, child: Text(widget.merchant.name, style: AppTypography.h2)),
            Text('Merchant ID ${widget.merchant.id}', style: AppTypography.caption.copyWith(color: c.textSecondary)),
            const SizedBox(height: AppSpacing.md),
            AmountInput(
              fieldKey: const ValueKey('qrAmount'),
              controller: _amount,
              autofocus: true,
              validator: (v) => Validators.amount(v),
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Continue',
              icon: Icons.arrow_forward_rounded,
              onPressed: () {
                if (_form.currentState!.validate()) Navigator.of(context).pop(double.parse(_amount.text));
              },
            ),
          ],
        ),
      ),
    );
  }
}
