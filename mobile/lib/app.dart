import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/connectivity_banner.dart';
import 'core/widgets/latest_snackbar_messenger.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/licence_blocked_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main/main_shell.dart';
import 'core/theme/app_colors.dart';

class PwpPosApp extends StatelessWidget {
  const PwpPosApp({super.key});

  /// App-wide navigator key so a new-order alert can pop up a dialog on top
  /// of whatever screen/tab is currently visible (e.g. POS, Dashboard),
  /// not just when the Orders tab happens to be the active one.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'PWP POS — Personalize Web Page',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: context.watch<ThemeProvider>().themeMode,
      // Theme changes are instant so MaterialApp and the AppColors palette
      // used by older widgets always switch together.
      themeAnimationDuration: Duration.zero,
      themeAnimationCurve: Curves.linear,
      builder: (context, child) => _ThemeRefresh(
        child: LatestSnackBarMessenger(
          child: ConnectivityBanner(child: child ?? const SizedBox.shrink()),
        ),
      ),
      home: const _RootRouter(),
    );
  }
}

/// Many screens read the static [AppColors] palette instead of
/// Theme.of(context), so Flutter doesn't know they depend on the theme:
/// const widgets and screens kept alive off-screen (other tabs, routes
/// below the current one) kept the old colors until something else rebuilt
/// them. On every Light/Dark change, mark the whole subtree dirty so the
/// next frame repaints everything in the new palette at once. State (cart,
/// navigation stack, text fields) is preserved.
class _ThemeRefresh extends StatefulWidget {
  final Widget child;

  const _ThemeRefresh({required this.child});

  @override
  State<_ThemeRefresh> createState() => _ThemeRefreshState();
}

class _ThemeRefreshState extends State<_ThemeRefresh> {
  late final ThemeProvider _theme;
  late AppThemeMode _mode;

  @override
  void initState() {
    super.initState();
    _theme = context.read<ThemeProvider>();
    _mode = _theme.mode;
    _theme.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (_theme.mode == _mode || !mounted) return;
    _mode = _theme.mode;

    void markDirty(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markDirty);
    }

    (context as Element).visitChildren(markDirty);
  }

  @override
  void dispose() {
    _theme.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _RootRouter extends StatefulWidget {
  const _RootRouter();

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
        // A new key per user/outlet rebuilds every tab from scratch, so no
        // screen keeps showing the previous outlet's data.
        return MainShell(key: ValueKey(auth.sessionKey));
      case AuthStatus.licenceInactive:
        return const LicenceBlockedScreen();
      case AuthStatus.unauthenticated:
        return const LoginScreen();
      case AuthStatus.unknown:
        return const _SplashScreen();
    }
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

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
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              // The icon already has its own rounded dark tile, so show it
              // directly rather than inside a second white box.
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 28,
                        offset: Offset(0, 12))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Image.asset('assets/images/app_icon.png',
                      width: 104, height: 104),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'PWP POS',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8),
            ),
            const SizedBox(height: 6),
            const Text(
              'PERSONALIZE WEB PAGE • POS',
              style: TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5),
            ),
            const SizedBox(height: 34),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white),
            ),
            if (_showSlowMessage) ...[
              const SizedBox(height: 16),
              const Text(
                'Connecting securely…',
                style: TextStyle(
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
