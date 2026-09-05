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
    return AppUser(
      id: json['_id'] as String,
      name: json['name'] as String? ?? '',
      username: json['username'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: json['role'] as String? ?? 'staff',
      status: json['status'] as String? ?? 'active',
      lastLoginAt: json['lastLoginAt'] != null ? DateTime.tryParse(json['lastLoginAt']) : null,
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
