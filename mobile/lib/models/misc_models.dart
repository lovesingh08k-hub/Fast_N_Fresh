class Expense {
  final String id;
  final String title;
  final String category;
  final double amount;
  final DateTime date;
  final String? notes;
  final String? recordedByName;

  Expense({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.date,
    this.notes,
    this.recordedByName,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    final recordedBy = json['recordedBy'];
    return Expense(
      id: json['_id'] as String,
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? 'Other',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      notes: json['notes'] as String?,
      recordedByName: recordedBy is Map ? recordedBy['name'] as String? : null,
    );
  }
}

class BusinessSettings {
  final String cafeName;
  final String tagline;
  final String phone;
  final String address;
  final String gstNumber;
  final String logoUrl;
  final String upiId;
  final String receiptFooter;
  final bool taxEnabled;
  final double taxPercent;
  final double defaultDiscount;
  final String currencySymbol;
  final String primaryColor;

  // Billing (see backend services/billing.js).
  final bool taxInclusive; // menu prices already include GST
  final String gstType; // cgst_sgst | igst
  final String fssai;
  final String invoicePrefix;
  final bool roundOff;
  final double serviceChargePercent;
  final List<String> serviceChargeOn; // order types
  final double packagingCharge;
  final List<String> packagingChargeOn;
  final double deliveryCharge;
  final List<String> onlinePlatforms; // Swiggy, Zomato...

  BusinessSettings({
    this.cafeName = 'PWP POS • PERSONALIZE WEB PAGE',
    this.tagline = 'Fresh • Fast • Delicious',
    this.phone = '',
    this.address = '',
    this.gstNumber = '',
    this.logoUrl = '',
    this.upiId = '',
    this.receiptFooter = 'Thank you for visiting!\nVisit Again',
    this.taxEnabled = false,
    this.taxPercent = 0,
    this.defaultDiscount = 0,
    this.currencySymbol = '₹',
    this.primaryColor = '#0E7C5A',
    this.taxInclusive = false,
    this.gstType = 'cgst_sgst',
    this.fssai = '',
    this.invoicePrefix = 'INV',
    this.roundOff = true,
    this.serviceChargePercent = 0,
    this.serviceChargeOn = const ['dine_in'],
    this.packagingCharge = 0,
    this.packagingChargeOn = const ['takeaway', 'delivery'],
    this.deliveryCharge = 0,
    this.onlinePlatforms = const ['Swiggy', 'Zomato'],
  });

  static List<String> _strings(Object? v, List<String> fallback) =>
      v is List ? v.map((e) => e.toString()).toList() : fallback;

  factory BusinessSettings.fromJson(Map<String, dynamic> json) {
    return BusinessSettings(
      cafeName: json['cafeName'] as String? ?? 'PWP POS • PERSONALIZE WEB PAGE',
      tagline: json['tagline'] as String? ?? 'Fresh • Fast • Delicious',
      phone: json['phone'] as String? ?? '',
      address: json['address'] as String? ?? '',
      gstNumber: json['gstNumber'] as String? ?? '',
      logoUrl: json['logoUrl'] as String? ?? '',
      upiId: json['upiId'] as String? ?? '',
      receiptFooter: json['receiptFooter'] as String? ?? 'Thank you for visiting!\nVisit Again',
      taxEnabled: json['taxEnabled'] as bool? ?? false,
      taxPercent: (json['taxPercent'] as num?)?.toDouble() ?? 0,
      defaultDiscount: (json['defaultDiscount'] as num?)?.toDouble() ?? 0,
      currencySymbol: json['currencySymbol'] as String? ?? '₹',
      primaryColor: json['primaryColor'] as String? ?? '#0E7C5A',
      taxInclusive: json['taxInclusive'] == true,
      gstType: json['gstType'] as String? ?? 'cgst_sgst',
      fssai: json['fssai'] as String? ?? '',
      invoicePrefix: json['invoicePrefix'] as String? ?? 'INV',
      roundOff: json['roundOff'] as bool? ?? true,
      serviceChargePercent: (json['serviceChargePercent'] as num?)?.toDouble() ?? 0,
      serviceChargeOn: _strings(json['serviceChargeOn'], const ['dine_in']),
      packagingCharge: (json['packagingCharge'] as num?)?.toDouble() ?? 0,
      packagingChargeOn: _strings(json['packagingChargeOn'], const ['takeaway', 'delivery']),
      deliveryCharge: (json['deliveryCharge'] as num?)?.toDouble() ?? 0,
      onlinePlatforms: _strings(json['onlinePlatforms'], const ['Swiggy', 'Zomato']),
    );
  }
}
