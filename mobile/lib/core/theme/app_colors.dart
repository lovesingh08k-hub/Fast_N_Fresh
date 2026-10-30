import 'package:flutter/material.dart';

/// Brand palette used by legacy widgets that do not directly read
/// Theme.of(context). The palette is interpolated during theme changes so
/// those widgets animate together with Material's ThemeData transition.
///
/// [progress] is a real ValueNotifier (not just a bare static field) so any
/// screen can wrap itself in `AnimatedBuilder(animation: AppColors.progress,
/// ...)` and be guaranteed to repaint on every tick of the theme animation.
/// Without that, a screen that isn't otherwise rebuilding while the palette
/// is mid-transition can get "stuck" showing whatever blended light/dark
/// color happened to be active on its last rebuild — which can wash out
/// contrast between background/surface/border/text until something else
/// (e.g. a cart or catalog update) happens to trigger a fresh rebuild.
class AppColors {
  AppColors._();

  static final ValueNotifier<double> progress = ValueNotifier<double>(0);

  static double get _darkProgress => progress.value;

  static void setDarkMode(bool value) => progress.value = value ? 1 : 0;
  static void setDarkProgress(double value) =>
      progress.value = value.clamp(0.0, 1.0).toDouble();
  static bool get isDark => _darkProgress >= .5;
  static Color _lerp(Color light, Color dark) => Color.lerp(light, dark, _darkProgress)!;

  // Brand: warm saffron-coral (Indian restaurant feel) on soft grey, white
  // cards with gentle shadows. Keep in sync with AppTheme._build.
  static Color get primary => _lerp(const Color(0xFFF2643D), const Color(0xFFFF8A65));
  static Color get primaryDark => _lerp(const Color(0xFFD9482A), const Color(0xFFFF7043));
  static Color get primaryLight => _lerp(const Color(0xFFFFEDE7), const Color(0xFF3A2219));
  static Color get accent => _lerp(const Color(0xFFF5A524), const Color(0xFFFFC266));
  static Color get background => _lerp(const Color(0xFFF4F4F6), const Color(0xFF0F1012));
  static Color get surface => _lerp(Colors.white, const Color(0xFF1A1B1F));
  static Color get surfaceElevated => _lerp(Colors.white, const Color(0xFF232429));
  static Color get textPrimary => _lerp(const Color(0xFF1B1D22), const Color(0xFFF3F3F5));
  static Color get textSecondary => _lerp(const Color(0xFF6B6F7A), const Color(0xFFB4B6BE));
  static Color get textMuted => _lerp(const Color(0xFF9CA0AA), const Color(0xFF7D808A));
  static Color get border => _lerp(const Color(0xFFEBEBEF), const Color(0xFF2C2D33));
  static Color get divider => _lerp(const Color(0xFFF0F0F3), const Color(0xFF26272C));

  static Color success = const Color(0xFF1FA463);
  static Color danger = const Color(0xFFE5484D);
  static Color warning = const Color(0xFFF59E0B);
  static Color info = const Color(0xFF3B82F6);
  static Color cash = const Color(0xFF1FA463);
  static Color upi = const Color(0xFF6366F1);
  static Color credit = const Color(0xFFA855F7);

  /// Indian food marks: green = veg, red = non-veg, amber = egg.
  static const Color veg = Color(0xFF16A34A);
  static const Color nonVeg = Color(0xFFDC2626);
  static const Color egg = Color(0xFFF59E0B);

  static Color get cardShadow => _darkProgress > .01 ? Colors.transparent : const Color(0x0F1B1D22);
}
