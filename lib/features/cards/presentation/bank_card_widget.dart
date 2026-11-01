import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/bank_logo.dart';
import '../../../shared/models/models.dart';

const _cardText = Colors.white;

List<Color> _gradientFor(CardKind kind) => switch (kind) {
  CardKind.debit => const [Color(0xFF1B4FD8), Color(0xFF0A1B3D)],
  CardKind.credit => const [Color(0xFF0E7490), Color(0xFF0A1B3D)],
  CardKind.virtual => const [Color(0xFF5B3FD0), Color(0xFF0A1B3D)],
};

String cardKindLabel(CardKind kind) => switch (kind) {
  CardKind.debit => 'Debit',
  CardKind.credit => 'Credit',
  CardKind.virtual => 'Virtual',
};

ColorFilter _saturation(double s) => ColorFilter.matrix([
  0.2126 + 0.7874 * s, 0.7152 - 0.7152 * s, 0.0722 - 0.0722 * s, 0, 0,
  0.2126 - 0.2126 * s, 0.7152 + 0.2848 * s, 0.0722 - 0.0722 * s, 0, 0,
  0.2126 - 0.2126 * s, 0.7152 - 0.7152 * s, 0.0722 + 0.9278 * s, 0, 0,
  0, 0, 0, 1, 0,
]);

/// Bank card face. Only the last four digits are ever shown. When frozen the
/// card desaturates, darkens, frosts over and shows a lock.
class BankCardWidget extends StatelessWidget {
  const BankCardWidget({super.key, required this.card});
  final BankCard card;

  @override
  Widget build(BuildContext context) {
    final frozen = card.frozen || card.blocked || !card.usable;
    return Semantics(
      label: '${cardKindLabel(card.kind)} card ending ${card.last4}${card.blocked ? ', blocked' : (!card.usable ? ', not active yet' : (card.frozen ? ', frozen' : ''))}',
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: 1.586,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: frozen ? 1 : 0),
            duration: AppAnimations.scaled(context, AppAnimations.slow),
            curve: AppAnimations.standard,
            builder: (context, freeze, _) => DecoratedBox(
              decoration: BoxDecoration(borderRadius: AppRadius.xlAll, boxShadow: AppShadows.elevated),
              child: ClipRRect(
                borderRadius: AppRadius.xlAll,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColorFiltered(
                      colorFilter: _saturation(1 - freeze * 0.9),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _gradientFor(card.kind),
                          ),
                        ),
                        // The card is artwork with a fixed shape, so its text scales only a little.
                        child: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.1, child: _Face(card: card)),
                      ),
                    ),
                    // Glass sheen.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.center,
                          colors: [Colors.white.withAlpha(46), Colors.white.withAlpha(0)],
                        ),
                      ),
                    ),
                    if (freeze > 0)
                      Opacity(
                        opacity: freeze,
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 3 * freeze, sigmaY: 3 * freeze),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Colors.white.withAlpha(70), Colors.black.withAlpha(110)],
                              ),
                            ),
                            child: Center(child: Icon(card.usable ? Icons.lock_rounded : Icons.hourglass_top_rounded, size: 44, color: _cardText)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.card});
  final BankCard card;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const BankMark(size: 26, color: _cardText),
            const SizedBox(width: 8),
            const Text(
              AppStrings.bankName,
              style: TextStyle(color: _cardText, fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const Spacer(),
            Text(
              cardKindLabel(card.kind).toUpperCase(),
              style: const TextStyle(color: _cardText, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2),
            ),
          ],
        ),
        const Spacer(),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '••••  ••••  ••••  ${card.last4}',
            style: AppTypography.title.copyWith(color: _cardText, fontSize: 21, letterSpacing: 1.5),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CARDHOLDER', style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 9, letterSpacing: 1)),
                  Text(
                    card.holder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _cardText, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('EXPIRES', style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 9, letterSpacing: 1)),
                Text(
                  card.expiry,
                  style: const TextStyle(color: _cardText, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(width: 14),
            _NetworkMark(card.network),
          ],
        ),
      ],
    ),
  );
}

/// Generic network placeholder (not the licensed brand marks).
class _NetworkMark extends StatelessWidget {
  const _NetworkMark(this.network);
  final CardNetwork network;

  @override
  Widget build(BuildContext context) => network == CardNetwork.visa
      ? const Text(
          'VISA',
          style: TextStyle(color: _cardText, fontSize: 18, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic),
        )
      : SizedBox(
          width: 38,
          height: 24,
          child: Stack(
            children: [
              Positioned(left: 0, child: _dot(const Color(0xCCEB5757))),
              Positioned(right: 0, child: _dot(const Color(0xCCF2C94C))),
            ],
          ),
        );

  Widget _dot(Color color) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}
