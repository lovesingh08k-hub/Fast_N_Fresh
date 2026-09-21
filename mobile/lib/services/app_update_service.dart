import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/dio_client.dart';

/// Set by the release workflow to the GitHub Releases "latest" manifest.
/// Keeping this separate from the API means backend deployments do not have
/// to be changed every time a Flutter APK is released.
const String _releaseManifestUrl = String.fromEnvironment(
  'UPDATE_MANIFEST_URL',
  defaultValue: '',
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
      version: json['version']?.toString() ?? '',
      buildNumber: int.tryParse(json['buildNumber']?.toString() ?? '') ?? 0,
      downloadUrl: json['downloadUrl']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      forceUpdate: json['forceUpdate'] == true,
    );
  }
}

class AppUpdateCheckResult {
  final PackageInfo current;
  final AppUpdateInfo? update;

  const AppUpdateCheckResult({required this.current, this.update});

  bool get hasUpdate =>
      update != null &&
      update!.enabled &&
      update!.downloadUrl.isNotEmpty &&
      update!.buildNumber > (int.tryParse(current.buildNumber) ?? 0);
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  final Dio _releaseDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      headers: const {'Accept': 'application/json'},
    ),
  );

  Future<AppUpdateCheckResult> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();

    // Preferred source: GitHub Releases. This is independent of Render cold
    // starts and means a Flutter release never needs a backend env edit.
    if (_releaseManifestUrl.trim().isNotEmpty) {
      try {
        final response = await _releaseDio.get(_releaseManifestUrl);
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (data is Map) {
          return AppUpdateCheckResult(
            current: packageInfo,
            update: AppUpdateInfo.fromJson(Map<String, dynamic>.from(data)),
          );
        }
      } on DioException {
        // Fall through to the backend endpoint for backward compatibility.
      } on FormatException {
        // Fall through to the backend endpoint for backward compatibility.
      }
    }

    try {
      final response = await DioClient.instance.dio.get('/public/app-update');
      final data = response.data;
      final payload = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data as Map);
      final update = AppUpdateInfo.fromJson(payload);
      return AppUpdateCheckResult(current: packageInfo, update: update);
    } on DioException {
      rethrow;
    }
  }

  Future<bool> openDownload(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
