import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';
import '../models/table.dart';
import '../models/order.dart';

class TableService {
  final Dio _dio = DioClient.instance.dio;

  Future<List<CafeTable>> list() async {
    try {
      final res = await _dio.get('/tables');
      final list = res.data['data'] as List<dynamic>;
      return list.map((e) => CafeTable.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Returns the table plus all its currently open (unpaid) customer orders.
  Future<(CafeTable, List<Order>)> getDetail(String tableId) async {
    try {
      final res = await _dio.get('/tables/$tableId');
      final data = res.data['data'] as Map<String, dynamic>;
      final table = CafeTable.fromJson(data['table'] as Map<String, dynamic>);
      final openOrders = (data['openOrders'] as List<dynamic>).map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
      return (table, openOrders);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<CafeTable> create({required String name, int capacity = 4}) async {
    try {
      final res = await _dio.post('/tables', data: {'name': name, 'capacity': capacity});
      return CafeTable.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<CafeTable> update(String id, Map<String, dynamic> body) async {
    try {
      final res = await _dio.put('/tables/$id', data: body);
      return CafeTable.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete('/tables/$id');
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Sets/changes this table's QR ordering number (used in /menu?table=N).
  /// Pass `null` to clear it.
  Future<CafeTable> setQrNumber(String id, int? number) => update(id, {'number': number});

  /// Fetches the PNG QR code image for this table's public ordering URL.
  /// Requires the table to already have a `number` assigned.
  Future<List<int>> fetchQrImageBytes(String tableId) async {
    try {
      final res = await _dio.get<List<int>>(
        '/tables/$tableId/qr',
        options: Options(responseType: ResponseType.bytes),
      );
      return res.data ?? const [];
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Starts a new open (unpaid) order/tab for one customer on this table.
  Future<Order> startOrder(String tableId, {String? tableCustomerLabel}) async {
    try {
      final res = await _dio.post('/tables/$tableId/orders', data: {
        if (tableCustomerLabel != null && tableCustomerLabel.isNotEmpty) 'tableCustomerLabel': tableCustomerLabel,
      });
      return Order.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}
