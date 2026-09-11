import 'package:flutter/foundation.dart';

/// TEMPORARY diagnostic logging for the "blank POS / no menu items"
/// investigation.
///
/// Traces the exact pipeline described in the debugging brief:
///   channel selected -> POS screen initialized -> fetch started ->
///   request URL -> response status -> raw product count -> parsed
///   product count -> filtered/displayed product count -> any error.
///
/// This is intentionally centralized behind one flag and one tag so it is
/// trivial to disable or remove entirely once the real device/APK log has
/// pinpointed the root cause:
///   - Flip [kPosDebugLogging] to false to silence it instantly.
///   - Or grep the codebase for `posLog(` and delete every call site plus
///     this file.
///
/// Never pass tokens, passwords, or secrets to [posLog] — only request
/// paths/params, counts, and error messages.
const bool kPosDebugLogging = true;

void posLog(String message) {
  if (!kPosDebugLogging) return;
  debugPrint('[POS] $message');
}
