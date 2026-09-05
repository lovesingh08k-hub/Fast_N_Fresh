/// Central place to configure the backend API URL.
///
/// IMPORTANT:
/// Never ship localhost, 127.0.0.1, or a local PC IP in a production APK.
///
/// Production APK:
///   flutter build apk --release \
///     --dart-define=API_BASE_URL=https://YOUR-RENDER-URL.onrender.com/api
///
/// Example:
///   flutter build apk --release \
///     --dart-define=API_BASE_URL=https://fast-n-fresh-api.onrender.com/api
///
/// Android Emulator + local backend:
///   http://10.0.2.2:5000/api
///
/// Physical phone + local backend on same Wi-Fi:
///   http://10.169.90.212:5000/api

class ApiConfig {
  ApiConfig._();

  /// Backend API URL.
  ///
  /// IMPORTANT:
  /// The production APK should always be built with:
  ///
  /// --dart-define=API_BASE_URL=https://YOUR-RENDER-URL.onrender.com/api
  ///
  /// The default is the verified production Render API so a release build
  /// remains usable even when the build command omits --dart-define.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://fast-n-fresh-api.onrender.com/api',
  );

  /// Connection timeout.
  static const Duration connectTimeout = Duration(seconds: 20);

  /// Request upload timeout.
  static const Duration sendTimeout = Duration(seconds: 20);

  /// Server response timeout. Long enough for a Render cold start.
  static const Duration receiveTimeout = Duration(seconds: 45);

  /// Returns the API root without the trailing `/api`.
  ///
  /// Example:
  /// https://example.onrender.com/api
  /// becomes:
  /// https://example.onrender.com
  static String get assetHost {
    if (baseUrl.endsWith('/api')) {
      return baseUrl.substring(0, baseUrl.length - 4);
    }

    return baseUrl;
  }

  /// Converts a relative asset path into a complete URL.
  ///
  /// Example:
  /// /uploads/products/example.jpg
  ///
  /// becomes:
  /// https://example.onrender.com/uploads/products/example.jpg
  static String resolveAssetUrl(String relativeOrAbsolute) {
    if (relativeOrAbsolute.isEmpty) {
      return relativeOrAbsolute;
    }

    if (relativeOrAbsolute.startsWith('http://') ||
        relativeOrAbsolute.startsWith('https://')) {
      return relativeOrAbsolute;
    }

    return '$assetHost$relativeOrAbsolute';
  }
}