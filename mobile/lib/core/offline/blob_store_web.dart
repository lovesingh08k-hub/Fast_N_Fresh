import 'package:shared_preferences/shared_preferences.dart';

/// Named text values in the browser's storage.
class BlobStore {
  static const _prefix = 'offline.';

  Future<String?> read(String name) async => (await SharedPreferences.getInstance()).getString('$_prefix$name');

  Future<void> write(String name, String value) async {
    await (await SharedPreferences.getInstance()).setString('$_prefix$name', value);
  }

  Future<void> delete(String name) async {
    await (await SharedPreferences.getInstance()).remove('$_prefix$name');
  }
}
