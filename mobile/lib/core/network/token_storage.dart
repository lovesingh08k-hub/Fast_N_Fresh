import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps flutter_secure_storage for JWT persistence, so sessions survive
/// app restarts ("remember session") without storing tokens in plaintext.
///
/// Reads never throw. The encrypted values can become undecryptable — most
/// often after Android restores app data from a backup or a reinstall with
/// a different signing key, because the Keystore key that encrypted them is
/// never restored. Every API request reads the token, so an exception here
/// would make every request (including login) fail. Instead, unreadable
/// storage is wiped and treated as "signed out".
class TokenStorage {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
    // The data-protection keychain needs a paid Apple developer team and a
    // keychain-sharing entitlement; the login keychain works for any build.
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );
  static const _tokenKey = 'fnf_auth_token';
  static const _userKey = 'fnf_auth_user';
  static const _sessionKey = 'fnf_business_session';

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);
  Future<String?> readToken() => _safeRead(_tokenKey);

  Future<void> saveUserJson(String json) => _storage.write(key: _userKey, value: json);
  Future<String?> readUserJson() => _safeRead(_userKey);

  Future<void> saveSessionJson(String json) => _storage.write(key: _sessionKey, value: json);
  Future<String?> readSessionJson() => _safeRead(_sessionKey);

  Future<void> clear() async {
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
      await _storage.delete(key: _sessionKey);
    } catch (_) {
      await _wipe();
    }
  }

  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      await _wipe();
      return null;
    }
  }

  Future<void> _wipe() async {
    try {
      await _storage.deleteAll();
    } catch (_) {
      // Nothing more can be done; callers already treat this as signed out.
    }
  }
}
