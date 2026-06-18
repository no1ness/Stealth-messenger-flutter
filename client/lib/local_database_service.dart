import 'dart:async';
import 'dart:convert';
import 'package:idb_shim/idb_io.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:idb_shim/idb_browser.dart';
import 'package:cryptography/cryptography.dart';
import 'package:stealth/crypto/crypto_isolate_service.dart';
import 'package:stealth/storage_service.dart';
import 'package:stealth/helpers/crypto_helper.dart';

class LocalDatabaseService {
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._internal();

  static final LocalDatabaseService _instance =
      LocalDatabaseService._internal();

  static const String dbName = 'stealth_local_v3.db';
  // v6 (task #8 of client-hardening-followup): `deliveryStatus` index on
  // messagesStore for the pending-message worker. Schema is additive —
  // legacy rows without `deliveryStatus` read as `'sent'` (computed by
  // MessageService at read time).
  // v7: callsStore schema changed from autoIncrement to keyPath:'id' so that
  // deleteCall(id) uses the UUID string key instead of an auto-increment integer
  // (which never matched). Existing v6 DBs are migrated during upgrade.
  static const int dbVersion = 7;

  static const String messagesStore = 'messages';
  static const String chatsStore = 'chats';
  static const String contactsStore = 'contacts';
  static const String callsStore = 'calls';
  static const String attachmentsStore = 'attachments';

  IdbFactory get _factory => kIsWeb ? idbFactoryBrowser : idbFactorySembastIo;
  Database? _db;
  SecretKey? _dbKey;
  Future<void>? _initializing;

  Future<void> _ensureInitialized() {
    if (_db != null) return Future<void>.value();
    return _initializing ??= _openDatabase().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _openDatabase() async {
    if (_db != null) return;

    final factory = _factory;
    final path = kIsWeb
        ? dbName
        : join((await getApplicationDocumentsDirectory()).path, dbName);

        _db =
            await factory.open(path, version: dbVersion, onUpgradeNeeded: (event) async {
      final db = event.database;
      if (!db.objectStoreNames.contains(messagesStore)) {
        final store = db.createObjectStore(messagesStore, autoIncrement: true);
        store.createIndex('chatId', 'chatId');
        store.createIndex('synced', 'synced');
        store.createIndex('messageId', 'messageId');
        store.createIndex('deliveryStatus', 'deliveryStatus');
      } else {
        final txn = event.transaction;
        final store = txn.objectStore(messagesStore);
        if (event.oldVersion < 2) {
          if (!store.indexNames.contains('synced')) {
            store.createIndex('synced', 'synced');
          }
        }
        if (event.oldVersion < 3) {
          if (!store.indexNames.contains('messageId')) {
            store.createIndex('messageId', 'messageId');
          }
        }
        if (event.oldVersion < 6) {
          if (!store.indexNames.contains('deliveryStatus')) {
            store.createIndex('deliveryStatus', 'deliveryStatus');
          }
        }
      }
      if (!db.objectStoreNames.contains(chatsStore)) {
        db.createObjectStore(chatsStore, keyPath: 'id');
      }
      if (!db.objectStoreNames.contains(contactsStore)) {
        db.createObjectStore(contactsStore, keyPath: 'contact_user_id');
      }
      if (!db.objectStoreNames.contains(callsStore)) {
        final store = db.createObjectStore(callsStore, keyPath: 'id');
        store.createIndex('chatId', 'chatId');
      } else if (event.oldVersion < 7) {
        // v7 migration: recreate callsStore with keyPath:'id' instead of
        // autoIncrement so deleteCall(id) matches the UUID string key.
        final txn = event.transaction;
        final oldStore = txn.objectStore(callsStore);
        final allCalls = await oldStore.getAll();
        db.deleteObjectStore(callsStore);
        final newStore = db.createObjectStore(callsStore, keyPath: 'id');
        newStore.createIndex('chatId', 'chatId');
        for (final call in allCalls) {
          await newStore.put(call);
        }
      }
      if (!db.objectStoreNames.contains(attachmentsStore)) {
        final store = db.createObjectStore(attachmentsStore, keyPath: 'id');
        store.createIndex('chatId', 'chatId');
      } else if (event.oldVersion < 5) {
        final txn = event.transaction;
        final store = txn.objectStore(attachmentsStore);
        if (!store.indexNames.contains('chatId')) {
          store.createIndex('chatId', 'chatId');
        }
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
  /// [synced] is kept as a generic delivery marker for P2P/local import paths.
  Future<Object?> saveMessage(
    Map<String, dynamic> message, {
    bool synced = true,
    String? deliveryStatus,
  }) async {
    await _ensureInitialized();

    final messageId = message['id']?.toString();
    final txn = _db!.transaction(messagesStore, idbModeReadWrite);
    final store = txn.objectStore(messagesStore);

    // 1. Check if message already exists by messageId index
    if (messageId != null) {
      final index = store.index('messageId');
      final existingKey = await index.getKey(messageId);
      if (existingKey != null) {
        // Already exists; refresh the encrypted payload and delivery marker.
        final existing = await store.getObject(existingKey);
        if (existing is Map) {
          final val = Map<String, dynamic>.from(existing);
          final encrypted =
              await CryptoHelper.encryptData(jsonEncode(message), _dbKey!);
          val['payload'] = encrypted;
          val['timestamp'] = DateTime.now().millisecondsSinceEpoch;
          val['chatId'] = message['chat_id'];
          val['synced'] = synced ? 1 : (val['synced'] as int? ?? 1);
          // deliveryStatus is OUTGOING-only. When non-null, overwrite (the
          // caller knows it's a state transition); when null, preserve the
          // existing value if any (don't fabricate a status for incoming).
          if (deliveryStatus != null) {
            val['deliveryStatus'] = deliveryStatus;
          }
          await store.put(val, existingKey);
        }
        await txn.completed;
        return existingKey;
      }
    }

    // 2. Encrypt and save new message
    final encrypted =
        await CryptoHelper.encryptData(jsonEncode(message), _dbKey!);

    final localKey = await store.put({
      'payload': encrypted,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'chatId': message['chat_id'],
      'messageId': messageId,
      'synced': synced ? 1 : 0,
      // Top-level field — indexed for the pending-message worker.
      // Absent for incoming messages (UI must treat absence as no indicator).
      if (deliveryStatus != null) 'deliveryStatus': deliveryStatus,
    });
    await txn.completed;
    return localKey;
  }

  /// Updates the outgoing-message lifecycle marker without re-encrypting the
  /// payload. Used by the P2P retry worker and ACK handler (task #9).
  /// No-op if no message with this `messageId` exists (legitimately deleted).
  ///
  /// `lastRetryAt` lets the multi-tab anti-double-retry coordinator skip
  /// rows that another tab attempted within the last 30 s. Pass `null`
  /// for terminal transitions (markSent, markDelivered, markFailed).
  Future<void> updateMessageDeliveryStatus(
    String messageId,
    String newStatus, {
    DateTime? lastRetryAt,
  }) async {
    await _ensureInitialized();
    final txn = _db!.transaction(messagesStore, idbModeReadWrite);
    final store = txn.objectStore(messagesStore);
    final index = store.index('messageId');
    final existingKey = await index.getKey(messageId);
    if (existingKey == null) {
      await txn.completed;
      return;
    }
    final existing = await store.getObject(existingKey);
    if (existing is Map) {
      final val = Map<String, dynamic>.from(existing);
      val['deliveryStatus'] = newStatus;
      if (lastRetryAt != null) {
        val['lastRetryAttemptedAt'] = lastRetryAt.toIso8601String();
      }
      await store.put(val, existingKey);
    }
    await txn.completed;
  }

  /// Returns outgoing messages with `deliveryStatus == 'pending'` ordered by
  /// IDB insertion. Decrypts the payload and surfaces top-level retry
  /// coordination fields (`deliveryStatus`, `lastRetryAttemptedAt`) on the
  /// returned map.
  Future<List<Map<String, dynamic>>> getPendingMessages({int? limit}) async {
    await _ensureInitialized();
    final txn = _db!.transaction(messagesStore, idbModeReadOnly);
    final store = txn.objectStore(messagesStore);
    final index = store.index('deliveryStatus');

    final pending = <Map<String, dynamic>>[];
    final cursor = index.openCursor(key: 'pending', autoAdvance: true);
    var count = 0;
    await for (final cv in cursor) {
      if (limit != null && count >= limit) break;
      final val = cv.value as Map;
      final decrypted =
          await CryptoHelper.decryptData(val['payload'] as String, _dbKey!);
      final message = jsonDecode(decrypted) as Map<String, dynamic>;
      message['_local_key'] = cv.primaryKey;
      message['deliveryStatus'] = val['deliveryStatus'];
      if (val['lastRetryAttemptedAt'] != null) {
        message['lastRetryAttemptedAt'] = val['lastRetryAttemptedAt'];
      }
      pending.add(message);
      count += 1;
    }
    return pending;
  }

  /// Returns messages for [chatId], decrypted. When [limit] is set, stops
  /// after that many rows. Pass [offset] to skip that many initial rows
  /// (applied at the cursor level to avoid decrypting skipped rows).
  Future<List<Map<String, dynamic>>> getMessages(
    String chatId, {
    int? limit,
    int offset = 0,
  }) async {
    await _ensureInitialized();
    final txn = _db!.transaction(messagesStore, idbModeReadOnly);
    final store = txn.objectStore(messagesStore);
    final index = store.index('chatId');

    final rows = <Map<String, dynamic>>[];
    final cursor = index.openCursor(key: chatId, autoAdvance: true);
    var count = 0;
    var skipped = 0;

    await for (final cv in cursor) {
      if (skipped < offset) {
        skipped++;
        continue;
      }
      if (limit != null && count >= limit) break;
      rows.add(Map<String, dynamic>.from(cv.value as Map));
      count++;
    }

    if (rows.isEmpty) return [];

    final encryptedPayloads =
        rows.map((r) => r['payload'] as String).toList();
    final decryptedPayloads = await CryptoIsolateService.decryptBatch(
      encryptedPayloads: encryptedPayloads,
      key: _dbKey!,
    );

    final messages = <Map<String, dynamic>>[];
    for (var i = 0; i < rows.length; i++) {
      final message =
          jsonDecode(decryptedPayloads[i]) as Map<String, dynamic>;
      if (rows[i]['deliveryStatus'] != null) {
        message['deliveryStatus'] = rows[i]['deliveryStatus'];
      }
      messages.add(message);
    }
    return messages;
  }

  /// Returns only the last (most recently inserted) message for [chatId],
  /// decrypted. Avoids loading the full chat history.
  Future<Map<String, dynamic>?> getLastMessage(String chatId) async {
    await _ensureInitialized();
    final txn = _db!.transaction(messagesStore, idbModeReadOnly);
    final store = txn.objectStore(messagesStore);
    final index = store.index('chatId');

    final cursor =
        index.openCursor(key: chatId, direction: 'prev', autoAdvance: true);
    await for (final cv in cursor) {
      final val = cv.value as Map;
      final decrypted =
          await CryptoHelper.decryptData(val['payload'] as String, _dbKey!);
      final message = jsonDecode(decrypted) as Map<String, dynamic>;
      if (val['deliveryStatus'] != null) {
        message['deliveryStatus'] = val['deliveryStatus'];
      }
      await txn.completed;
      return message;
    }
    await txn.completed;
    return null;
  }

  /// Returns messages that were written while offline (synced = 0).
  Future<List<Map<String, dynamic>>> getPendingSyncMessages() async {
    await _ensureInitialized();
    final txn = _db!.transaction(messagesStore, idbModeReadOnly);
    final store = txn.objectStore(messagesStore);
    final index = store.index('synced');

    final pending = <Map<String, dynamic>>[];
    final cursor = index.openCursor(key: 0, autoAdvance: true);

    await for (final cv in cursor) {
      final val = cv.value as Map;
      final decrypted =
          await CryptoHelper.decryptData(val['payload'] as String, _dbKey!);
      final message = jsonDecode(decrypted) as Map<String, dynamic>;
      message['_local_key'] = cv.primaryKey;
      pending.add(message);
    }

    return pending;
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

  /// Marks a locally stored message as delivered using its messageId.
  Future<void> markMessageSynced(String messageId) async {
    await _ensureInitialized();
    final txn = _db!.transaction(messagesStore, idbModeReadWrite);
    final store = txn.objectStore(messagesStore);
    final index = store.index('messageId');

    final cursor = index.openCursor(key: messageId, autoAdvance: false);
    await for (final cv in cursor) {
      final val = Map<String, dynamic>.from(cv.value as Map);
      if ((val['synced'] as int? ?? 1) == 0) {
        val['synced'] = 1;
        await cv.update(val);
      }
      // Usually there's only one record per messageId, but we update all just in case.
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

  // --- Contacts ---

  Future<void> saveContact(Map<String, dynamic> contact) async {
    await _ensureInitialized();
    final txn = _db!.transaction(contactsStore, idbModeReadWrite);
    final store = txn.objectStore(contactsStore);
    await store.put(contact);
    await txn.completed;
  }

  Future<List<Map<String, dynamic>>> getContacts() async {
    await _ensureInitialized();
    final txn = _db!.transaction(contactsStore, idbModeReadOnly);
    final store = txn.objectStore(contactsStore);
    final list = await store.getAll();
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> deleteContact(String userId) async {
    await _ensureInitialized();
    final txn = _db!.transaction(contactsStore, idbModeReadWrite);
    final store = txn.objectStore(contactsStore);
    await store.delete(userId);
    await txn.completed;
  }

  // --- Calls ---

  Future<void> saveCall(Map<String, dynamic> call) async {
    await _ensureInitialized();
    final txn = _db!.transaction(callsStore, idbModeReadWrite);
    final store = txn.objectStore(callsStore);
    await store.put(call);
    await txn.completed;
  }

  Future<List<Map<String, dynamic>>> getCalls() async {
    await _ensureInitialized();
    final txn = _db!.transaction(callsStore, idbModeReadOnly);
    final store = txn.objectStore(callsStore);
    final list = await store.getAll();
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> deleteCall(String id) async {
    await _ensureInitialized();
    final txn = _db!.transaction(callsStore, idbModeReadWrite);
    final store = txn.objectStore(callsStore);
    await store.delete(id);
    await txn.completed;
  }

  // --- Attachments ---

  Future<void> saveAttachment(Map<String, dynamic> attachment) async {
    await _ensureInitialized();
    final txn = _db!.transaction(attachmentsStore, idbModeReadWrite);
    final store = txn.objectStore(attachmentsStore);
    await store.put(attachment);
    await txn.completed;
  }

  Future<Map<String, dynamic>?> getAttachment(String id) async {
    await _ensureInitialized();
    final txn = _db!.transaction(attachmentsStore, idbModeReadOnly);
    final store = txn.objectStore(attachmentsStore);
    final val = await store.getObject(id);
    if (val == null) return null;
    return Map<String, dynamic>.from(val as Map);
  }

  /// Returns every attachment row (for LRU eviction sweeps — task #12).
  /// Rows include the encrypted `payload` field; callers should consider
  /// memory if the attachment store is large.
  Future<List<Map<String, dynamic>>> getAllAttachments() async {
    await _ensureInitialized();
    final txn = _db!.transaction(attachmentsStore, idbModeReadOnly);
    final store = txn.objectStore(attachmentsStore);
    final all = <Map<String, dynamic>>[];
    final cursor = store.openCursor(autoAdvance: true);
    await for (final cv in cursor) {
      final val = cv.value as Map;
      all.add(Map<String, dynamic>.from(val));
    }
    return all;
  }

  /// Hard-delete an attachment by id. Used by LRU eviction (task #12)
  /// and by manual storage management.
  Future<void> deleteAttachment(String id) async {
    await _ensureInitialized();
    final txn = _db!.transaction(attachmentsStore, idbModeReadWrite);
    final store = txn.objectStore(attachmentsStore);
    await store.delete(id);
    await txn.completed;
  }
}
