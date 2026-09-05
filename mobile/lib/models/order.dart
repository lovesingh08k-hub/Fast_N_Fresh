class OrderItem {
  final String productId;
  final String name;
  final double price;
  final int quantity;
  final double total;

  OrderItem({required this.productId, required this.name, required this.price, required this.quantity, required this.total});

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final productField = json['product'];
    return OrderItem(
      productId: productField is Map ? productField['_id'] as String : (productField as String? ?? ''),
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
    );
  }
}

class PaymentBreakdown {
  final double cash;
  final double upi;
  final double credit;

  PaymentBreakdown({this.cash = 0, this.upi = 0, this.credit = 0});

  factory PaymentBreakdown.fromJson(Map<String, dynamic>? json) {
    if (json == null) return PaymentBreakdown();
    return PaymentBreakdown(
      cash: (json['cash'] as num?)?.toDouble() ?? 0,
      upi: (json['upi'] as num?)?.toDouble() ?? 0,
      credit: (json['credit'] as num?)?.toDouble() ?? 0,
    );
  }
}

class DeliveryInfo {
  final String? address;
  final String? phone;
  DeliveryInfo({this.address, this.phone});

  factory DeliveryInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return DeliveryInfo();
    return DeliveryInfo(address: json['address'] as String?, phone: json['phone'] as String?);
  }
}

/// Contact info a customer optionally gave when placing a QR order directly
/// (no staff/login involved). Absent on regular POS orders.
class QrCustomerContact {
  final String? name;
  final String? phone;
  QrCustomerContact({this.name, this.phone});

  factory QrCustomerContact.fromJson(Map<String, dynamic>? json) {
    if (json == null) return QrCustomerContact();
    return QrCustomerContact(name: json['name'] as String?, phone: json['phone'] as String?);
  }
}

class Order {
  final String id;
  final int orderNumber;
  final List<OrderItem> items;
  final double subtotal;
  final double discount;
  final double tax;
  final double grandTotal;
  final String orderType; // dine_in | takeaway | delivery
  final String orderSource; // pos | qr — how this order was placed
  final String? tableId;
  final String? tableName;
  final String? tableCustomerLabel;
  final QrCustomerContact? qrCustomerContact;
  final DeliveryInfo? deliveryInfo;
  final String paymentMethod; // CASH | UPI | CREDIT | MIXED
  final String paymentStatus; // pending | payment_initiated | paid | failed | cancelled
  final PaymentBreakdown paymentBreakdown;
  final String? upiReference;
  final double? amountReceived;
  final double changeReturned;
  final String? customerId;
  final String? customerName;
  final String? notes;
  final String staffId;
  final String? staffName; // this is the current "attended by" employee
  final String status; // open | preparing | ready | completed | voided
  final DateTime createdAt;
  final DateTime? estimatedReadyAt;

  Order({
    required this.id,
    required this.orderNumber,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.grandTotal,
    this.orderType = 'takeaway',
    this.orderSource = 'pos',
    this.tableId,
    this.tableName,
    this.tableCustomerLabel,
    this.qrCustomerContact,
    this.deliveryInfo,
    required this.paymentMethod,
    this.paymentStatus = 'pending',
    required this.paymentBreakdown,
    this.upiReference,
    this.amountReceived,
    this.changeReturned = 0,
    this.customerId,
    this.customerName,
    this.notes,
    required this.staffId,
    this.staffName,
    required this.status,
    required this.createdAt,
    this.estimatedReadyAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final customerField = json['customer'];
    final staffField = json['staff'];
    final tableField = json['table'];

    return Order(
      id: json['_id'] as String,
      orderNumber: (json['orderNumber'] as num?)?.toInt() ?? 0,
      items: (json['items'] as List<dynamic>? ?? []).map((e) => OrderItem.fromJson(e as Map<String, dynamic>)).toList(),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      tax: (json['tax'] as num?)?.toDouble() ?? 0,
      grandTotal: (json['grandTotal'] as num?)?.toDouble() ?? 0,
      orderType: json['orderType'] as String? ?? 'takeaway',
      orderSource: json['orderSource'] as String? ?? 'pos',
      tableId: tableField is Map ? tableField['_id'] as String? : tableField as String?,
      tableName: tableField is Map ? tableField['name'] as String? : null,
      tableCustomerLabel: json['tableCustomerLabel'] as String?,
      qrCustomerContact: json['qrCustomerContact'] != null
          ? QrCustomerContact.fromJson(json['qrCustomerContact'] as Map<String, dynamic>?)
          : null,
      deliveryInfo: json['deliveryInfo'] != null ? DeliveryInfo.fromJson(json['deliveryInfo'] as Map<String, dynamic>?) : null,
      paymentMethod: json['paymentMethod'] as String? ?? 'CASH',
      paymentStatus: json['paymentStatus'] as String? ?? ((json['status'] as String?) == 'completed' ? 'paid' : 'pending'),
      paymentBreakdown: PaymentBreakdown.fromJson(json['paymentBreakdown'] as Map<String, dynamic>?),
      upiReference: json['upiReference'] as String?,
      amountReceived: (json['amountReceived'] as num?)?.toDouble(),
      changeReturned: (json['changeReturned'] as num?)?.toDouble() ?? 0,
      customerId: customerField is Map ? customerField['_id'] as String? : customerField as String?,
      customerName: customerField is Map ? customerField['name'] as String? : null,
      notes: json['notes'] as String?,
      staffId: staffField is Map ? staffField['_id'] as String? ?? '' : staffField as String? ?? '',
      staffName: staffField is Map ? staffField['name'] as String? : null,
      status: json['status'] as String? ?? 'completed',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      estimatedReadyAt: DateTime.tryParse(json['estimatedReadyAt'] as String? ?? ''),
    );
  }

  bool get isQrOrder => orderSource == 'qr';
}
