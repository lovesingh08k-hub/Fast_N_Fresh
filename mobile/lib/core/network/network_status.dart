import 'package:flutter/foundation.dart';

/// Broadcasts whether the app is currently in the middle of an automatic
/// retry cycle against a slow/waking backend (e.g. a Render free-tier
/// cold start), so any screen can show a "Waking up the server..." style
/// message without each screen having to know about Dio/retry internals.
///
/// This is populated exclusively by [DioClient]'s retry logic and is
/// read-only from the UI side. It is intentionally separate from
/// [ConnectivityProvider]: that tracks the *device's* network state
/// (airplane mode, Wi-Fi off, etc.), while this tracks whether requests to
/// *our backend* are currently failing and being retried, which is the
/// situation a sleeping Render instance produces (the device has perfectly
/// good internet; the backend just hasn't woken up yet).
class NetworkStatus extends ChangeNotifier {
  NetworkStatus._();

  static final NetworkStatus instance = NetworkStatus._();

  bool isRetrying = false;
  int attempt = 0;
  int maxAttempts = 0;

  /// Called by the retry interceptor right before it waits and re-sends a
  /// failed request.
  void reportRetrying({required int attempt, required int maxAttempts}) {
    isRetrying = true;
    this.attempt = attempt;
    this.maxAttempts = maxAttempts;
    notifyListeners();
  }

  /// Called by the retry interceptor when a retried request finally
  /// succeeds.
  void reportRecovered() {
    if (!isRetrying && attempt == 0) return;
    isRetrying = false;
    attempt = 0;
    maxAttempts = 0;
    notifyListeners();
  }

  /// Called by the retry interceptor when retries are exhausted (or the
  /// error wasn't retryable to begin with) so any "waking up" indicator
  /// clears and the screen's own error/retry UI can take over.
  void reportGaveUp() {
    if (!isRetrying) return;
    isRetrying = false;
    notifyListeners();
  }
}
