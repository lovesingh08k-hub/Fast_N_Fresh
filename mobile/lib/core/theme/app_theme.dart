import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final primary = dark ? const Color(0xFF63C6A4) : const Color(0xFF176B52);
    final primaryLight = dark ? const Color(0xFF173A31) : const Color(0xFFE7F3EE);
    final background = dark ? const Color(0xFF101312) : const Color(0xFFF7F8F6);
    final surface = dark ? const Color(0xFF181C1A) : Colors.white;
    final surfaceElevated = dark ? const Color(0xFF202522) : Colors.white;
    final textPrimary = dark ? const Color(0xFFF1F4F2) : const Color(0xFF1C211F);
    final textSecondary = dark ? const Color(0xFFB3BCB8) : const Color(0xFF66706B);
    final textMuted = dark ? const Color(0xFF7F8A85) : const Color(0xFF929A96);
    final border = dark ? const Color(0xFF2A322E) : const Color(0xFFE1E5E2);
    final divider = dark ? const Color(0xFF252B28) : const Color(0xFFEAEEEB);

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
      fontFamily: GoogleFonts.inter().fontFamily,
    );

    final text = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      headlineSmall: GoogleFonts.inter(fontSize: 21, fontWeight: FontWeight.w700, color: textPrimary),
      titleLarge: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: textPrimary),
      titleMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
      bodyLarge: GoogleFonts.inter(fontSize: 15, color: textPrimary),
      bodyMedium: GoogleFonts.inter(fontSize: 13, color: textSecondary),
      labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
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
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: dark ? const Color(0xFF0D1814) : Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: AppColors.danger)),
        hintStyle: GoogleFonts.inter(color: textMuted, fontSize: 14),
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
          GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: background,
        selectedColor: primaryLight,
        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        side: BorderSide(color: border),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? surfaceElevated : textPrimary,
        contentTextStyle: GoogleFonts.inter(color: dark ? textPrimary : Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
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
