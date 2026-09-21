import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/dio_client.dart';

/// ============================================================
/// FAST N FRESH - APP UPDATE SERVICE
/// ============================================================
///
/// Update source:
/// GitHub Releases
///
/// Manifest:
/// https://github.com/lovesingh08k-hub/Fast_N_Fresh/releases/latest/download/manifest.json
///
/// Fallback:
/// Backend /public/app-update
///
/// The URL can still be overridden at build time with:
///
/// --dart-define=UPDATE_MANIFEST_URL=...
///
/// ============================================================

const String _releaseManifestUrl = String.fromEnvironment(
  'UPDATE_MANIFEST_URL',
  defaultValue:
      'https://github.com/lovesingh08k-hub/Fast_N_Fresh/releases/latest/download/manifest.json',
);

class AppUpdateInfo {
  final bool enabled;
  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String notes;
  final bool forceUpdate;

  const AppUpdateInfo({
    required this.enabled,
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.notes,
    required this.forceUpdate,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      enabled: json['enabled'] == true,
      version: json['version']?.toString().trim() ?? '',
      buildNumber: _parseInt(json['buildNumber']),
      downloadUrl: json['downloadUrl']?.toString().trim() ?? '',
      notes: json['notes']?.toString().trim() ?? '',
      forceUpdate: json['forceUpdate'] == true,
    );
  }

  static int _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool get isValid {
    return version.isNotEmpty &&
        buildNumber > 0 &&
        downloadUrl.isNotEmpty;
  }

  @override
  String toString() {
    return 'AppUpdateInfo('
        'enabled: $enabled, '
        'version: $version, '
        'buildNumber: $buildNumber, '
        'downloadUrl: $downloadUrl, '
        'forceUpdate: $forceUpdate'
        ')';
  }
}

class AppUpdateCheckResult {
  final PackageInfo current;
  final AppUpdateInfo? update;

  const AppUpdateCheckResult({
    required this.current,
    this.update,
  });

  int get currentBuildNumber {
    return int.tryParse(current.buildNumber) ?? 0;
  }

  bool get hasUpdate {
    final availableUpdate = update;

    if (availableUpdate == null) {
      return false;
    }

    if (!availableUpdate.enabled) {
      return false;
    }

    if (!availableUpdate.isValid) {
      return false;
    }

    return availableUpdate.buildNumber > currentBuildNumber;
  }

  bool get isForceUpdate {
    return hasUpdate && update!.forceUpdate;
  }

  @override
  String toString() {
    return 'AppUpdateCheckResult('
        'current: ${current.version}+${current.buildNumber}, '
        'hasUpdate: $hasUpdate'
        ')';
  }
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  /// Dedicated Dio instance for GitHub.
  ///
  /// This is intentionally separate from the main backend client.
  final Dio _releaseDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      headers: const <String, String>{
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      },
    ),
  );

  /// ==========================================================
  /// CHECK FOR UPDATE
  /// ==========================================================

  Future<AppUpdateCheckResult> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();

    // ----------------------------------------------------------
    // 1. GITHUB RELEASE MANIFEST
    // ----------------------------------------------------------

    if (_releaseManifestUrl.trim().isNotEmpty) {
      try {
        final update = await _fetchGitHubManifest();

        if (update != null) {
          return AppUpdateCheckResult(
            current: packageInfo,
            update: update,
          );
        }
      } on DioException {
        // GitHub unavailable.
        // Continue to backend fallback.
      } on FormatException {
        // Invalid manifest.
        // Continue to backend fallback.
      } catch (_) {
        // Any unexpected GitHub error.
        // Continue to backend fallback.
      }
    }

    // ----------------------------------------------------------
    // 2. BACKEND FALLBACK
    // ----------------------------------------------------------

    try {
      final response = await DioClient.instance.dio.get(
        '/public/app-update',
      );

      final data = response.data;

      if (data == null) {
        return AppUpdateCheckResult(
          current: packageInfo,
          update: null,
        );
      }

      final Map<String, dynamic> payload;

      if (data is Map<String, dynamic>) {
        payload = data;
      } else if (data is Map) {
        payload = Map<String, dynamic>.from(data);
      } else if (data is String) {
        final decoded = jsonDecode(data);

        if (decoded is! Map) {
          throw const FormatException(
            'Invalid update response.',
          );
        }

        payload = Map<String, dynamic>.from(decoded);
      } else {
        throw const FormatException(
          'Invalid update response.',
        );
      }

      final update = AppUpdateInfo.fromJson(payload);

      return AppUpdateCheckResult(
        current: packageInfo,
        update: update,
      );
    } on DioException {
      rethrow;
    }
  }

  /// ==========================================================
  /// FETCH GITHUB MANIFEST
  /// ==========================================================

  Future<AppUpdateInfo?> _fetchGitHubManifest() async {
    final url = _releaseManifestUrl.trim();

    if (url.isEmpty) {
      return null;
    }

    final response = await _releaseDio.get(
      url,
      queryParameters: <String, dynamic>{
        // Prevent stale cached manifest.
        't': DateTime.now().millisecondsSinceEpoch,
      },
    );

    dynamic data = response.data;

    if (data is String) {
      data = jsonDecode(data);
    }

    if (data is! Map) {
      throw const FormatException(
        'GitHub update manifest is not a JSON object.',
      );
    }

    final update = AppUpdateInfo.fromJson(
      Map<String, dynamic>.from(data),
    );

    if (update.enabled && !update.isValid) {
      throw const FormatException(
        'GitHub update manifest is missing required fields.',
      );
    }

    return update;
  }

  /// ==========================================================
  /// OPEN APK DOWNLOAD
  /// ==========================================================

  Future<bool> openDownload(String url) async {
    final cleanUrl = url.trim();

    if (cleanUrl.isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(cleanUrl);

    if (uri == null) {
      return false;
    }

    if (!uri.hasScheme) {
      return false;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return false;
    }

    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  /// ==========================================================
  /// DOWNLOAD CURRENT UPDATE
  /// ==========================================================

  Future<bool> downloadUpdate(
    AppUpdateCheckResult result,
  ) async {
    if (!result.hasUpdate) {
      return false;
    }

    final update = result.update;

    if (update == null) {
      return false;
    }

    return openDownload(update.downloadUrl);
  }

  /// ==========================================================
  /// GET CURRENT APP VERSION
  /// ==========================================================

  Future<PackageInfo> getCurrentVersion() async {
    return PackageInfo.fromPlatform();
  }

  /// ==========================================================
  /// GET CURRENT VERSION STRING
  /// ==========================================================

  Future<String> getCurrentVersionString() async {
    final info = await PackageInfo.fromPlatform();

    return '${info.version} (${info.buildNumber})';
  }

  /// ==========================================================
  /// CHECK ONLY
  /// ==========================================================

  Future<bool> hasUpdate() async {
    final result = await checkForUpdate();

    return result.hasUpdate;
  }

  /// ==========================================================
  /// CHECK + OPEN DOWNLOAD
  /// ==========================================================

  Future<bool> checkAndOpenDownload() async {
    final result = await checkForUpdate();

    if (!result.hasUpdate) {
      return false;
    }

    return downloadUpdate(result);
  }
}