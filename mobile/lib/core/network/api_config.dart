
/// Central place to configure the backend API URL.
///
/// IMPORTANT:
/// Never ship localhost, 127.0.0.1, or a local PC IP in a production APK.
///
/// Production APK:
///   flutter build apk --release --dart-define=API_BASE_URL=https://fast-n-fresh-cafe-api.onrender.com/api
///
/// Current Fast N Fresh production backend:
///   https://fast-n-fresh-cafe-api.onrender.com/api
///
/// Android Emulator + local backend:
///   http://10.0.2.2:5000/api
///
/// Physical phone + local backend on the same Wi-Fi:
///   http://10.169.90.212:5000/api
library;

import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  ApiConfig._();

  /// Backend API URL.
  ///
  /// You can override this default at build time using:
  ///
  /// --dart-define=API_BASE_URL=https://fast-n-fresh-cafe-api.onrender.com/api
  ///
  /// The default is the production Render backend. The web app is served
  /// by the backend itself (at /app/), so by default it calls the API on
  /// the same host it was loaded from -- same-origin, no CORS needed.
  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    if (kIsWeb) return '${Uri.base.origin}/api';
    return 'https://fast-n-fresh-cafe-api.onrender.com/api';
  }

  static const String _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Connection timeout.
  static const Duration connectTimeout = Duration(seconds: 20);

  /// Request upload timeout.
  static const Duration sendTimeout = Duration(seconds: 20);

  /// Server response timeout.
  ///
  /// Render Free services may need additional time during a cold start.
  static const Duration receiveTimeout = Duration(seconds: 45);

  /// Returns the API host without the trailing `/api`.
  ///
  /// Example:
  /// https://example.com/api
  /// becomes:
  /// https://example.com
  static String get assetHost {
    final url = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');

    if (url.endsWith('/api')) {
      return url.substring(0, url.length - 4);
    }

    return url;
  }

  /// Converts a relative asset path into a complete URL.
  ///
  /// Example:
  /// /uploads/products/example.jpg
  ///
  /// becomes:
  /// https://example.com/uploads/products/example.jpg
  static String resolveAssetUrl(String relativeOrAbsolute) {
    final path = relativeOrAbsolute.trim();

    if (path.isEmpty) {
      return path;
    }

    if (path.startsWith('https://') || path.startsWith('http://')) {
      return path;
    }

    final normalizedPath = path.startsWith('/') ? path : '/$path';

    return '$assetHost$normalizedPath';
  }
}
