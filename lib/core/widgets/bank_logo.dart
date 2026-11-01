import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../theme/app_typography.dart';

/// The Zentrix mark: the supplied logo artwork (assets/brand/bank_logo.png, derived from assets/icon/bank logo.png).
/// Pass [color] to draw it as a single-colour silhouette where the full-colour logo would disappear into its background
/// (for example on the blue card face).
class BankMark extends StatelessWidget {
  const BankMark({super.key, this.size = 40, this.color});
  final double size;
  final Color? color;

  static const asset = 'assets/brand/bank_logo.png';

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        color: color,
        colorBlendMode: color == null ? null : BlendMode.srcIn,
        // A missing or corrupt asset must never break a screen.
        errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
      ),
    ),
  );
}

class BankLogo extends StatelessWidget {
  const BankLogo({super.key, this.size = 36, this.showName = true});
  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) => Semantics(
    label: AppStrings.bankName,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BankMark(size: size),
          if (showName) ...[
            SizedBox(width: size * 0.35),
            ExcludeSemantics(
              child: Text(
                AppStrings.bankName,
                style: AppTypography.h2.copyWith(fontSize: size * 0.72, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
