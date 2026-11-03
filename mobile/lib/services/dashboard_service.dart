import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';
import '../core/offline/offline_engine.dart';
import '../models/dashboard_models.dart';

class DashboardService {
  final Dio _dio = DioClient.instance.dio;

  Future<DashboardData?> dashboardCached() async {
    final saved = await OfflineEngine.instance.peek('/dashboard');
    return saved == null ? null : DashboardData.fromJson(saved['data'] as Map<String, dynamic>);
  }

  Future<SalesOverview?> overviewCached() async {
    final saved = await OfflineEngine.instance.peek('/dashboard/sales-overview');
    return saved == null ? null : SalesOverview.fromJson(saved['data'] as Map<String, dynamic>);
  }

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
