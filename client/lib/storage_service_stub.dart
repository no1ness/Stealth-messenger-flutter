import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<String?> read(String key) async {
    await init();
    return _prefs?.getString(key);
  }

  Future<void> write(String key, String value) async {
    await init();
    await _prefs?.setString(key, value);
  }

  Future<void> delete(String key) async {
    await init();
    await _prefs?.remove(key);
  }

  Future<void> deleteAll() async {
    await init();
    await _prefs?.clear();
  }
}
