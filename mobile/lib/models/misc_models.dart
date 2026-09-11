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

  BusinessSettings({
    this.cafeName = 'FAST N FRESH CAFE',
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
  });

  factory BusinessSettings.fromJson(Map<String, dynamic> json) {
    return BusinessSettings(
      cafeName: json['cafeName'] as String? ?? 'FAST N FRESH CAFE',
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
    );
  }
}
