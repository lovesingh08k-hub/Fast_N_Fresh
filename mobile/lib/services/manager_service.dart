import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';
import '../core/network/api_exception.dart';

class ManagerService {
  final Dio _dio = DioClient.instance.dio;

  /// Loads the manager day summary. New backends expose /manager/day.
  /// Older deployed backends may not have the manager module yet; in that
  /// case fall back to the authenticated dashboard so the Manager Center
  /// still opens instead of showing a blank/error screen.
  Future<Map<String, dynamic>> day({String? date}) async {
    try {
      final response = await _dio.get(
        '/manager/day',
        queryParameters: {if (date != null) 'date': date},
      );
      final data = response.data['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      throw const FormatException('Invalid manager day response');
    } catch (e) {
      // The APK and backend may be deployed independently. If the Manager
      // module is missing on the currently hosted backend, use the normal
      // dashboard endpoint so Manager Center still opens with read-only
      // sales data. Never hide authentication/permission errors.
      final status = _statusCode(e);
      if (status != 404) rethrow;

      final response = await _dio.get('/dashboard');
      final raw = response.data['data'];
      if (raw is! Map) throw const FormatException('Invalid dashboard response');
      final dashboard = Map<String, dynamic>.from(raw);
      final todayRaw = dashboard['today'];
      final today = todayRaw is Map
          ? Map<String, dynamic>.from(todayRaw)
          : <String, dynamic>{};

      return <String, dynamic>{
        'date': date ?? _todayIso(),
        'sales': today['sales'] ?? 0,
        'orders': today['orders'] ?? 0,
        'cashSales': today['cash'] ?? 0,
        'upi': today['upi'] ?? 0,
        'credit': today['credit'] ?? 0,
        'cashExpenses': 0,
        'cashIn': 0,
        'cashOut': 0,
        'openingCash': 0,
        'expectedCash': today['cash'] ?? 0,
        'cashRefunds': 0,
        'upiRefunds': 0,
        'pendingKitchen': 0,
        'lowStock': dashboard['lowStockCount'] ?? 0,
        'closed': false,
        'shift': null,
        '_managerEndpointUnavailable': true,
      };
    }
  }

  int? _statusCode(Object error) {
    if (error is ApiException) return error.statusCode;
    try {
      final response = (error as dynamic).response;
      final status = response?.statusCode;
      return status is int ? status : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> openDay(double openingCash, {String? date}) async {
    await _dio.post(
      '/manager/day/open',
      data: {
        'openingCash': openingCash,
        if (date != null) 'businessDate': date,
      },
    );
  }

  Future<Map<String, dynamic>> closeDay(
    double actualCash, {
    String? date,
    String? note,
  }) async {
    final response = await _dio.post(
      '/manager/day/close',
      data: {
        'actualCash': actualCash,
        if (date != null) 'businessDate': date,
        if (note != null) 'note': note,
      },
    );
    return Map<String, dynamic>.from(response.data['data'] as Map);
  }

  Future<void> cashMovement(
    String type,
    double amount,
    String reason, {
    String? reference,
  }) async {
    await _dio.post(
      '/manager/cash-movement',
      data: {
        'type': type,
        'amount': amount,
        'reason': reason,
        if (reference != null) 'reference': reference,
      },
    );
  }

  Future<void> wastage(
    String productId,
    double quantity,
    String reason,
    String notes,
  ) async {
    await _dio.post(
      '/manager/wastage',
      data: {
        'productId': productId,
        'quantity': quantity,
        'reason': reason,
        'notes': notes,
      },
    );
  }

  Future<List<dynamic>> wastageList() async =>
      (await _dio.get('/manager/wastage')).data['data'];

  Future<void> purchase({
    required String supplier,
    required List<Map<String, dynamic>> items,
    double tax = 0,
    String? invoice,
  }) async {
    await _dio.post(
      '/manager/purchases',
      data: {
        'supplier': supplier,
        'items': items,
        'tax': tax,
        if (invoice != null) 'invoiceNumber': invoice,
      },
    );
  }

  Future<List<dynamic>> purchases() async =>
      (await _dio.get('/manager/purchases')).data['data'];

  String _todayIso() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }
}
