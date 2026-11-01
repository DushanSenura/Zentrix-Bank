import 'package:flutter/material.dart';

/// Semantic colour tokens. Widgets read these through `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.backgroundGradient,
    required this.surface,
    required this.glassFill,
    required this.glassBorder,
    required this.glassHighlight,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.success,
    required this.warning,
    required this.error,
    required this.onPrimary,
    required this.inputFill,
    required this.divider,
  });

  final Color background, surface, glassFill, glassBorder, glassHighlight;
  final List<Color> backgroundGradient;
  final Color textPrimary, textSecondary;
  final Color primary, secondary, accent;
  final Color success, warning, error, onPrimary;
  final Color inputFill, divider;

  static const _navy = Color(0xFF0A1B3D);
  static const _electric = Color(0xFF2F6BFF);
  static const _aqua = Color(0xFF22D3EE);

  static const dark = AppColors(
    background: Color(0xFF050E24),
    backgroundGradient: [Color(0xFF0B1F4B), Color(0xFF071634), Color(0xFF040B1D)],
    surface: Color(0xFF0E1F46),
    glassFill: Color(0x1FFFFFFF),
    glassBorder: Color(0x38FFFFFF),
    glassHighlight: Color(0x40FFFFFF),
    textPrimary: Color(0xFFF4F7FF),
    textSecondary: Color(0xFFA9B8DC),
    primary: Color(0xFF2A62F0),
    secondary: Color(0xFF5B8DFF),
    accent: _aqua,
    success: Color(0xFF3DDC97),
    warning: Color(0xFFFFB84D),
    error: Color(0xFFFF9494),
    onPrimary: Colors.white,
    inputFill: Color(0x26FFFFFF),
    divider: Color(0x26FFFFFF),
  );

  static const light = AppColors(
    background: Color(0xFFF2F5FB),
    backgroundGradient: [Color(0xFFE4ECFF), Color(0xFFF2F5FB), Color(0xFFEAF6FB)],
    surface: Colors.white,
    glassFill: Color(0xB3FFFFFF),
    glassBorder: Color(0xCCFFFFFF),
    glassHighlight: Color(0xFFFFFFFF),
    textPrimary: _navy,
    textSecondary: Color(0xFF52607F),
    primary: Color(0xFF1F55E0),
    secondary: _electric,
    accent: Color(0xFF0C6B86),
    success: Color(0xFF0F7352),
    warning: Color(0xFFA04A07),
    error: Color(0xFFC62828),
    onPrimary: Colors.white,
    inputFill: Color(0xCCFFFFFF),
    divider: Color(0x1A0A1B3D),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      backgroundGradient: [
        for (var i = 0; i < backgroundGradient.length; i++)
          l(backgroundGradient[i], other.backgroundGradient[i]),
      ],
      surface: l(surface, other.surface),
      glassFill: l(glassFill, other.glassFill),
      glassBorder: l(glassBorder, other.glassBorder),
      glassHighlight: l(glassHighlight, other.glassHighlight),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      primary: l(primary, other.primary),
      secondary: l(secondary, other.secondary),
      accent: l(accent, other.accent),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      error: l(error, other.error),
      onPrimary: l(onPrimary, other.onPrimary),
      inputFill: l(inputFill, other.inputFill),
      divider: l(divider, other.divider),
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
