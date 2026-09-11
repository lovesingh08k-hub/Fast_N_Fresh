import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_colors.dart';

enum AppThemeMode { system, light, dark }

class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const _key = 'theme_mode';
  AppThemeMode _mode = AppThemeMode.system;

  ThemeProvider() { WidgetsBinding.instance.addObserver(this); }

  @override
  void didChangePlatformBrightness() {
    if (_mode == AppThemeMode.system) {
      AppColors.setDarkMode(isDark);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  AppThemeMode get mode => _mode;
  bool get isDark => _mode == AppThemeMode.dark ||
      (_mode == AppThemeMode.system &&
          WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
  bool isDarkForMode(AppThemeMode mode) => switch (mode) {
        AppThemeMode.dark => true,
        AppThemeMode.light => false,
        AppThemeMode.system =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark,
      };

  ThemeMode get themeMode => switch (_mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    _mode = switch (value) {
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      _ => AppThemeMode.system,
    };
    AppColors.setDarkMode(isDark);
    notifyListeners();
  }

  Future<void> setMode(AppThemeMode value) async {
    if (_mode == value) return;
    _mode = value;
    // Keep legacy AppColors-based widgets synchronized with the selected
    // endpoint. The circular reveal handles the visual transition.
    AppColors.setDarkMode(value == AppThemeMode.dark ||
        (value == AppThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark));
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, switch (value) {
      AppThemeMode.system => 'system',
      AppThemeMode.light => 'light',
      AppThemeMode.dark => 'dark',
    });
  }

  // Backward compatibility for older screens/callers.
  Future<void> setDarkMode(bool value) => setMode(value ? AppThemeMode.dark : AppThemeMode.light);
}
