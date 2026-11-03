import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Named text files in the app's private folder. A write goes to a temporary
/// file first and replaces the old one in a single step, so a phone dying
/// mid-write can never leave a half-written list of unsynced bills.
class BlobStore {
  Directory? _dir;

  Future<Directory> _folder() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/offline');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<String?> read(String name) async {
    final file = File('${(await _folder()).path}/$name');
    return await file.exists() ? file.readAsString() : null;
  }

  Future<void> write(String name, String value) async {
    final folder = await _folder();
    final temp = File('${folder.path}/$name.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await temp.writeAsString(value, flush: true);
    await temp.rename('${folder.path}/$name');
  }

  Future<void> delete(String name) async {
    final file = File('${(await _folder()).path}/$name');
    if (await file.exists()) await file.delete();
  }
}
