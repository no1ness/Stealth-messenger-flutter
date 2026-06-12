import 'dart:js_interop';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

@JS('window.stealthCrypto')
external JSObject? get _stealthCrypto;

@JS('window.stealthCrypto.encrypt')
external JSPromise _jsEncrypt(JSString data);

@JS('window.stealthCrypto.decrypt')
external JSPromise _jsDecrypt(JSString data);

/// Безопасное Web-хранилище (IndexedDB + Web Crypto API).
///
/// Логика:
/// 1. Создаётся неэкспортируемый (extractable: false) AES-GCM ключ.
/// 2. Ключ навсегда сохраняется в браузере через IndexedDB.
/// 3. Любой XSS-скрипт не сможет украсть (экспортировать) этот ключ.
/// 4. Приватные E2E-ключи приложения шифруются этим WebCrypto ключом, и в
///    SharedPreferences попадает только нечитаемый шифротекст.
class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;

  bool _initialized = false;
  SharedPreferences? _prefs;

  StorageService._internal();

  Future<void> init() async {
    if (_initialized) return;
    _prefs ??= await SharedPreferences.getInstance();

    // Внедряем JS-скрипт с логикой Web Crypto API, если он ещё не внедрён
    if (_stealthCrypto == null) {
      final script =
          web.document.createElement('script') as web.HTMLScriptElement;
      script.text = r'''
        window.stealthCrypto = (function() {
          const DB_NAME = 'stealth_crypto_db';
          const STORE_NAME = 'keys';
          
          function openDB() {
            return new Promise((resolve, reject) => {
              const req = window.indexedDB.open(DB_NAME, 1);
              req.onupgradeneeded = e => req.result.createObjectStore(STORE_NAME);
              req.onsuccess = () => resolve(req.result);
              req.onerror = () => reject(req.error);
            });
          }
          
          async function getKey() {
            const db = await openDB();
            return new Promise((resolve, reject) => {
              const tx = db.transaction(STORE_NAME, 'readonly');
              const req = tx.objectStore(STORE_NAME).get('masterKey');
              req.onsuccess = async () => {
                if (req.result) {
                  resolve(req.result);
                } else {
                  // Генерируем ключ, который ЗАПРЕЩЕНО экспортировать
                  const key = await window.crypto.subtle.generateKey(
                    { name: 'AES-GCM', length: 256 },
                    false, // extractable = false (Защита от кражи через XSS)
                    ['encrypt', 'decrypt']
                  );
                  const tx2 = db.transaction(STORE_NAME, 'readwrite');
                  tx2.objectStore(STORE_NAME).put(key, 'masterKey');
                  tx2.oncomplete = () => resolve(key);
                }
              };
              req.onerror = () => reject(req.error);
            });
          }
          
          function buf2hex(buffer) {
            return [...new Uint8Array(buffer)].map(x => x.toString(16).padStart(2, '0')).join('');
          }
          
          function hex2buf(hexString) {
            const matches = hexString.match(/.{1,2}/g);
            if (!matches) return new Uint8Array(0);
            return new Uint8Array(matches.map(byte => parseInt(byte, 16)));
          }
          
          return {
            async encrypt(text) {
              const key = await getKey();
              const iv = window.crypto.getRandomValues(new Uint8Array(12));
              const encoded = new TextEncoder().encode(text);
              const cipher = await window.crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, encoded);
              return buf2hex(iv) + buf2hex(cipher);
            },
            async decrypt(hexStr) {
              const key = await getKey();
              const iv = hex2buf(hexStr.slice(0, 24));
              const cipher = hex2buf(hexStr.slice(24));
              const decoded = await window.crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, cipher);
              return new TextDecoder().decode(decoded);
            }
          };
        })();
      ''';
      web.document.head!.appendChild(script);
    }
    _initialized = true;
  }

  Future<String?> read(String key) async {
    await init();
    final encrypted = _prefs?.getString(key);
    if (encrypted == null || encrypted.isEmpty) return null;

    // Пытаемся расшифровать. Если ошибка (например, ключ удалился), возвращаем null
    try {
      final promise = _jsDecrypt(encrypted.toJS);
      final decrypted = await promise.toDart as JSString;
      return decrypted.toDart;
    } catch (e) {
      return null;
    }
  }

  Future<void> write(String key, String value) async {
    await init();
    final promise = _jsEncrypt(value.toJS);
    final encrypted = await promise.toDart as JSString;
    await _prefs?.setString(key, encrypted.toDart);
  }

  Future<void> delete(String key) async {
    await init();
    await _prefs?.remove(key);
  }

  Future<void> deleteAll() async {
    await init();
    // Мы очищаем SharedPreferences, но ключ в IndexedDB остается.
    // При следующей записи он просто будет шифровать данные старым ключом.
    await _prefs?.clear();
  }
}
