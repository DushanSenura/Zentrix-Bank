import 'package:flutter/material.dart';

/// Central motion tokens. Always go through [scaled] so reduced-motion
/// preferences are honoured.
class AppAnimations {
  const AppAnimations._();

  static const Duration micro = Duration(milliseconds: 120);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 450);
  static const Duration success = Duration(milliseconds: 700);
  static const Duration number = Duration(milliseconds: 800);

  /// Step between items of an entrance sequence.
  static const Duration stagger = Duration(milliseconds: 60);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve spring = Curves.easeOutBack;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Collapses motion to an instant change when the user prefers less motion.
  static Duration scaled(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}
