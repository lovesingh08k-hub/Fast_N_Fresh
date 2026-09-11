import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/network/dio_client.dart';
import 'notification_service.dart';

/// Background/terminated-app FCM message handler.
///
/// Must be a TOP-LEVEL (or static) function -- Flutter spins this up in
/// its own isolate when a push arrives while the app is not running, so
/// it can't be a method on an instance. This is what actually makes
/// "still get a notification even when I'm not in the app" work: the
/// existing NotificationService/poll-based alerts only ever fire while
/// the app process is alive.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No extra work needed here -- FCM shows the OS notification for a
  // message with a `notification` payload automatically, even in this
  // background isolate. This handler exists so `data`-only pushes could
  // be handled the same way in future; kept intentionally minimal.
}

/// Wires up Firebase Cloud Messaging so admin/manager/staff devices get a
/// real push notification for new orders even when the app is fully
/// closed, not just backgrounded.
///
/// ---------------------------------------------------------------------
/// ONE-TIME SETUP REQUIRED before this does anything (see also
/// backend/src/utils/push.js):
/// 1. Create a Firebase project, add this app, and run
///    `flutterfire configure` from the mobile/ directory (or manually
///    place google-services.json in mobile/android/app/ and
///    GoogleService-Info.plist in mobile/ios/Runner/).
/// 2. `flutter pub get` (firebase_core/firebase_messaging are already in
///    pubspec.yaml).
/// 3. Configure the backend's push credentials -- see the header comment
///    in backend/src/utils/push.js.
///
/// Every method below fails silently (try/catch, no rethrow) if Firebase
/// hasn't been configured yet, so the rest of the app keeps working
/// exactly as before either way.
/// ---------------------------------------------------------------------
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  bool _initialized = false;
  String? _lastRegisteredToken;

  /// Call once, early in app startup (before runApp), after
  /// WidgetsFlutterBinding.ensureInitialized().
  Future<void> init() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // A push that arrives while the app IS in the foreground doesn't
      // show a system tray notification on its own -- surface it the
      // same way the existing in-app poll does.
      FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null) return;
        NotificationService.instance.showNewOrderNotification(count: 1);
      });

      _initialized = true;
    } catch (err) {
      // Firebase not configured yet (no google-services.json etc.) --
      // this is expected until the setup steps above are done.
      _initialized = false;
    }
  }

  /// Requests notification permission (iOS needs this explicitly;
  /// Android 13+ permission is requested separately via
  /// NotificationService.requestPermission, already called in MainShell),
  /// then fetches this device's FCM token and registers it with the
  /// backend so it can be pushed to.
  Future<void> registerDeviceToken() async {
    if (!_initialized) return;

    try {
      final messaging = FirebaseMessaging.instance;

      if (Platform.isIOS || Platform.isMacOS) {
        await messaging.requestPermission(alert: true, badge: true, sound: true);
      }

      final token = await messaging.getToken();
      if (token == null || token == _lastRegisteredToken) return;

      await DioClient.instance.dio.post('/auth/push-token', data: {'token': token});
      _lastRegisteredToken = token;

      // FCM can rotate the token later (app reinstall, storage clear,
      // etc.) -- keep the backend in sync when that happens.
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        try {
          await DioClient.instance.dio.post('/auth/push-token', data: {'token': newToken});
          _lastRegisteredToken = newToken;
        } catch (_) {
          // Best-effort; will retry on next app start.
        }
      });
    } catch (_) {
      // Best-effort -- registering a push token should never block or
      // crash the sign-in flow.
    }
  }

  /// Call on logout so a signed-out device stops receiving pushes meant
  /// for whoever signs in next on that phone.
  Future<void> unregisterDeviceToken() async {
    if (!_initialized || _lastRegisteredToken == null) return;

    try {
      await DioClient.instance.dio.post(
        '/auth/push-token/unregister',
        data: {'token': _lastRegisteredToken},
      );
    } catch (_) {
      // Best-effort.
    } finally {
      _lastRegisteredToken = null;
    }
  }
}
