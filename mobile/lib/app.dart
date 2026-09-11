import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/connectivity_banner.dart';
import 'package:circular_theme_reveal/circular_theme_reveal.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main/main_shell.dart';
import 'core/theme/app_colors.dart';

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
      // The circular reveal package owns the visual transition. Keeping
      // MaterialApp's own theme tween at zero prevents two animations from
      // competing underneath the reveal snapshot.
      themeAnimationDuration: Duration.zero,
      themeAnimationCurve: Curves.linear,
      builder: (context, child) => CircularThemeRevealOverlay(
        child: ConnectivityBanner(child: child ?? const SizedBox.shrink()),
      ),
      home: const _RootRouter(),
    );
  }
}

class _RootRouter extends StatefulWidget {
  const _RootRouter({super.key});

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  bool _minimumSplashElapsed = false;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    // Keep the branded green startup visible long enough to feel intentional
    // rather than flashing for a few frames on fast devices. This is a UI
    // minimum only; auth/network work continues independently.
    _splashTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _minimumSplashElapsed = true);
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!_minimumSplashElapsed || auth.status == AuthStatus.unknown) {
      return const _SplashScreen();
    }

    switch (auth.status) {
      case AuthStatus.authenticated:
        return const MainShell();
      case AuthStatus.unauthenticated:
        return const LoginScreen();
      case AuthStatus.unknown:
        return const _SplashScreen();
    }
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen({super.key});

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
    _timer = Timer(const Duration(seconds: 4), () {
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
      backgroundColor: AppColors.primaryDark,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: .88, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 28, offset: Offset(0, 12))],
                ),
                child: Image.asset('assets/images/app_icon.png', width: 72, height: 72),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'FAST N FRESH',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.8),
            ),
            const SizedBox(height: 6),
            const Text(
              'CAFE • POS & MANAGEMENT',
              style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5),
            ),
            const SizedBox(height: 34),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            ),
            if (_showSlowMessage) ...[
              SizedBox(height: 16),
              Text(
                'Connecting securely…',
                style: const TextStyle(
                  color: Color(0xB3FFFFFF),
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
