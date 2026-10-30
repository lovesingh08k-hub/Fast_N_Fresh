import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/network/dio_client.dart';
import '../core/network/token_storage.dart';
import '../core/network/api_exception.dart';
import '../models/business_session.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';

/// [licenceInactive]: logged in, but the business's subscription is
/// suspended or expired, so the app shows a blocking screen.
enum AuthStatus { unknown, authenticated, unauthenticated, licenceInactive }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  AuthStatus status = AuthStatus.unknown;
  AppUser? currentUser;
  String? errorMessage;

  /// Business, outlets and current outlet (null on a single-cafe server).
  BusinessSession? session;

  /// Why the business is blocked, when [status] is licenceInactive.
  String? licenceMessage;
  bool isLoading = false;

  bool _restoreInProgress = false;
  bool _resumeCheckInProgress = false;
  bool _logoutInProgress = false;

  bool get isAdmin => currentUser?.isAdmin ?? false;

  OutletInfo? get currentOutlet => session?.currentOutlet;

  /// Changes whenever the user logs in or switches outlet, so screens
  /// holding outlet data can be rebuilt from scratch.
  String get sessionKey => '${currentUser?.id}:${session?.code}:${session?.currentOutletCode}';

  void _applySession(BusinessSession? value) {
    session = value;
    DioClient.instance.outletCode = value?.currentOutletCode;
  }

  Future<void> _saveSession() async {
    final value = session;
    if (value == null) return;
    await TokenStorage.instance.saveSessionJson(jsonEncode(value.toJson()));
  }

  /// Switches the app to another outlet of the business.
  Future<void> switchOutlet(String outletCode) async {
    final value = session;
    if (value == null || value.currentOutletCode == outletCode) return;
    _applySession(value.withOutlet(outletCode));
    await _saveSession();
    notifyListeners();
  }

  /// Called by the network layer when the server says the subscription is
  /// not active (suspended / expired / outlet turned off).
  void onLicenceInactive(String message) {
    if (status == AuthStatus.unauthenticated) return;
    licenceMessage = message;
    status = AuthStatus.licenceInactive;
    notifyListeners();
  }

  /// "Try again" on the blocked screen: re-checks the session.
  Future<void> recheckLicence() async {
    try {
      await _validateServerSession();
      licenceMessage = null;
    } on ApiException catch (e) {
      if (e.statusCode == 401) await _performLogout();
    } catch (_) {}
  }

  /// Restores the cached session during application startup.
  ///
  /// A cached user is shown immediately when valid local session data exists.
  /// The server session is then checked in the background.
  Future<void> restoreSession() async {
    if (_restoreInProgress) return;

    _restoreInProgress = true;

    try {
      await _restoreSessionInner().timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          throw TimeoutException('Session restore timed out.');
        },
      );
    } catch (_) {
      if (status == AuthStatus.unknown) {
        status = AuthStatus.unauthenticated;
        notifyListeners();
      }
    } finally {
      _restoreInProgress = false;
    }
  }

  Future<void> _restoreSessionInner() async {
    String? token;
    String? userJson;
    String? sessionJson;

    try {
      token = await TokenStorage.instance.readToken();
      userJson = await TokenStorage.instance.readUserJson();
      sessionJson = await TokenStorage.instance.readSessionJson();
    } catch (_) {
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    if (token == null ||
        token.trim().isEmpty ||
        userJson == null ||
        userJson.trim().isEmpty) {
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    try {
      final decoded = jsonDecode(userJson);

      if (decoded is! Map<String, dynamic>) {
        await TokenStorage.instance.clear();

        status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }

      currentUser = AppUser.fromJson(decoded);
      if (sessionJson != null && sessionJson.isNotEmpty) {
        final rawSession = jsonDecode(sessionJson);
        if (rawSession is Map<String, dynamic>) _applySession(BusinessSession.fromJson(rawSession));
      }

      // Show the cached authenticated state immediately.
      status = AuthStatus.authenticated;
      notifyListeners();

      // Verify the JWT against the current backend session.
      await _validateServerSession();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _performLogout();
      }

      // Network/temporary failures deliberately keep the cached session.
    } catch (_) {
      // A valid cached session should remain usable if the server
      // is temporarily unreachable.
    }
  }

  /// Checks the current session after the Android application returns
  /// from the background.
  ///
  /// Temporary network failures do NOT log the user out.
  /// A confirmed 401 does.
  Future<void> checkSessionOnResume() async {
    if (status != AuthStatus.authenticated) return;
    if (_resumeCheckInProgress) return;
    if (_logoutInProgress) return;

    _resumeCheckInProgress = true;

    try {
      await _validateServerSession();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _performLogout();
      }
      // Do not logout for timeout/offline/server errors.
    } catch (_) {
      // Keep the cached session on temporary failures.
    } finally {
      _resumeCheckInProgress = false;
    }
  }

  Future<void> _validateServerSession() async {
    final (freshUser, freshSession) =
        await _authService.getMe(keepOutlet: session?.currentOutletCode);

    currentUser = freshUser;
    if (freshSession != null) {
      _applySession(freshSession);
      await _saveSession();
    }

    await TokenStorage.instance.saveUserJson(
      jsonEncode(freshUser.toJson()),
    );

    if (status != AuthStatus.authenticated) {
      status = AuthStatus.authenticated;
    }

    notifyListeners();
  }

  Future<bool> login(String businessCode, String identifier, String password) async {
    if (isLoading) return false;

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final (token, user, newSession) =
          await _authService.login(businessCode, identifier, password);

      await TokenStorage.instance.saveToken(token);
      await TokenStorage.instance.saveUserJson(
        jsonEncode(user.toJson()),
      );
      _applySession(newSession);
      await _saveSession();

      currentUser = user;
      licenceMessage = null;
      status = AuthStatus.authenticated;
      isLoading = false;

      notifyListeners();
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      isLoading = false;

      notifyListeners();
      return false;
    } catch (_) {
      errorMessage = 'Unable to log in. Please try again.';
      isLoading = false;

      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _performLogout();
  }

  /// Used when the backend confirms that the current JWT is invalid.
  Future<void> forceLogout() async {
    await _performLogout();
  }

  Future<void> _performLogout() async {
    if (_logoutInProgress) return;

    _logoutInProgress = true;

    try {
      // Must happen before clearing the stored auth token below -- the
      // unregister call needs to be authenticated as this user so the
      // backend knows which token to remove.
      await PushNotificationService.instance.unregisterDeviceToken();
    } catch (_) {
      // Best-effort; never block logout over this.
    }

    try {
      await TokenStorage.instance.clear();
    } catch (_) {
      // Continue clearing the in-memory session even if secure storage
      // temporarily fails.
    }

    currentUser = null;
    _applySession(null);
    licenceMessage = null;
    status = AuthStatus.unauthenticated;
    errorMessage = null;

    notifyListeners();

    _logoutInProgress = false;
  }
}