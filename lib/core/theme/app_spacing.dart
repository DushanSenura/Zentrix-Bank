class AppSpacing {
  const AppSpacing._();
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Horizontal gutter for every screen.
  static const double gutter = 20;

  /// Minimum accessible touch target.
  static const double touchTarget = 48;

  /// Space reserved so scrolling content clears the floating nav bar.
  static const double navClearance = 112;

  /// Widest content column; keeps layouts tidy on tablets.
  static const double maxContentWidth = 520;
}
