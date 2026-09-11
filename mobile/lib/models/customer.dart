class Customer {
  final String id;
  final String name;
  final String phone;
  final String? address;
  final String? notes;
  final double totalPurchases;
  final double totalPaid;
  final double outstandingBalance;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.address,
    this.notes,
    this.totalPurchases = 0,
    this.totalPaid = 0,
    this.outstandingBalance = 0,
  });

  bool get hasDue => outstandingBalance > 0;

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['_id'] as String,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      address: json['address'] as String?,
      notes: json['notes'] as String?,
      totalPurchases: (json['totalPurchases'] as num?)?.toDouble() ?? 0,
      totalPaid: (json['totalPaid'] as num?)?.toDouble() ?? 0,
      outstandingBalance: (json['outstandingBalance'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CreditTransaction {
  final String id;
  final String type; // 'DEBIT' | 'PAID'
  final double amount;
  final String method; // 'CASH' | 'UPI' | 'ORDER'
  final int? orderNumber;
  final double balanceAfter;
  final String? note;
  final DateTime createdAt;

  CreditTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.method,
    this.orderNumber,
    required this.balanceAfter,
    this.note,
    required this.createdAt,
  });

  factory CreditTransaction.fromJson(Map<String, dynamic> json) {
    final orderField = json['order'];
    return CreditTransaction(
      id: json['_id'] as String,
      type: json['type'] as String? ?? 'DEBIT',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      method: json['method'] as String? ?? 'CASH',
      orderNumber: orderField is Map ? (orderField['orderNumber'] as num?)?.toInt() : null,
      balanceAfter: (json['balanceAfter'] as num?)?.toDouble() ?? 0,
      note: json['note'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
