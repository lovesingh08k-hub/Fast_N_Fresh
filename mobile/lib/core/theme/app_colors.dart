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

  static Color get primary => _lerp(const Color(0xFF176B52), const Color(0xFF63C6A4));
  static Color get primaryDark => _lerp(const Color(0xFF0F5540), const Color(0xFF3FAE88));
  static Color get primaryLight => _lerp(const Color(0xFFE7F3EE), const Color(0xFF173A31));
  static Color get accent => _lerp(const Color(0xFFC98B36), const Color(0xFFE5B66A));
  static Color get background => _lerp(const Color(0xFFF7F8F6), const Color(0xFF101312));
  static Color get surface => _lerp(Colors.white, const Color(0xFF181C1A));
  static Color get surfaceElevated => _lerp(Colors.white, const Color(0xFF202522));
  static Color get textPrimary => _lerp(const Color(0xFF1C211F), const Color(0xFFF1F4F2));
  static Color get textSecondary => _lerp(const Color(0xFF66706B), const Color(0xFFB3BCB8));
  static Color get textMuted => _lerp(const Color(0xFF929A96), const Color(0xFF7F8A85));
  static Color get border => _lerp(const Color(0xFFE1E5E2), const Color(0xFF2A322E));
  static Color get divider => _lerp(const Color(0xFFEAEEEB), const Color(0xFF252B28));

  static Color success = const Color(0xFF4FA879);
  static Color danger = const Color(0xFFC85C5C);
  static Color warning = const Color(0xFFD6A04D);
  static Color info = const Color(0xFF628EC5);
  static Color cash = const Color(0xFF4FA879);
  static Color upi = const Color(0xFF628EC5);
  static Color credit = const Color(0xFF9A7CB8);

  static Color get cardShadow => _darkProgress > .01 ? Colors.transparent : const Color(0x12000000);
}
