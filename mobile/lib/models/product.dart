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
  final String imageUrl; // relative URL, resolve against ApiConfig host to display

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
  });

  bool get hasImage => imageUrl.isNotEmpty;

  bool get isLowStock => trackInventory && stock <= lowStockThreshold;
  bool get isAvailable => status == 'available';

  factory Product.fromJson(Map<String, dynamic> json) {
    final categoryField = json['category'];
    String categoryId;
    String? categoryName;
    if (categoryField is Map) {
      categoryId = categoryField['_id'] as String;
      categoryName = categoryField['name'] as String?;
    } else {
      categoryId = categoryField as String? ?? '';
    }

    return Product(
      id: json['_id'] as String,
      name: json['name'] as String? ?? '',
      categoryId: categoryId,
      categoryName: categoryName,
      sellingPrice: (json['sellingPrice'] as num?)?.toDouble() ?? 0,
      costPrice: (json['costPrice'] as num?)?.toDouble() ?? 0,
      trackInventory: json['trackInventory'] as bool? ?? true,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      lowStockThreshold: (json['lowStockThreshold'] as num?)?.toInt() ?? 10,
      status: json['status'] as String? ?? 'available',
      imageUrl: json['imageUrl'] as String? ?? '',
    );
  }
}
