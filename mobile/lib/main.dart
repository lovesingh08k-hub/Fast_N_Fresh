import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/network/dio_client.dart';
import 'core/network/network_status.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/catalog_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/tab_refresh_bus.dart';
import 'providers/theme_provider.dart';
import 'services/push_notification_service.dart';
import 'services/notification_service.dart';
import 'core/theme/app_colors.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Flutter's default ErrorWidget is a plain grey box with no text in
  // release builds — on a dark screen that is functionally invisible, so a
  // build-time crash anywhere in the tree looks exactly like "blank
  // screen, nothing renders" with zero clue why. Replace it with something
  // that is always readable regardless of theme, so any future crash shows
  // its message on-screen instead of silently disappearing.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Container(
      color: AppColors.primaryDark,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Text(
        'Something went wrong displaying this screen.\n\n'
        '${details.exceptionAsString()}',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.danger, fontSize: 12),
      ),
    );
  };

  final authProvider = AuthProvider();
  final themeProvider = ThemeProvider();
  // Theme is read from local storage only (fast, synchronous-ish) and is
  // needed for the very first frame, so it's the one thing still awaited
  // here. Everything else below was previously awaited before runApp(),
  // which meant the splash screen sat frozen through a Firebase network
  // round-trip and a blocking OS permission dialog before the user ever
  // saw the app. None of that is needed to paint the first frame, so it
  // now runs in the background after runApp() (see _AppBootstrapperState
  // below) instead of delaying startup.
  await themeProvider.load();

  DioClient.instance.onUnauthorized = authProvider.forceLogout;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => CatalogProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => TabRefreshBus()),
        ChangeNotifierProvider.value(value: NetworkStatus.instance),
      ],
      child: const _AppBootstrapper(),
    ),
  );
}

class _AppBootstrapper extends StatefulWidget {
  const _AppBootstrapper();

  @override
  State<_AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<_AppBootstrapper>
    with WidgetsBindingObserver {
  late final AuthProvider _authProvider;

  AppLifecycleState? _lastLifecycleState;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _authProvider = context.read<AuthProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authProvider.restoreSession();
      // Best-effort, non-blocking: notification setup (including the
      // Android 13+ permission prompt and Firebase init/token fetch) now
      // happens after the app is already visible, so a slow network or a
      // user who sits on the permission dialog no longer delays startup.
      unawaited(_initNotifications());
    });
  }

  Future<void> _initNotifications() async {
    await PushNotificationService.instance.init();
    await NotificationService.instance.init();
    await NotificationService.instance.requestPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackgrounded =
        _lastLifecycleState == AppLifecycleState.paused ||
        _lastLifecycleState == AppLifecycleState.inactive ||
        _lastLifecycleState == AppLifecycleState.hidden;

    final returnedToForeground =
        state == AppLifecycleState.resumed && wasBackgrounded;

    _lastLifecycleState = state;

    if (returnedToForeground) {
      _authProvider.checkSessionOnResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const FastNFreshApp();
  }
}
