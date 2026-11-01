import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// PIN lengths the app accepts. Longer is harder to guess; shorter is quicker to type.
const pinLengths = [4, 6];
const defaultPinLength = 6;

/// "4 digits / 6 digits" switch shown while a PIN is being created.
class PinLengthPicker extends StatelessWidget {
  const PinLengthPicker({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [for (final n in pinLengths) ButtonSegment(value: n, label: Text('$n digits'))],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
        const SizedBox(height: 6),
        Text(
          value == 4 ? 'Quicker to type. Easier to guess.' : 'Harder to guess. Recommended.',
          style: AppTypography.caption.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}
