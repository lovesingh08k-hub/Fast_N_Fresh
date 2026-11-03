import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';
import '../core/utils/pos_debug_log.dart';
import '../models/product.dart';
import '../models/category.dart';

class ProductService {
  static const _pageSize = 200;

  final Dio _dio = DioClient.instance.dio;

  Future<List<Product>> list({String? search, String? categoryId, String? status, bool lowStock = false}) async {
    final queryParameters = {
      if (search != null && search.isNotEmpty) 'search': search,
      if (categoryId != null) 'category': categoryId,
      if (status != null) 'status': status,
      if (lowStock) 'lowStock': 'true',
      'limit': _pageSize,
    };

    // The server gives at most [_pageSize] at a time; a big menu has more.
    final data = <dynamic>[];
    try {
      for (var page = 1;; page++) {
        final res = await _dio.get('/products', queryParameters: {...queryParameters, if (page > 1) 'page': page});
        final raw = res.data;
        final rows = raw is Map ? raw['data'] : null;
        if (rows is! List) {
          throw const FormatException('Invalid products response: data is not a list');
        }
        data.addAll(rows);
        if (rows.length < _pageSize) break;
      }
    } on FormatException {
      rethrow;
    } catch (e) {
      posLog('Products request FAILED: $e');
      throw DioClient.instance.mapError(e);
    }

    try {
      posLog('Raw product count: ${data.length}');

      // Parse defensively: one malformed product must not blank the complete
      // POS menu. Invalid rows are skipped and logged.
      final parsed = <Product>[];
      for (var i = 0; i < data.length; i++) {
        final item = data[i];
        if (item is! Map) {
          posLog('Skipping malformed product row $i: expected object, got ${item.runtimeType}');
          continue;
        }
        try {
          parsed.add(Product.fromJson(Map<String, dynamic>.from(item)));
        } catch (e) {
          posLog('Skipping malformed product row $i: $e');
        }
      }
      posLog('Parsed product count: ${parsed.length}');
      return parsed;
    } catch (e) {
      posLog('Failed to parse products response: $e');
      rethrow;
    }
  }

  Future<Product> create(Map<String, dynamic> body) async {
    try {
      final res = await _dio.post('/products', data: body);
      return Product.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<Product> update(String id, Map<String, dynamic> body) async {
    try {
      final res = await _dio.put('/products/$id', data: body);
      return Product.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete('/products/$id');
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}

class CategoryService {
  final Dio _dio = DioClient.instance.dio;

  Future<List<Category>> list({String? status}) async {
    try {
      posLog('Request URL: ${_dio.options.baseUrl}/categories | params: {status: $status}');
      final res = await _dio.get('/categories', queryParameters: {if (status != null) 'status': status});
      posLog('Categories response status: ${res.statusCode}');
      final raw = res.data;
      final data = raw is Map ? raw['data'] : null;
      if (data is! List) {
        throw const FormatException('Invalid categories response: data is not a list');
      }
      posLog('Raw category count: ${data.length}');
      final parsed = <Category>[];
      for (var i = 0; i < data.length; i++) {
        final item = data[i];
        if (item is! Map) {
          posLog('Skipping malformed category row $i');
          continue;
        }
        try {
          parsed.add(Category.fromJson(Map<String, dynamic>.from(item)));
        } catch (e) {
          posLog('Skipping malformed category row $i: $e');
        }
      }
      posLog('Parsed category count: ${parsed.length}');
      return parsed;
    } catch (e) {
      posLog('Categories request FAILED: $e');
      throw DioClient.instance.mapError(e);
    }
  }

  Future<Category> create(String name) async {
    try {
      final res = await _dio.post('/categories', data: {'name': name});
      return Category.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<Category> update(String id, Map<String, dynamic> body) async {
    try {
      final res = await _dio.put('/categories/$id', data: body);
      return Category.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete('/categories/$id');
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}
