import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';
import '../models/customer.dart';

class CustomerService {
  final Dio _dio = DioClient.instance.dio;

  Future<List<Customer>> list({String? search, bool? hasDue}) async {
    try {
      final res = await _dio.get('/customers', queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        if (hasDue == true) 'hasDue': 'true',
        'limit': 200,
      });
      final list = res.data['data'] as List<dynamic>;
      return list.map((e) => Customer.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<(Customer, List<CreditTransaction>)> getDetail(String id) async {
    try {
      final res = await _dio.get('/customers/$id');
      final data = res.data['data'] as Map<String, dynamic>;
      final customer = Customer.fromJson(data['customer'] as Map<String, dynamic>);
      final transactions =
          (data['transactions'] as List<dynamic>).map((e) => CreditTransaction.fromJson(e as Map<String, dynamic>)).toList();
      return (customer, transactions);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<Customer> create({required String name, required String phone, String? address, String? notes}) async {
    try {
      final res = await _dio.post('/customers', data: {
        'name': name,
        'phone': phone,
        if (address != null && address.isNotEmpty) 'address': address,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      });
      return Customer.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<Customer> update(String id, Map<String, dynamic> body) async {
    try {
      final res = await _dio.put('/customers/$id', data: body);
      return Customer.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete('/customers/$id');
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// [clientRequestId] should be a UUID generated once per payment attempt
  /// by the caller and reused unchanged on retry, so the backend can
  /// collapse a duplicate submission instead of deducting the customer's
  /// balance twice (see customerController.recordPayment).
  Future<Customer> recordPayment(
    String id, {
    required double amount,
    required String method,
    String? note,
    String? clientRequestId,
  }) async {
    try {
      final res = await _dio.post('/customers/$id/payment', data: {
        'amount': amount,
        'method': method,
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
