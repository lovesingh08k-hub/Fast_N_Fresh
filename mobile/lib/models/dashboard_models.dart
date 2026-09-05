import 'user.dart';

class StaffPerformance {
  final AppUser staff;
  final double todaySales;
  final int todayBills;

  StaffPerformance({required this.staff, required this.todaySales, required this.todayBills});

  factory StaffPerformance.fromJson(Map<String, dynamic> json) {
    final today = json['today'] as Map<String, dynamic>? ?? {};
    return StaffPerformance(
      staff: AppUser.fromJson(json['staff'] as Map<String, dynamic>),
      todaySales: (today['sales'] as num?)?.toDouble() ?? 0,
      todayBills: (today['bills'] as num?)?.toInt() ?? 0,
    );
  }
}

class InventoryTransaction {
  final String id;
  final String type;
  final int quantity;
  final int stockAfter;
  final String? reason;
  final String? recordedByName;
  final DateTime createdAt;

  InventoryTransaction({
    required this.id,
    required this.type,
    required this.quantity,
    required this.stockAfter,
    this.reason,
    this.recordedByName,
    required this.createdAt,
  });

  factory InventoryTransaction.fromJson(Map<String, dynamic> json) {
    final recordedBy = json['recordedBy'];
    return InventoryTransaction(
      id: json['_id'] as String,
      type: json['type'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      stockAfter: (json['stockAfter'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String?,
      recordedByName: recordedBy is Map ? recordedBy['name'] as String? : null,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class PeriodSummary {
  final double sales;
  final int orders;
  final double cash;
  final double upi;
  final double credit;

  PeriodSummary({this.sales = 0, this.orders = 0, this.cash = 0, this.upi = 0, this.credit = 0});

  factory PeriodSummary.fromJson(Map<String, dynamic> json) {
    return PeriodSummary(
      sales: (json['sales'] as num?)?.toDouble() ?? 0,
      orders: (json['orders'] as num?)?.toInt() ?? 0,
      cash: (json['cash'] as num?)?.toDouble() ?? 0,
      upi: (json['upi'] as num?)?.toDouble() ?? 0,
      credit: (json['credit'] as num?)?.toDouble() ?? 0,
    );
  }
}

class RecentOrderSummary {
  final int orderNumber;
  final String itemsSummary;
  final double grandTotal;
  final String paymentMethod;
  final String status;
  final String orderSource;
  final String? tableName;
  final DateTime createdAt;

  RecentOrderSummary({
    required this.orderNumber,
    required this.itemsSummary,
    required this.grandTotal,
    required this.paymentMethod,
    this.status = 'completed',
    this.orderSource = 'pos',
    this.tableName,
    required this.createdAt,
  });

  factory RecentOrderSummary.fromJson(Map<String, dynamic> json) {
    // Normalize backend values so UI comparisons remain reliable even if an
    // older deployment/API response uses uppercase status names.
    final rawStatus = json['status']?.toString().trim().toLowerCase();
    final normalizedStatus = switch (rawStatus) {
      'open' => 'open',
      'preparing' => 'preparing',
      'ready' => 'ready',
      'completed' => 'completed',
      'voided' => 'voided',
      _ => 'completed',
    };

    final rawPayment = json['paymentMethod']?.toString().trim().toUpperCase();

    return RecentOrderSummary(
      orderNumber: (json['orderNumber'] as num?)?.toInt() ?? 0,
      itemsSummary: json['itemsSummary'] as String? ?? '',
      grandTotal: (json['grandTotal'] as num?)?.toDouble() ?? 0,
      paymentMethod: rawPayment == null || rawPayment.isEmpty
          ? (normalizedStatus == 'completed' ? '—' : 'UNPAID')
          : rawPayment,
      status: normalizedStatus,
      orderSource: json['orderSource']?.toString().trim().toLowerCase() == 'qr' ? 'qr' : 'pos',
      tableName: json['tableName'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class TopProduct {
  final String name;
  final int quantitySold;

  TopProduct({required this.name, required this.quantitySold});

  factory TopProduct.fromJson(Map<String, dynamic> json) {
    return TopProduct(name: json['name'] as String? ?? '', quantitySold: (json['quantitySold'] as num?)?.toInt() ?? 0);
  }
}

class DashboardData {
  final PeriodSummary today;
  final int lowStockCount;
  final double outstandingCreditTotal;
  final int outstandingCreditCustomerCount;
  final List<RecentOrderSummary> recentOrders;
  final List<TopProduct> topSellingProducts;

  DashboardData({
    required this.today,
    required this.lowStockCount,
    required this.outstandingCreditTotal,
    required this.outstandingCreditCustomerCount,
    required this.recentOrders,
    required this.topSellingProducts,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final outstanding = json['outstandingCredit'] as Map<String, dynamic>? ?? {};
    return DashboardData(
      today: PeriodSummary.fromJson(json['today'] as Map<String, dynamic>? ?? {}),
      lowStockCount: (json['lowStockCount'] as num?)?.toInt() ?? 0,
      outstandingCreditTotal: (outstanding['total'] as num?)?.toDouble() ?? 0,
      outstandingCreditCustomerCount: (outstanding['customerCount'] as num?)?.toInt() ?? 0,
      recentOrders: (json['recentOrders'] as List<dynamic>? ?? [])
          .map((e) => RecentOrderSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      topSellingProducts:
          (json['topSellingProducts'] as List<dynamic>? ?? []).map((e) => TopProduct.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class DailySales {
  final String date;
  final double sales;
  final int orders;

  DailySales({required this.date, required this.sales, required this.orders});

  factory DailySales.fromJson(Map<String, dynamic> json) {
    return DailySales(
      date: json['date'] as String? ?? '',
      sales: (json['sales'] as num?)?.toDouble() ?? 0,
      orders: (json['orders'] as num?)?.toInt() ?? 0,
    );
  }
}

class SalesOverview {
  final PeriodSummary today;
  final PeriodSummary yesterday;
  final PeriodSummary thisWeek;
  final PeriodSummary thisMonth;
  final List<DailySales> last14Days;

  SalesOverview({
    required this.today,
    required this.yesterday,
    required this.thisWeek,
    required this.thisMonth,
    required this.last14Days,
  });

  factory SalesOverview.fromJson(Map<String, dynamic> json) {
    return SalesOverview(
      today: PeriodSummary.fromJson(json['today'] as Map<String, dynamic>? ?? {}),
      yesterday: PeriodSummary.fromJson(json['yesterday'] as Map<String, dynamic>? ?? {}),
      thisWeek: PeriodSummary.fromJson(json['thisWeek'] as Map<String, dynamic>? ?? {}),
      thisMonth: PeriodSummary.fromJson(json['thisMonth'] as Map<String, dynamic>? ?? {}),
      last14Days: (json['last14Days'] as List<dynamic>? ?? []).map((e) => DailySales.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
