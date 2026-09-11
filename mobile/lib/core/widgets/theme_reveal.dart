import 'package:circular_theme_reveal/circular_theme_reveal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';

/// Runs a Telegram-style circular reveal from the supplied widget/context and
/// changes the app theme exactly when the new theme is ready to be revealed.
///
/// If the target mode has the same effective brightness (for example System
/// while the device is already in Light), the mode is changed without an
/// unnecessary visual animation.
Future<void> changeThemeWithReveal(
  BuildContext context,
  AppThemeMode targetMode, {
  BuildContext? originContext,
}) async {
  final provider = context.read<ThemeProvider>();
  final currentDark = provider.isDark;
  final targetDark = provider.isDarkForMode(targetMode);
  final origin = originContext ?? context;

  if (provider.mode == targetMode) return;

  final overlay = CircularThemeRevealOverlay.of(context);
  if (overlay == null || currentDark == targetDark) {
    await provider.setMode(targetMode);
    return;
  }

  final center = CircularThemeRevealOverlay.getCenterFromContext(origin);

  await overlay.startTransition(
    center: center,
    // Package docs: reverse=true is used for dark -> light.
    reverse: currentDark && !targetDark,
    onThemeChange: () {
      // The provider update is intentionally performed inside the package's
      // transition callback so the snapshot remains visible while the new
      // ThemeData is applied underneath it.
      provider.setMode(targetMode);
    },
  );
}
