import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/category.dart';
import '../services/catalog_service.dart';
import '../core/network/api_exception.dart';
import '../core/utils/pos_debug_log.dart';

/// Shared POS catalog state.
///
/// Products and categories are loaded independently. A failure in the
/// categories endpoint must NEVER erase a successfully loaded product menu;
/// that was the main cause of the POS appearing empty even when the backend
/// already had products.
class CatalogProvider extends ChangeNotifier {
  final ProductService _productService = ProductService();
  final CategoryService _categoryService = CategoryService();

  List<Product> products = [];
  List<Category> categories = [];
  bool isLoading = false;
  String? errorMessage;
  String? categoryErrorMessage;
  Future<void>? _activeLoad;

  Future<void> ensureLoaded() {
    if (products.isNotEmpty) {
      // Categories can still be missing independently; refresh them in the
      // background without blocking the already-visible product menu.
      if (categories.isEmpty && categoryErrorMessage != null) {
        _loadCategoriesOnly();
      }
      return _activeLoad ?? Future<void>.value();
    }
    return load();
  }

  Future<void> load() {
    final existing = _activeLoad;
    if (existing != null) return existing;

    final operation = _loadInternal();
    _activeLoad = operation;
    operation.whenComplete(() {
      if (identical(_activeLoad, operation)) _activeLoad = null;
    });
    return operation;
  }

  Future<void> _loadInternal() async {
    isLoading = true;
    errorMessage = null;
    categoryErrorMessage = null;
    notifyListeners();

    posLog('Fetching menu...');

    // Do NOT use Future.wait here. If /categories fails while /products
    // succeeds, Future.wait would throw and leave the POS with zero products.
    Object? productFailure;

    try {
      products = await _productService.list();
    } on ApiException catch (e) {
      productFailure = e;
      errorMessage = e.message;
      posLog('Error: products load failed - "${e.message}" (statusCode: ${e.statusCode}, type: ${e.type})');
    } catch (e) {
      productFailure = Object();
      errorMessage = 'Could not load products. Please try again.';
      posLog('Error: products load failed with an unexpected exception - $e');
    }
    notifyListeners();

    try {
      categories = await _categoryService.list(status: 'active');
      categoryErrorMessage = null;
    } on ApiException catch (e) {
      categoryErrorMessage = e.message;
      // Categories are optional for showing the menu. Keep the products.
      if (categories.isEmpty) categories = [];
      posLog('Error: categories load failed - "${e.message}" (statusCode: ${e.statusCode}, type: ${e.type})');
    } catch (e) {
      categoryErrorMessage = 'Categories could not be loaded.';
      posLog('Error: categories load failed with an unexpected exception - $e');
    }

    isLoading = false;
    if (products.isEmpty && productFailure == null) {
      errorMessage = null;
    }
    posLog(
      'Load complete -> products: ${products.length}, categories: ${categories.length}, '
      'errorMessage: $errorMessage, categoryErrorMessage: $categoryErrorMessage',
    );
    notifyListeners();
  }

  Future<void> _loadCategoriesOnly() async {
    try {
      final loaded = await _categoryService.list(status: 'active');
      if (loaded.isNotEmpty && categories != loaded) {
        categories = loaded;
        categoryErrorMessage = null;
        notifyListeners();
      }
    } catch (_) {
      // Categories are optional. Never blank the POS over this request.
    }
  }

  List<Product> productsForCategory(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) return products;
    return products.where((p) => p.categoryId == categoryId).toList();
  }
}
