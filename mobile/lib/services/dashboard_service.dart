import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';
import '../models/dashboard_models.dart';

class DashboardService {
  final Dio _dio = DioClient.instance.dio;

  Future<DashboardData> getDashboard() async {
    try {
      final res = await _dio.get('/dashboard');
      return DashboardData.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<SalesOverview> getSalesOverview() async {
    try {
      final res = await _dio.get('/dashboard/sales-overview');
      return SalesOverview.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}
