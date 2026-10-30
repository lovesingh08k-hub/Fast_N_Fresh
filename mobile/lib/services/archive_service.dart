import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/network/dio_client.dart';

/// Whether old records should be archived, and storage use (see backend
/// archiveController).
class ArchiveStatus {
  final bool due;
  final bool storageLow;
  final int everyDays;
  final int keepRecentDays;
  final DateTime? lastArchiveAt;
  final DateTime? oldestRecordAt;
  final String suggestedBefore;
  final int oldOrders;
  final double? usedMB;
  final double? limitMB;
  final int? percent;
  final String? lastRunStatus;
  final String? lastRunBefore;

  ArchiveStatus.fromJson(Map<String, dynamic> j)
      : due = j['due'] == true,
        storageLow = j['storageLow'] == true,
        everyDays = (j['everyDays'] as num?)?.toInt() ?? 120,
        keepRecentDays = (j['keepRecentDays'] as num?)?.toInt() ?? 90,
        lastArchiveAt = DateTime.tryParse(j['lastArchiveAt']?.toString() ?? ''),
        oldestRecordAt = DateTime.tryParse(j['oldestRecordAt']?.toString() ?? ''),
        suggestedBefore = j['suggestedBefore']?.toString() ?? '',
        oldOrders = (j['oldOrders'] as num?)?.toInt() ?? 0,
        usedMB = (j['storage']?['usedMB'] as num?)?.toDouble(),
        limitMB = (j['storage']?['limitMB'] as num?)?.toDouble(),
        percent = (j['storage']?['percent'] as num?)?.toInt(),
        lastRunStatus = j['lastRun']?['status']?.toString(),
        lastRunBefore = j['lastRun']?['before']?.toString();
}

/// One archived day kept as a total after its bills were deleted.
class DaySummary {
  final String date;
  final int orders;
  final double netSales;

  DaySummary.fromJson(Map<String, dynamic> j)
      : date = j['businessDate']?.toString() ?? '',
        orders = (j['orders'] as num?)?.toInt() ?? 0,
        netSales = (j['netSales'] as num?)?.toDouble() ?? 0;
}

class ArchiveService {
  final Dio _dio = DioClient.instance.dio;

  Future<ArchiveStatus> status() async {
    try {
      final res = await _dio.get('/archive/status');
      return ArchiveStatus.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Full backup (JSON) or bills sheet (CSV) of records before [before].
  Future<Uint8List> download({required String before, required bool csv}) async {
    try {
      final res = await _dio.get<List<int>>(
        csv ? '/archive/export.csv' : '/archive/export',
        queryParameters: {'before': before},
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 5)),
      );
      return Uint8List.fromList(res.data ?? const []);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Deletes the records before [before]; their backup must be downloaded first.
  Future<Map<String, dynamic>> purge(String before) async {
    try {
      final res = await _dio.post('/archive/purge', data: {'before': before});
      return Map<String, dynamic>.from(res.data['data'] as Map);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<List<DaySummary>> summaries() async {
    try {
      final res = await _dio.get('/archive/summaries');
      return (res.data['data'] as List).map((e) => DaySummary.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}
