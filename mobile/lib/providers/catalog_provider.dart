import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/category.dart';
import '../services/catalog_service.dart';
import '../core/network/api_exception.dart';

class CatalogProvider extends ChangeNotifier {
  final ProductService _productService = ProductService();
  final CategoryService _categoryService = CategoryService();

  List<Product> products = [];
  List<Category> categories = [];
  bool isLoading = false;
  String? errorMessage;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _productService.list(status: 'available'),
        _categoryService.list(status: 'active'),
      ]);
      products = results[0] as List<Product>;
      categories = results[1] as List<Category>;
    } on ApiException catch (e) {
      errorMessage = e.message;
    } catch (_) {
      errorMessage = 'Could not load products. Please try again.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  List<Product> productsForCategory(String? categoryId) {
    if (categoryId == null) return products;
    return products.where((p) => p.categoryId == categoryId).toList();
  }
}
