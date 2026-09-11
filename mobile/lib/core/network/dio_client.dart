import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'network_status.dart';
import 'token_storage.dart';

typedef OnUnauthorized = void Function();

class DioClient {
  DioClient._internal();

  static final DioClient instance = DioClient._internal();

  late final Dio dio = _build();

  OnUnauthorized? onUnauthorized;

  // ---------------------------------------------------------------------
  // RETRY CONFIGURATION
  //
  // Centralized retry-with-backoff for transient network failures, most
  // notably a sleeping Render free-tier backend waking back up. This is
  // implemented once here, at the Dio layer, so every screen/service that
  // goes through DioClient.instance.dio benefits automatically — nothing
  // screen-specific is required.
  //
  // Only safe (GET/HEAD) requests are auto-retried. Writes (POST/PUT/
  // PATCH/DELETE) are NEVER retried here, on purpose: a timed-out
  // "create order" or "record payment" call must not be silently
  // resubmitted by this layer. Where a write genuinely needs to survive a
  // timeout safely, that is handled explicitly and end-to-end with a
  // stable `clientRequestId` that the backend uses to de-duplicate (see
  // OrderService.createOrder / CustomerService.recordPayment) — retrying
  // those is a deliberate, opt-in action taken by the user (tapping
  // "Try Again"), not something this interceptor does behind the scenes.
  // ---------------------------------------------------------------------

  static const int maxRetryAttempts = 3;

  /// Delay before each retry attempt, in order. Attempt 1 is short
  /// (near-immediate), then backs off to ~2s, then ~4s, per attempt.
  static const List<Duration> _retryDelays = [
    Duration(milliseconds: 600),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  Dio _build() {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        sendTimeout: ApiConfig.sendTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await TokenStorage.instance.readToken();

          if (token != null && token.trim().isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';

            // Used by the error interceptor to determine whether
            // this request was authenticated.
            options.extra['hadAuthToken'] = true;
          } else {
            options.extra['hadAuthToken'] = false;
          }

          handler.next(options);
        },
        onError: (DioException e, handler) {
          // Fire-and-continue: the handler is always resolved/rejected
          // from inside _handleError itself (either after a successful
          // retry, or by forwarding the terminal error), so nothing else
          // needs to happen in this callback.
          unawaited(_handleError(dio, e, handler));
        },
      ),
    );

    return dio;
  }

  // ---------------------------------------------------------------------
  // ERROR / RETRY HANDLING
  // ---------------------------------------------------------------------

  Future<void> _handleError(
    Dio dio,
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // 401 detection runs on every failed attempt, retried or not — it is
    // a no-op unless the response actually is a 401, so it is safe to
    // check up front regardless of what happens next.
    _checkUnauthorized(err);

    final options = err.requestOptions;
    final attemptSoFar = (options.extra['retryAttempt'] as int?) ?? 0;

    final shouldRetry = attemptSoFar < maxRetryAttempts &&
        _isRetryableMethod(options) &&
        _isRetryableError(err);

    if (!shouldRetry) {
      NetworkStatus.instance.reportGaveUp();
      handler.next(err);
      return;
    }

    final nextAttempt = attemptSoFar + 1;
    options.extra['retryAttempt'] = nextAttempt;

    NetworkStatus.instance.reportRetrying(
      attempt: nextAttempt,
      maxAttempts: maxRetryAttempts,
    );

    final delay = _retryDelays[math.min(attemptSoFar, _retryDelays.length - 1)];
    await Future.delayed(delay);

    try {
      // Re-sends the SAME RequestOptions (including the freshly-read
      // Authorization header from the original attempt, and the updated
      // retryAttempt counter in `extra`). This goes back through the full
      // interceptor chain, including this same onError handler, so if it
      // fails again it will itself either retry further (bounded by the
      // shared, mutated `retryAttempt` counter above) or give up and
      // finalize its own attempt — either way this call below settles
      // once a final outcome (success or exhausted retries) is reached.
      final response = await dio.fetch<dynamic>(options);
      NetworkStatus.instance.reportRecovered();
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    } catch (_) {
      handler.next(err);
    }
  }

  void _checkUnauthorized(DioException e) {
    final statusCode = e.response?.statusCode;

    if (statusCode == 401) {
      final hadAuthToken = e.requestOptions.extra['hadAuthToken'] == true;

      final path = e.requestOptions.path.toLowerCase();

      final isLoginRequest =
          path.endsWith('/auth/login') || path == '/auth/login';

      final isChangePasswordRequest =
          path.endsWith('/auth/change-password') ||
          path == '/auth/change-password';

      /*
       * Only treat 401 as an expired/invalid session when:
       *
       * 1. The request actually had an authentication token.
       * 2. It was not the login endpoint.
       * 3. It was not the change-password endpoint.
       *
       * This prevents normal authentication/validation errors
       * from unexpectedly logging the user out.
       */
      if (hadAuthToken && !isLoginRequest && !isChangePasswordRequest) {
        onUnauthorized?.call();
      }
    }
  }

  /// Only GET/HEAD are auto-retried. See the class-level comment above
  /// for why writes are deliberately excluded from automatic retry.
  bool _isRetryableMethod(RequestOptions options) {
    final method = options.method.toUpperCase();
    return method == 'GET' || method == 'HEAD';
  }

  /// Only genuinely transient failures are retried: timeouts, connection
  /// errors (both consistent with a backend that hasn't finished waking
  /// up yet), and temporary 5xx server responses. 4xx errors (including
  /// 401/403/404/validation) are never retried — they are not transient
  /// and endless-retrying them would be both wrong and, for 401/403,
  /// explicitly against requirement.
  bool _isRetryableError(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;

      case DioExceptionType.badResponse:
        final status = err.response?.statusCode;
        return status != null && status >= 500 && status < 600;

      default:
        return false;
    }
  }

  // ---------------------------------------------------------------------
  // ERROR MAPPING
  // ---------------------------------------------------------------------

  ApiException mapError(Object error) {
    if (error is DioException) {
      final response = error.response;
      final statusCode = response?.statusCode;

      if (response != null && response.data is Map) {
        final data = response.data as Map;

        final message =
            data['message']?.toString() ?? 'Something went wrong.';

        final rawDetails = data['details'];

        final details = rawDetails is List<dynamic> ? rawDetails : null;

        return ApiException(
          message,
          statusCode: statusCode,
          details: details,
          type: _typeForStatus(statusCode),
        );
      }

      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return ApiException(
            'The server is taking longer than usual to respond. It may be waking up — please wait a moment and try again.',
            type: ApiErrorType.timeout,
          );

        case DioExceptionType.connectionError:
          return ApiException(
            'No internet connection. Please check your network and retry.',
            type: ApiErrorType.noInternet,
          );

        case DioExceptionType.badCertificate:
          return ApiException(
            'Secure connection failed. Please try again later.',
          );

        case DioExceptionType.cancel:
          return ApiException(
            'Request was cancelled.',
            type: ApiErrorType.cancelled,
          );

        case DioExceptionType.badResponse:
          return ApiException(
            'Server returned an unexpected response.',
            statusCode: statusCode,
            type: _typeForStatus(statusCode),
          );

        default:
          return ApiException(
            'Something went wrong. Please try again.',
          );
      }
    }

    return ApiException('Unexpected error: $error');
  }

  ApiErrorType _typeForStatus(int? statusCode) {
    if (statusCode == null) return ApiErrorType.unknown;
    if (statusCode == 401) return ApiErrorType.unauthorized;
    if (statusCode == 403) return ApiErrorType.forbidden;
    if (statusCode == 404) return ApiErrorType.notFound;
    if (statusCode == 400 || statusCode == 422) return ApiErrorType.validation;
    if (statusCode >= 500 && statusCode < 600) {
      return ApiErrorType.serverUnavailable;
    }
    return ApiErrorType.unknown;
  }
}
