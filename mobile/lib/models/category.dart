class Category {
  final String id;
  final String name;
  final int sortOrder;
  final String status;

  Category({required this.id, required this.name, this.sortOrder = 0, this.status = 'active'});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['_id'] as String,
      name: json['name'] as String? ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'active',
    );
  }
}
