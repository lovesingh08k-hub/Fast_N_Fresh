import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';
import '../models/user.dart';
import '../models/dashboard_models.dart';
import '../models/customer.dart';
import '../models/misc_models.dart';

class StaffService {
  final Dio _dio = DioClient.instance.dio;

  Future<List<AppUser>> list() async {
    try {
      final res = await _dio.get('/staff');
      final list = res.data['data'] as List<dynamic>;
      return list.map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<StaffPerformance> getDetail(String id) async {
    try {
      final res = await _dio.get('/staff/$id');
      return StaffPerformance.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<AppUser> create({required String name, required String phone, required String username, required String password}) async {
    try {
      final res = await _dio.post('/staff', data: {'name': name, 'phone': phone, 'username': username, 'password': password});
      return AppUser.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<AppUser> update(String id, Map<String, dynamic> body) async {
    try {
      final res = await _dio.put('/staff/$id', data: body);
      return AppUser.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<void> resetPassword(String id, String newPassword) async {
    try {
      await _dio.post('/staff/$id/reset-password', data: {'newPassword': newPassword});
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}

class CreditService {
  final Dio _dio = DioClient.instance.dio;

  Future<(double totalOutstanding, List<Customer> customers)> getOverview() async {
    try {
      final res = await _dio.get('/credits');
      final data = res.data['data'] as Map<String, dynamic>;
      final customers = (data['customers'] as List<dynamic>).map((e) => Customer.fromJson(e as Map<String, dynamic>)).toList();
      return ((data['totalOutstanding'] as num?)?.toDouble() ?? 0, customers);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Directly registers a new UDHAR/credit transaction for a customer, not
  /// tied to a POS bill. This is the ONE credit action available to staff —
  /// they can give credit but (per role rules, enforced server-side) cannot
  /// view credit history/outstanding reports.
  Future<Customer> grantCredit({
    required String customerId,
    required double amount,
    String? note,
    String? clientRequestId,
  }) async {
    try {
      final res = await _dio.post('/credits/grant', data: {
        'customerId': customerId,
        'amount': amount,
        if (note != null && note.isNotEmpty) 'note': note,
        if (clientRequestId != null && clientRequestId.isNotEmpty)
          'clientRequestId': clientRequestId,
      });
      final data = res.data['data'] as Map<String, dynamic>;
      return Customer.fromJson(data['customer'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}

class UserService {
  final Dio _dio = DioClient.instance.dio;

  /// Admin-only: full user directory (staff, manager, admin).
  Future<List<AppUser>> list({String? role}) async {
    try {
      final res = await _dio.get('/users', queryParameters: {if (role != null) 'role': role});
      final list = res.data['data'] as List<dynamic>;
      return list.map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<AppUser> create({required String name, required String phone, required String username, required String password, required String role}) async {
    try {
      final res = await _dio.post('/users', data: {'name': name, 'phone': phone, 'username': username, 'password': password, 'role': role});
      return AppUser.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<AppUser> changeRole(String userId, String role) async {
    try {
      final res = await _dio.patch('/users/$userId/role', data: {'role': role});
      return AppUser.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<AppUser> updateAccount(String userId, {String? name, String? phone, String? username, String? password}) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (phone != null) data['phone'] = phone;
      if (username != null) data['username'] = username;
      if (password != null && password.isNotEmpty) data['password'] = password;
      final res = await _dio.patch('/users/$userId/account', data: data);
      return AppUser.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<AppUser> changeStatus(String userId, String status) async {
    try {
      final res = await _dio.patch('/users/$userId/status', data: {'status': status});
      return AppUser.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}

class AttendanceService {
  final Dio _dio = DioClient.instance.dio;

  /// Admin-only staff performance / customer-attendance summary.
  Future<List<dynamic>> getSummary({DateTime? from, DateTime? to}) async {
    try {
      final res = await _dio.get('/attendance/summary', queryParameters: {
        if (from != null) 'from': from.toIso8601String(),
        if (to != null) 'to': to.toIso8601String(),
      });
      return res.data['data'] as List<dynamic>;
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<Map<String, dynamic>> getStaffDetail(String staffId, {DateTime? from, DateTime? to}) async {
    try {
      final res = await _dio.get('/attendance/$staffId', queryParameters: {
        if (from != null) 'from': from.toIso8601String(),
        if (to != null) 'to': to.toIso8601String(),
      });
      return res.data['data'] as Map<String, dynamic>;
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}

class ExpenseService {
  final Dio _dio = DioClient.instance.dio;

  Future<List<Expense>> list({DateTime? from, DateTime? to, String? category}) async {
    try {
      final res = await _dio.get('/expenses', queryParameters: {
        if (from != null) 'from': from.toIso8601String(),
        if (to != null) 'to': to.toIso8601String(),
        if (category != null) 'category': category,
        'limit': 200,
      });
      final list = res.data['data'] as List<dynamic>;
      return list.map((e) => Expense.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<Expense> create(Map<String, dynamic> body) async {
    try {
      final res = await _dio.post('/expenses', data: body);
      return Expense.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete('/expenses/$id');
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}

class SettingsService {
  final Dio _dio = DioClient.instance.dio;

  Future<BusinessSettings> get() async {
    try {
      final res = await _dio.get('/settings');
      return BusinessSettings.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<BusinessSettings> update(Map<String, dynamic> body) async {
    try {
      final res = await _dio.put('/settings', data: body);
      return BusinessSettings.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}

class ReportService {
  final Dio _dio = DioClient.instance.dio;

  Future<Map<String, dynamic>> salesReport({DateTime? from, DateTime? to}) async {
    try {
      final res = await _dio.get('/reports/sales', queryParameters: _range(from, to));
      return res.data['data'] as Map<String, dynamic>;
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<List<dynamic>> productReport({DateTime? from, DateTime? to}) async {
    try {
      final res = await _dio.get('/reports/products', queryParameters: _range(from, to));
      return res.data['data'] as List<dynamic>;
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<List<dynamic>> staffReport({DateTime? from, DateTime? to}) async {
    try {
      final res = await _dio.get('/reports/staff', queryParameters: _range(from, to));
      return res.data['data'] as List<dynamic>;
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<Map<String, dynamic>> creditReport() async {
    try {
      final res = await _dio.get('/reports/credit');
      return res.data['data'] as Map<String, dynamic>;
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<Map<String, dynamic>> expenseReport({DateTime? from, DateTime? to}) async {
    try {
      final res = await _dio.get('/reports/expenses', queryParameters: _range(from, to));
      return res.data['data'] as Map<String, dynamic>;
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Map<String, dynamic> _range(DateTime? from, DateTime? to) => {
        if (from != null) 'from': from.toIso8601String(),
        if (to != null) 'to': to.toIso8601String(),
      };
}
