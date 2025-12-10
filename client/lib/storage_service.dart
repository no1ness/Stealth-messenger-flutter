import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Универсальный сервис хранения для Web и Mobile
/// На Web использует SharedPreferences (localStorage)
/// На Mobile использует FlutterSecureStorage
class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  SharedPreferences? _prefs;

  Future<void> init() async {
    if (kIsWeb) {
      _prefs = await SharedPreferences.getInstance();
    }
  }

  Future<String?> read(String key) async {
    if (kIsWeb) {
      await init();
      return _prefs?.getString(key);
    } else {
      return await _secureStorage.read(key: key);
    }
  }

  Future<void> write(String key, String value) async {
    if (kIsWeb) {
      await init();
      await _prefs?.setString(key, value);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  Future<void> delete(String key) async {
    if (kIsWeb) {
      await init();
      await _prefs?.remove(key);
    } else {
      await _secureStorage.delete(key: key);
    }
  }

  Future<void> deleteAll() async {
    if (kIsWeb) {
      await init();
      await _prefs?.clear();
    } else {
      await _secureStorage.deleteAll();
    }
  }
}
