import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/connectivity_banner.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main/main_shell.dart';
import 'core/theme/app_colors.dart';
import 'core/widgets/brand_lockup.dart';

class FastNFreshApp extends StatelessWidget {
  const FastNFreshApp({super.key});

  /// App-wide navigator key so a new-order alert can pop up a dialog on top
  /// of whatever screen/tab is currently visible (e.g. POS, Dashboard),
  /// not just when the Orders tab happens to be the active one.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Fast N Fresh Cafe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: context.watch<ThemeProvider>().themeMode,
      home: ConnectivityBanner(child: _RootRouter()),
    );
  }
}

class _RootRouter extends StatelessWidget {
  _RootRouter();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    switch (auth.status) {
      case AuthStatus.unknown:
        return _SplashScreen();
      case AuthStatus.authenticated:
        return MainShell();
      case AuthStatus.unauthenticated:
        return LoginScreen();
    }
  }
}

class _SplashScreen extends StatefulWidget {
  _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  bool _showSlowMessage = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Purely cosmetic reassurance for the user if startup is slow (e.g. a
    // Render cold start on the background session check) — this does NOT
    // change any state-machine behavior. AuthProvider.restoreSession()
    // itself is bounded and will always resolve to authenticated or
    // unauthenticated well before this.
    _timer = Timer(Duration(seconds: 5), () {
      if (mounted) setState(() => _showSlowMessage = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandLockup(),
            SizedBox(height: 12),
            GooglixLabsMark(label: 'DEVELOPED BY GOOGLIXLABS'),
            SizedBox(height: 28),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            if (_showSlowMessage) ...[
              SizedBox(height: 16),
              Text(
                'Connecting securely…',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
