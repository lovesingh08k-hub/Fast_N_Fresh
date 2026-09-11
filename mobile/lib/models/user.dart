class AppUser {
  final String id;
  final String name;
  final String username;
  final String phone;
  final String role; // 'admin' | 'manager' | 'staff'
  final String status; // 'active' | 'inactive'
  final DateTime? lastLoginAt;

  AppUser({
    required this.id,
    required this.name,
    required this.username,
    required this.phone,
    required this.role,
    required this.status,
    this.lastLoginAt,
  });

  bool get isAdmin => role == 'admin';
  bool get isManager => role == 'manager';
  bool get isStaff => role == 'staff';

  // Centralized permission helpers so screens and widgets don't re-derive
  // role logic in multiple places. The backend independently enforces all
  // of these — this is purely for UI convenience (hide, don't just disable).
  bool get canViewCreditHistory => isAdmin || isManager;
  bool get canManageTables => isAdmin || isManager;
  bool get canManageRoles => isAdmin;
  bool get canViewStaffPerformance => isAdmin;
  bool get canViewDashboard => isAdmin || isManager;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    // Mongo/Mongoose normally serializes _id as a string, but accepting an
    // ObjectId-like value here makes login/session restore resilient to older
    // or differently serialized API responses instead of throwing a type
    // error that gets surfaced as a generic login failure.
    final rawId = json['_id'] ?? json['id'];
    final id = rawId == null ? '' : rawId.toString();
    if (id.isEmpty) {
      throw const FormatException('Login response did not contain a user id.');
    }

    final rawLastLogin = json['lastLoginAt'];
    DateTime? lastLoginAt;
    if (rawLastLogin is String) {
      lastLoginAt = DateTime.tryParse(rawLastLogin);
    } else if (rawLastLogin != null) {
      lastLoginAt = DateTime.tryParse(rawLastLogin.toString());
    }

    return AppUser(
      id: id,
      name: json['name']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      role: json['role']?.toString() ?? 'staff',
      status: json['status']?.toString() ?? 'active',
      lastLoginAt: lastLoginAt,
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'name': name,
        'username': username,
        'phone': phone,
        'role': role,
        'status': status,
      };
}
