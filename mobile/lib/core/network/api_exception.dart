/// Broad categories of API failure, used by screens to decide how to
/// react (e.g. show a "waking up" message vs a "log in again" prompt)
/// without string-matching on [ApiException.message].
enum ApiErrorType {
  /// Request timed out (connect/send/receive). The most common shape of
  /// a sleeping backend: the client gets no response within the
  /// configured timeout because the server hasn't finished booting yet.
  timeout,

  /// No route to the server at all (DNS failure, connection refused,
  /// device offline). Distinct from [timeout]: here the request never
  /// really got underway.
  noInternet,

  /// The server responded, but with a temporary server-side error
  /// (5xx) — also typical of a backend that is still starting up behind
  /// a proxy that returns a gateway error until the app is ready.
  serverUnavailable,

  /// 401 — the session is invalid/expired.
  unauthorized,

  /// 403 — authenticated, but not allowed to do this.
  forbidden,

  /// 404 — the resource doesn't exist.
  notFound,

  /// 400/422 — the request was rejected for a business/validation reason.
  /// These are permanent for the given input and should never be retried
  /// automatically.
  validation,

  /// The request was cancelled (e.g. screen disposed mid-request).
  cancelled,

  /// Anything else.
  unknown,
}

/// Uniform exception thrown by services when an API call fails, carrying a
/// human-readable message (taken from the backend's `message` field when
/// available) so screens can show it directly, plus a coarse [type] for
/// screens/widgets that want to branch on the kind of failure (e.g. to
/// avoid retrying validation errors, or to treat 401 specially).
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final List<dynamic>? details;
  final ApiErrorType type;

  ApiException(
    this.message, {
    this.statusCode,
    this.details,
    this.type = ApiErrorType.unknown,
  });

  /// True for failures that are likely to resolve on their own shortly
  /// (timeouts, connectivity issues, temporary 5xx) — i.e. the kind of
  /// error a backend cold start produces. Screens can use this to decide
  /// whether "Reconnecting…" copy is more appropriate than a hard error.
  bool get isTransient =>
      type == ApiErrorType.timeout ||
      type == ApiErrorType.noInternet ||
      type == ApiErrorType.serverUnavailable;

  @override
  String toString() => message;
}
