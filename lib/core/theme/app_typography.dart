import 'package:flutter/material.dart';

/// Type scale. Colour is applied by the theme, not hard-coded here.
class AppTypography {
  const AppTypography._();
  static const family = 'Manrope';

  static const display = TextStyle(fontSize: 36, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -1.2);
  static const h1 = TextStyle(fontSize: 30, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.9);
  static const h2 = TextStyle(fontSize: 24, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.5);
  static const h3 = TextStyle(fontSize: 20, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: -0.3);
  static const title = TextStyle(fontSize: 17, height: 1.3, fontWeight: FontWeight.w600);
  static const bodyLarge = TextStyle(fontSize: 16, height: 1.45, fontWeight: FontWeight.w500);
  static const body = TextStyle(fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w500);
  static const bodySmall = TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w500);
  static const caption = TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w500, letterSpacing: 0.1);
  static const button = TextStyle(fontSize: 16, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: 0.1);

  /// Dedicated style for money: tabular figures keep digits aligned.
  static const amount = TextStyle(
    fontSize: 36,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: -1,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const amountSmall = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static TextTheme textTheme(Color primary) => const TextTheme(
    displayLarge: display,
    headlineLarge: h1,
    headlineMedium: h2,
    headlineSmall: h3,
    titleLarge: title,
    titleMedium: title,
    bodyLarge: bodyLarge,
    bodyMedium: body,
    bodySmall: bodySmall,
    labelLarge: button,
    labelSmall: caption,
  ).apply(fontFamily: family, bodyColor: primary, displayColor: primary);
}
