import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    // Same palette as AppColors (light / dark).
    final primary = dark ? const Color(0xFFFF8A65) : const Color(0xFFF2643D);
    final primaryLight = dark ? const Color(0xFF3A2219) : const Color(0xFFFFEDE7);
    final background = dark ? const Color(0xFF0F1012) : const Color(0xFFF4F4F6);
    final surface = dark ? const Color(0xFF1A1B1F) : Colors.white;
    final surfaceElevated = dark ? const Color(0xFF232429) : Colors.white;
    final textPrimary = dark ? const Color(0xFFF3F3F5) : const Color(0xFF1B1D22);
    final textSecondary = dark ? const Color(0xFFB4B6BE) : const Color(0xFF6B6F7A);
    final textMuted = dark ? const Color(0xFF7D808A) : const Color(0xFF9CA0AA);
    final border = dark ? const Color(0xFF2C2D33) : const Color(0xFFEBEBEF);
    final divider = dark ? const Color(0xFF26272C) : const Color(0xFFF0F0F3);
    // A shade darker than the page so fields stay visible on grey and white.
    final field = dark ? const Color(0xFF26272D) : const Color(0xFFEBEBF0);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        primary: primary,
        primaryContainer: primaryLight,
        surface: surface,
        error: AppColors.danger,
      ),
      scaffoldBackgroundColor: background,
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      // Compact density keeps list tiles, buttons and fields tight for a
      // minimal, information-dense POS.
      visualDensity: VisualDensity.compact,
    );

    final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).copyWith(
      headlineSmall: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: textPrimary),
      titleLarge: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary),
      titleMedium: GoogleFonts.plusJakartaSans(fontSize: 14.5, fontWeight: FontWeight.w700, color: textPrimary),
      bodyLarge: GoogleFonts.plusJakartaSans(fontSize: 15, color: textPrimary),
      bodyMedium: GoogleFonts.plusJakartaSans(fontSize: 13, color: textSecondary),
      labelLarge: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
    );

    // Keep one Flutter-SDK-compatible transition builder across platforms.
    // The Material fade/slide transition is smooth on Android and desktop
    // and avoids relying on Cupertino-only constructors that are absent in
    // some supported Flutter SDK versions.
    final pageTransitions = PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const _FastNFreshPageTransitionsBuilder(),
      },
    );

    return base.copyWith(
      textTheme: text,
      pageTransitionsTheme: pageTransitions,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 56,
        titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: primary,
          selectedForegroundColor: Colors.white,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : null),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        // Soft grey filled fields without a heavy outline.
        filled: true,
        fillColor: field,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: field)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: field)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.danger)),
        prefixIconColor: textMuted,
        hintStyle: GoogleFonts.plusJakartaSans(color: textMuted, fontSize: 14),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: dark ? 0 : 8,
        showUnselectedLabels: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primaryLight,
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        selectedColor: primaryLight,
        checkmarkColor: primary,
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        side: BorderSide(color: border),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? surfaceElevated : textPrimary,
        contentTextStyle: GoogleFonts.plusJakartaSans(color: dark ? textPrimary : Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        // Swipe left/right to dismiss, like native Android snackbars.
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);
}


class _FastNFreshPageTransitionsBuilder extends PageTransitionsBuilder {
  const _FastNFreshPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, .025),
      end: Offset.zero,
    ).animate(curved);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(position: slide, child: child),
    );
  }
}
