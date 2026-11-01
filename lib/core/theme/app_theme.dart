import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(AppColors.light, Brightness.light);
  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: c.primary, brightness: b).copyWith(
      primary: c.primary,
      secondary: c.accent,
      surface: c.surface,
      error: c.error,
      onSurface: c.textPrimary,
    );
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: AppRadius.mdAll,
      borderSide: BorderSide(color: color, width: width),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: c.surface,
      fontFamily: AppTypography.family,
      textTheme: AppTypography.textTheme(c.textPrimary),
      extensions: [c],
      dividerColor: c.divider,
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.inputFill,
        hintStyle: AppTypography.body.copyWith(color: c.textSecondary),
        labelStyle: AppTypography.body.copyWith(color: c.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border(c.glassBorder),
        enabledBorder: border(c.glassBorder),
        focusedBorder: border(c.accent, 1.6),
        errorBorder: border(c.error),
        focusedErrorBorder: border(c.error, 1.6),
      ),
    );
  }
}
