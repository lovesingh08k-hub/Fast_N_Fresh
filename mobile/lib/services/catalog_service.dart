import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';
import '../models/product.dart';
import '../models/category.dart';

class ProductService {
  final Dio _dio = DioClient.instance.dio;

  Future<List<Product>> list({String? search, String? categoryId, String? status, bool lowStock = false}) async {
    try {
      final res = await _dio.get('/products', queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        if (categoryId != null) 'category': categoryId,
        if (status != null) 'status': status,
        if (lowStock) 'lowStock': 'true',
        'limit': 200,
      });
      final list = res.data['data'] as List<dynamic>;
      return list.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw DioClient.instance.mapError(e);
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
      final res = await _dio.get('/categories', queryParameters: {if (status != null) 'status': status});
      final list = res.data['data'] as List<dynamic>;
      return list.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
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
