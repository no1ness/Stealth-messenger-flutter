import 'package:flutter_secure_storage_x/flutter_secure_storage_x.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

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
