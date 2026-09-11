class Product {
  final String id;
  final String name;
  final String categoryId;
  final String? categoryName;
  final double sellingPrice;
  final double costPrice;
  final bool trackInventory;
  final int stock;
  final int lowStockThreshold;
  final String status; // 'available' | 'unavailable'
  final String imageUrl;
  final List<Map<String,dynamic>> recipe; // relative URL, resolve against ApiConfig host to display

  Product({
    required this.id,
    required this.name,
    required this.categoryId,
    this.categoryName,
    required this.sellingPrice,
    this.costPrice = 0,
    this.trackInventory = true,
    this.stock = 0,
    this.lowStockThreshold = 10,
    this.status = 'available',
    this.imageUrl = '',
    this.recipe = const [],
  });

  bool get hasImage => imageUrl.isNotEmpty;

  bool get isLowStock => trackInventory && stock <= lowStockThreshold;
  bool get isAvailable => status == 'available';

  factory Product.fromJson(Map<String, dynamic> json) {
    final rawId = json['_id'] ?? json['id'];
    final rawName = json['name'];
    if (rawId == null || rawName == null) {
      throw const FormatException('Product is missing id or name');
    }

    final categoryField = json['category'];
    var categoryId = '';
    String? categoryName;
    if (categoryField is Map) {
      final id = categoryField['_id'] ?? categoryField['id'];
      if (id is String) categoryId = id;
      final name = categoryField['name'];
      if (name is String) categoryName = name;
    } else if (categoryField is String) {
      categoryId = categoryField;
    }

    final rawRecipe = json['recipe'];
    final recipe = <Map<String, dynamic>>[];
    if (rawRecipe is List) {
      for (final item in rawRecipe) {
        if (item is Map) {
          recipe.add(Map<String, dynamic>.from(item));
        }
      }
    }

    return Product(
      id: rawId.toString(),
      name: rawName.toString(),
      categoryId: categoryId,
      categoryName: categoryName,
      sellingPrice: (json['sellingPrice'] as num?)?.toDouble() ?? 0,
      costPrice: (json['costPrice'] as num?)?.toDouble() ?? 0,
      trackInventory: json['trackInventory'] is bool ? json['trackInventory'] as bool : true,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      lowStockThreshold: (json['lowStockThreshold'] as num?)?.toInt() ?? 10,
      status: json['status'] is String ? json['status'] as String : 'available',
      imageUrl: json['imageUrl'] is String ? json['imageUrl'] as String : '',
      recipe: recipe,
    );
  }
}
