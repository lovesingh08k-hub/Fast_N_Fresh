import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Local system notifications for newly-arrived QR orders.
///
/// OrdersScreen uses this as the reliable foreground/background-while-alive
/// fallback. Firebase Cloud Messaging is wired separately for delivery when
/// the app is fully closed; that path requires Firebase project credentials.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const String _channelId = 'new_orders';
  static const String _channelName = 'New Orders';
  static const String _channelDescription =
      'Alerts when a new QR order arrives.';

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      playSound: true,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// Requests the OS notification permission (Android 13+ / iOS). Safe to
  /// call more than once -- the OS only prompts the user the first time.
  Future<void> requestPermission() async {
    await Permission.notification.request();

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> showNewOrderNotification({required int count, String? bodyOverride}) async {
    // Be defensive: notifications can be requested from the QR-order poll
    // before the UI shell has finished initializing on a cold start.
    if (!_initialized) {
      try {
        await init();
      } catch (_) {
        return;
      }
    }
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final title =
        count == 1 ? 'New order received' : '$count new orders received';
    final body = bodyOverride ?? (count == 1
        ? 'A new QR order just came in.'
        : '$count new QR orders just came in.');

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }
}
