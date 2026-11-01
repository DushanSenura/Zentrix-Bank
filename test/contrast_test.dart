import 'dart:math';
import 'package:bank_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x relative luminance and contrast ratio, computed from the design tokens themselves.
/// Screenshot-based checks are unreliable over blurred glass, so the palette is verified at the source.
double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

/// Paints [top] over [bottom].
Color over(Color top, Color bottom) => Color.alphaBlend(top, bottom);

void main() {
  for (final (name, c) in [('light', AppColors.light), ('dark', AppColors.dark)]) {
    group('$name palette', () {
      // Everything text can sit on: the page, plain surfaces, and glass over every background stop.
      final grounds = <String, Color>{
        'background': c.background,
        'surface': c.surface,
        for (var i = 0; i < c.backgroundGradient.length; i++) ...{
          'gradient $i': c.backgroundGradient[i],
          'glass over gradient $i': over(c.glassFill, c.backgroundGradient[i]),
          'input over gradient $i': over(c.inputFill, c.backgroundGradient[i]),
        },
      };

      final text = <String, Color>{
        'textPrimary': c.textPrimary,
        'textSecondary': c.textSecondary,
        'accent': c.accent,
        'success': c.success,
        'warning': c.warning,
        'error': c.error,
      };

      for (final t in text.entries) {
        test('${t.key} is readable (≥ 4.5:1) on every ground', () {
          final bad = [
            for (final g in grounds.entries)
              if (contrast(t.value, g.value) < 4.5) '${g.key}: ${contrast(t.value, g.value).toStringAsFixed(2)}',
          ];
          expect(bad, isEmpty, reason: '${t.key} is too faint on: ${bad.join(', ')}');
        });
      }

      test('button label (onPrimary) is readable on the primary colour', () {
        expect(contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
      });

      test('the glass border and divider are not relied on to convey meaning alone', () {
        // Non-text UI parts need 3:1 under WCAG 1.4.11; borders here are decorative, so only the
        // focus/selection colours (accent) must reach it.
        for (final g in grounds.values) {
          expect(contrast(c.accent, g), greaterThanOrEqualTo(3));
        }
      });
    });
  }
}
