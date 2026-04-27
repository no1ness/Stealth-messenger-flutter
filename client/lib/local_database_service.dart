import 'dart:async';
import 'dart:convert';
import 'package:idb_shim/idb_io.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:idb_shim/idb_browser.dart';
import 'package:cryptography/cryptography.dart';
import 'package:stealth/storage_service.dart';
import 'package:stealth/helpers/crypto_helper.dart';

class LocalDatabaseService {
  static const String dbName = 'stealth_local_v3.db';
  // Bumped to v2 to add the `synced` index on the messages store.
  static const int dbVersion = 2;

  static const String messagesStore = 'messages';
  static const String chatsStore = 'chats';

  IdbFactory get _factory => kIsWeb ? idbFactoryBrowser : idbFactorySembastIo;
  Database? _db;
  SecretKey? _dbKey;

  Future<void> _ensureInitialized() async {
    if (_db != null) return;

    final factory = _factory;
    final path = kIsWeb
        ? dbName
        : join((await getApplicationDocumentsDirectory()).path, dbName);

    _db =
        await factory.open(path, version: dbVersion, onUpgradeNeeded: (event) {
      final db = event.database;
      if (!db.objectStoreNames.contains(messagesStore)) {
        final store = db.createObjectStore(messagesStore, autoIncrement: true);
        store.createIndex('chatId', 'chatId');
        store.createIndex('synced', 'synced');
      } else if (event.oldVersion < 2) {
        // Upgrade existing store: add synced index if missing
        final txn = event.transaction;
        final store = txn.objectStore(messagesStore);
        if (!store.indexNames.contains('synced')) {
          store.createIndex('synced', 'synced');
        }
      }
      if (!db.objectStoreNames.contains(chatsStore)) {
        db.createObjectStore(chatsStore, keyPath: 'id');
      }
    });

    // Initialize encryption key
    final storage = StorageService();
    String? b64Key = await storage.read('local_db_key');
    if (b64Key == null) {
      final key = await CryptoHelper.generateSymmetricKey();
      final bytes = await CryptoHelper.exportKey(key);
      await storage.write('local_db_key', base64Encode(bytes));
      _dbKey = key;
    } else {
      _dbKey = await CryptoHelper.importKey(base64Decode(b64Key));
    }
  }

  /// Saves a message to the local DB.
  /// [synced] — true if already persisted to Supabase, false if written offline.
  Future<Object?> saveMessage(
    Map<String, dynamic> message, {
    bool synced = true,
  }) async {
    await _ensureInitialized();
    final encrypted =
        await CryptoHelper.encryptData(jsonEncode(message), _dbKey!);

    final txn = _db!.transaction(messagesStore, idbModeReadWrite);
    final store = txn.objectStore(messagesStore);
    final localKey = await store.put({
      'payload': encrypted,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'chatId': message['chat_id'],
      'messageId': message['id']?.toString(),
      'synced': synced ? 1 : 0,
    });
    await txn.completed;
    return localKey;
  }

  /// Returns all messages for [chatId], decrypted.
  Future<List<Map<String, dynamic>>> getMessages(String chatId) async {
    await _ensureInitialized();
    final txn = _db!.transaction(messagesStore, idbModeReadOnly);
    final store = txn.objectStore(messagesStore);

    final messages = <Map<String, dynamic>>[];
    final cursor = store.openCursor(autoAdvance: true);

    await for (final cv in cursor) {
      final val = cv.value as Map;
      if (val['chatId'] == chatId) {
        final decrypted =
            await CryptoHelper.decryptData(val['payload'] as String, _dbKey!);
        messages.add(jsonDecode(decrypted) as Map<String, dynamic>);
      }
    }

    return messages;
  }

  /// Returns messages that were written while offline (synced = 0).
  Future<List<Map<String, dynamic>>> getPendingSyncMessages() async {
    await _ensureInitialized();
    final txn = _db!.transaction(messagesStore, idbModeReadOnly);
    final store = txn.objectStore(messagesStore);

    final pending = <({Object key, Map<String, dynamic> message})>[];
    final cursor = store.openCursor(autoAdvance: true);

    await for (final cv in cursor) {
      final val = cv.value as Map;
      if ((val['synced'] as int? ?? 1) == 0) {
        final decrypted =
            await CryptoHelper.decryptData(val['payload'] as String, _dbKey!);
        final message = jsonDecode(decrypted) as Map<String, dynamic>;
        message['_local_key'] = cv.key;
        pending.add((
          key: cv.key,
          message: message,
        ));
      }
    }

    return pending.map((e) => e.message).toList();
  }

  Future<void> markMessageSyncedByLocalKey(Object localKey) async {
    await _ensureInitialized();
    final txn = _db!.transaction(messagesStore, idbModeReadWrite);
    final store = txn.objectStore(messagesStore);

    final raw = await store.getObject(localKey);
    if (raw is Map) {
      final val = Map<String, dynamic>.from(raw);
      val['synced'] = 1;
      await store.put(val, localKey);
    }

    await txn.completed;
  }

  /// Marks a locally stored message as synced with Supabase.
  Future<void> markMessageSynced(String messageId) async {
    await _ensureInitialized();
    final txn = _db!.transaction(messagesStore, idbModeReadWrite);
    final store = txn.objectStore(messagesStore);

    // Walk all records to find the matching messageId
    final cursor = store.openCursor(autoAdvance: false);
    await for (final cv in cursor) {
      final val = Map<String, dynamic>.from(cv.value as Map);
      if (val['messageId'] == messageId && (val['synced'] as int? ?? 1) == 0) {
        val['synced'] = 1;
        await cv.update(val);
        break;
      }
      cv.next();
    }

    await txn.completed;
  }

  Future<void> saveChat(Map<String, dynamic> chat) async {
    await _ensureInitialized();
    final txn = _db!.transaction(chatsStore, idbModeReadWrite);
    final store = txn.objectStore(chatsStore);
    await store.put(chat);
    await txn.completed;
  }

  Future<List<Map<String, dynamic>>> getChats() async {
    await _ensureInitialized();
    final txn = _db!.transaction(chatsStore, idbModeReadOnly);
    final store = txn.objectStore(chatsStore);
    final list = await store.getAll();
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>?> getChatById(String chatId) async {
    await _ensureInitialized();
    final txn = _db!.transaction(chatsStore, idbModeReadOnly);
    final store = txn.objectStore(chatsStore);
    final val = await store.getObject(chatId);
    if (val != null) {
      return Map<String, dynamic>.from(val as Map);
    }
    return null;
  }
}
