import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';
import '../models/product.dart';
import '../models/dashboard_models.dart';

class InventoryService {
  final Dio _dio = DioClient.instance.dio;

  Future<(List<Product>, List<Product>)> getInventory() async {
    try {
      final res = await _dio.get('/inventory');
      final data = res.data['data'] as Map<String, dynamic>;
      final products = (data['products'] as List<dynamic>).map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
      final lowStock =
          (data['lowStockProducts'] as List<dynamic>).map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
      return (products, lowStock);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<List<InventoryTransaction>> getHistory(String productId) async {
    try {
      final res = await _dio.get('/inventory/$productId/history');
      final list = res.data['data'] as List<dynamic>;
      return list.map((e) => InventoryTransaction.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<void> adjust({required String productId, required String type, required int quantity, String? reason}) async {
    try {
      await _dio.post('/inventory/adjust', data: {
        'productId': productId,
        'type': type,
        'quantity': quantity,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}
