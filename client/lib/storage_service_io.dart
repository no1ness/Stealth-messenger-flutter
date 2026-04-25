import 'package:flutter_secure_storage_x/flutter_secure_storage_x.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  // `resetOnError: true` makes the Android backend wipe EncryptedSharedPreferences
  // instead of throwing `BAD_DECRYPT` when the Keystore master key is unusable
  // (e.g. after reinstalling with a different signing key). Without this, even
  // `deleteAll()` fails because the plugin still tries to decrypt the master
  // key first.
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );

  Future<void> init() async {
    // The storage plugin itself is wasm-safe, so init is a no-op here.
  }

  Future<String?> read(String key) async {
    return _secureStorage.read(key: key);
  }

  Future<void> write(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  Future<void> delete(String key) async {
    await _secureStorage.delete(key: key);
  }

  Future<void> deleteAll() async {
    await _secureStorage.deleteAll();
  }
}
