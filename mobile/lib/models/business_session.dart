/// One outlet (cafe/restaurant branch) of the client's business.
class OutletInfo {
  final String id;
  final String code;
  final String name;

  /// "<businessCode>:<outletCode>", used in QR menu links.
  final String key;

  const OutletInfo({required this.id, required this.code, required this.name, required this.key});

  factory OutletInfo.fromJson(Map<String, dynamic> json) => OutletInfo(
        id: json['id']?.toString() ?? '',
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        key: json['key']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'code': code, 'name': name, 'key': key};
}

/// The client (business) the user logged into, its licence and the
/// outlets this user may open. Absent on a single-cafe server without a
/// platform registry.
class BusinessSession {
  final String code;
  final String name;
  final DateTime? validUntil;
  final List<OutletInfo> outlets;

  /// Outlet the app is working in (sent as X-Outlet-Id).
  final String? currentOutletCode;

  const BusinessSession({
    required this.code,
    required this.name,
    required this.outlets,
    this.validUntil,
    this.currentOutletCode,
  });

  OutletInfo? get currentOutlet {
    for (final outlet in outlets) {
      if (outlet.code == currentOutletCode) return outlet;
    }
    return outlets.isEmpty ? null : outlets.first;
  }

  bool get hasManyOutlets => outlets.length > 1;

  /// Days until the licence ends (negative once expired), or null.
  int? get daysLeft => validUntil?.difference(DateTime.now()).inDays;

  BusinessSession withOutlet(String outletCode) => BusinessSession(
        code: code,
        name: name,
        validUntil: validUntil,
        outlets: outlets,
        currentOutletCode: outletCode,
      );

  /// Parses `{business, outlets, currentOutlet}` from the login or /me
  /// response; null when the server has no business (single-cafe setup).
  static BusinessSession? fromApi(Map<String, dynamic> data, {String? keepOutlet}) {
    final business = data['business'];
    if (business is! Map) return null;
    final outlets = (data['outlets'] as List? ?? const [])
        .whereType<Map>()
        .map((o) => OutletInfo.fromJson(Map<String, dynamic>.from(o)))
        .toList();
    final current = data['currentOutlet'];
    final serverOutlet = current is Map ? current['code']?.toString() : null;
    final wanted = keepOutlet != null && outlets.any((o) => o.code == keepOutlet) ? keepOutlet : serverOutlet;
    return BusinessSession(
      code: business['code']?.toString() ?? '',
      name: business['name']?.toString() ?? '',
      validUntil: DateTime.tryParse(business['validUntil']?.toString() ?? ''),
      outlets: outlets,
      currentOutletCode: wanted ?? (outlets.isEmpty ? null : outlets.first.code),
    );
  }

  factory BusinessSession.fromJson(Map<String, dynamic> json) => BusinessSession(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        validUntil: DateTime.tryParse(json['validUntil']?.toString() ?? ''),
        outlets: (json['outlets'] as List? ?? const [])
            .whereType<Map>()
            .map((o) => OutletInfo.fromJson(Map<String, dynamic>.from(o)))
            .toList(),
        currentOutletCode: json['currentOutletCode']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'validUntil': validUntil?.toIso8601String(),
        'outlets': outlets.map((o) => o.toJson()).toList(),
        'currentOutletCode': currentOutletCode,
      };
}
