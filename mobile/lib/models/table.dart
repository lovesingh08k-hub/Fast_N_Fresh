class CafeTable {
  final String id;
  final String name;
  final int capacity;
  final String status; // 'available' | 'occupied' | 'reserved' (manual)
  final String liveStatus; // server-computed: 'available' | 'occupied' | 'reserved'
  final int openOrderCount;
  // Numeric identifier used in the customer QR ordering URL (/menu?table=N).
  // Null until an admin/manager assigns one (see QR Management screen).
  final int? number;

  CafeTable({
    required this.id,
    required this.name,
    required this.capacity,
    required this.status,
    required this.liveStatus,
    required this.openOrderCount,
    this.number,
  });

  bool get isOccupied => liveStatus == 'occupied';
  bool get isAvailable => liveStatus == 'available';
  bool get isReserved => liveStatus == 'reserved';
  bool get hasQrNumber => number != null;

  factory CafeTable.fromJson(Map<String, dynamic> json) {
    return CafeTable(
      id: json['_id'] as String,
      name: json['name'] as String? ?? '',
      capacity: (json['capacity'] as num?)?.toInt() ?? 4,
      status: json['status'] as String? ?? 'available',
      liveStatus: json['liveStatus'] as String? ?? json['status'] as String? ?? 'available',
      openOrderCount: (json['openOrderCount'] as num?)?.toInt() ?? 0,
      number: (json['number'] as num?)?.toInt(),
    );
  }
}
