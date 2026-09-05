import 'package:flutter/material.dart';

/// Single source of truth for the app palette.
///
/// The palette is intentionally restrained: green is the brand/action color,
/// amber is used for attention states, and red is reserved for destructive or
/// genuine error states. The same semantic palette is switched for dark mode.
class AppColors {
  AppColors._();

  static bool _dark = false;

  static void setDarkMode(bool value) => _dark = value;
  static bool get isDark => _dark;

  static Color get primary => _dark ? Color(0xFF63C6A4) : Color(0xFF176B52);
  static Color get primaryDark => _dark ? Color(0xFF3FAE88) : Color(0xFF0F5540);
  static Color get primaryLight => _dark ? Color(0xFF173A31) : Color(0xFFE7F3EE);

  static Color get accent => _dark ? Color(0xFFE5B66A) : Color(0xFFC98B36);

  static Color get background => _dark ? Color(0xFF101312) : Color(0xFFF7F8F6);
  static Color get surface => _dark ? Color(0xFF181C1A) : Color(0xFFFFFFFF);
  static Color get surfaceElevated => _dark ? Color(0xFF202522) : Color(0xFFFFFFFF);

  static Color get textPrimary => _dark ? Color(0xFFF1F4F2) : Color(0xFF1C211F);
  static Color get textSecondary => _dark ? Color(0xFFB3BCB8) : Color(0xFF66706B);
  static Color get textMuted => _dark ? Color(0xFF7F8A85) : Color(0xFF929A96);

  static Color get border => _dark ? Color(0xFF2A322E) : Color(0xFFE1E5E2);
  static Color get divider => _dark ? Color(0xFF252B28) : Color(0xFFEAEEEB);

  static Color success = Color(0xFF4FA879);
  static Color danger = Color(0xFFC85C5C);
  static Color warning = Color(0xFFD6A04D);
  static Color info = Color(0xFF628EC5);

  // Payment methods use restrained semantic colors; CREDIT is deliberately
  // not red so normal payment history does not look like an error.
  static Color cash = Color(0xFF4FA879);
  static Color upi = Color(0xFF628EC5);
  static Color credit = Color(0xFF9A7CB8);

  static Color get cardShadow => _dark ? Colors.transparent : Color(0x12000000);
}
