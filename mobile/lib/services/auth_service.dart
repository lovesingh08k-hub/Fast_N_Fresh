import 'dart:async';

import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';
import '../models/user.dart';

class AuthService {
  final Dio _dio = DioClient.instance.dio;

  Future<(String token, AppUser user)> login(
    String identifier,
    String password,
  ) async {
    // Render's free tier can cold-start. Login is safe to repeat because it
    // only authenticates the user and updates lastLoginAt. Retry only
    // transient transport/5xx failures; never retry 4xx credential errors.
    const retryDelays = [
      Duration(seconds: 2),
      Duration(seconds: 4),
    ];

    for (var attempt = 0; ; attempt++) {
      try {
        final res = await _dio.post(
          '/auth/login',
          data: {
            'identifier': identifier.trim(),
            'password': password,
          },
        );

        final body = res.data;
        if (body is! Map || body['data'] is! Map) {
          throw StateError('Invalid login response from server.');
        }

        final data = Map<String, dynamic>.from(body['data'] as Map);
        final token = data['token'];
        final rawUser = data['user'];

        if (token is! String || token.isEmpty || rawUser is! Map) {
          throw StateError('Invalid login response from server.');
        }

        final user = AppUser.fromJson(
          Map<String, dynamic>.from(rawUser),
        );

        return (token, user);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        final transient =
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError ||
            (status != null && status >= 500 && status < 600);

        if (!transient || attempt >= retryDelays.length) {
          throw DioClient.instance.mapError(e);
        }

        await Future.delayed(retryDelays[attempt]);
      } catch (e) {
        throw DioClient.instance.mapError(e);
      }
    }
  }

  Future<AppUser> getMe() async {
    try {
      final res = await _dio.get('/auth/me');
      return AppUser.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    try {
      await _dio.post('/auth/change-password', data: {'currentPassword': currentPassword, 'newPassword': newPassword});
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<void> logoutAllDevices() async {
    try {
      await _dio.post('/auth/logout-all');
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}
