import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:idb_shim/idb_browser.dart';
import 'package:idb_shim/idb_io.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stealth/helpers/crypto_helper.dart';
import 'package:stealth/storage_service.dart';

/// Test-only override of the platform dependencies that
/// [LocalDatabaseService] consults during `_ensureInitialized`:
///
/// - [factory] swaps the IDB backend (e.g. `idbFactoryMemory` for
///   unit tests so no filesystem or `path_provider` access is needed).
/// - [dbPath] overrides the DB file path (irrelevant for in-memory
///   factories, used by sembast-on-tmp tests).
/// - [dbKey] supplies a deterministic encryption key so the test does
///   not have to mock `flutter_secure_storage_x` through a method
///   channel just to hand back `local_db_key`.
class LocalDatabaseServiceOverrides {
  const LocalDatabaseServiceOverrides({
    this.factory,
    this.dbPath,
    this.dbKey,
  });

  final IdbFactory? factory;
  final String? dbPath;
  final SecretKey? dbKey;
}

class LocalDatabaseService {
  static const String dbName = 'stealth_local_v3.db';
  // Bumped to v2 to add the `synced` index on the messages store.
  static const int dbVersion = 4;

  static const String messagesStore = 'messages';
  static const String chatsStore = 'chats';
  static const String contactsStore = 'contacts';
  static const String callsStore = 'calls';

  /// Test-only seam. Set in `setUp`, clear in `tearDown` (assign back
  /// to `null`). Production code never touches this field.
  @visibleForTesting
  static LocalDatabaseServiceOverrides? testOverrides;

  IdbFactory get _factory {
    final override = testOverrides?.factory;
    if (override != null) return override;
    return kIsWeb ? idbFactoryBrowser : idbFactorySembastIo;
  }

  Database? _db;
  SecretKey? _dbKey;

  Future<void> _ensureInitialized() async {
    if (_db != null) return;

    final factory = _factory;
    final overridePath = testOverrides?.dbPath;
    final path = overridePath ??
        (kIsWeb
            ? dbName
            : join((await getApplicationDocumentsDirectory()).path, dbName));

    _db =
        await factory.open(path, version: dbVersion, onUpgradeNeeded: (event) {
      final db = event.database;
      if (!db.objectStoreNames.contains(messagesStore)) {
        final store = db.createObjectStore(messagesStore, autoIncrement: true);
        store.createIndex('chatId', 'chatId');
        store.createIndex('synced', 'synced');
        store.createIndex('messageId', 'messageId');
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
      }
      if (!db.objectStoreNames.contains(chatsStore)) {
        db.createObjectStore(chatsStore, keyPath: 'id');
      }
      if (!db.objectStoreNames.contains(contactsStore)) {
        db.createObjectStore(contactsStore, keyPath: 'contact_user_id');
      }
      if (!db.objectStoreNames.contains(callsStore)) {
        final store = db.createObjectStore(callsStore, autoIncrement: true);
        store.createIndex('chatId', 'chatId');
      }
    });

    // Initialize encryption key. Tests can short-circuit the
    // StorageService round-trip via `testOverrides.dbKey`.
    final overrideKey = testOverrides?.dbKey;
    if (overrideKey != null) {
      _dbKey = overrideKey;
      return;
    }
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
  }) async {
    await _ensureInitialized();

    final messageId = message['id']?.toString();
    // Encrypt before opening the transaction. AES-GCM in
    // `package:cryptography` schedules work that can yield to the
    // microtask queue on some backends; awaiting it inside an IDB
    // transaction will release the transaction context and the
    // subsequent `store.put` then throws `TransactionInactiveError`
    // (reproducible under sembast in tests; intermittent in
    // production on slower devices). Pre-computing here keeps every
    // `await` inside the transaction strictly IDB-only.
    final encrypted =
        await CryptoHelper.encryptData(jsonEncode(message), _dbKey!);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

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
          val['payload'] = encrypted;
          val['timestamp'] = timestamp;
          val['chatId'] = message['chat_id'];
          val['synced'] = synced ? 1 : (val['synced'] as int? ?? 1);
          await store.put(val, existingKey);
        }
        await txn.completed;
        return existingKey;
      }
    }

    // 2. Save new message (already encrypted above).
    final localKey = await store.put({
      'payload': encrypted,
      'timestamp': timestamp,
      'chatId': message['chat_id'],
      'messageId': messageId,
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
    final index = store.index('chatId');

    final messages = <Map<String, dynamic>>[];
    final cursor = index.openCursor(key: chatId, autoAdvance: true);

    await for (final cv in cursor) {
      final val = cv.value as Map;
      final decrypted =
          await CryptoHelper.decryptData(val['payload'] as String, _dbKey!);
      messages.add(jsonDecode(decrypted) as Map<String, dynamic>);
    }

    return messages;
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

  /// Returns the single contact record keyed by [contactUserId], or
  /// `null` if no such row exists. Used by safety-number verification
  /// (see [LocalAppService.isContactVerified]) which needs to read a
  /// single contact without paging the whole table.
  Future<Map<String, dynamic>?> getContact(String contactUserId) async {
    await _ensureInitialized();
    final txn = _db!.transaction(contactsStore, idbModeReadOnly);
    final store = txn.objectStore(contactsStore);
    final raw = await store.getObject(contactUserId);
    await txn.completed;
    if (raw == null) {
      return null;
    }
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Persists a safety-number verification result for the given
  /// contact. The contact record stores two related fields:
  ///
  /// - `verified_at` — ISO-8601 timestamp of the user-confirmed
  ///   verification (null until the user clicks "Confirm" in the
  ///   safety-number dialog).
  /// - `verified_safety_number` — snapshot of the SHA-256 fingerprint
  ///   at the moment of verification. If a future call to
  ///   [LocalAppService.getSafetyNumber] returns a different value,
  ///   the contact's public key has rotated and the verification is
  ///   stale (see [LocalAppService.detectSafetyMismatch]).
  Future<void> markContactVerified(
    String contactUserId, {
    required String safetyNumber,
    required DateTime verifiedAt,
  }) async {
    await _ensureInitialized();
    final txn = _db!.transaction(contactsStore, idbModeReadWrite);
    final store = txn.objectStore(contactsStore);
    final raw = await store.getObject(contactUserId);
    if (raw == null) {
      await txn.completed;
      throw StateError(
        'Cannot mark unknown contact as verified: $contactUserId',
      );
    }
    final updated = Map<String, dynamic>.from(raw as Map);
    updated['verified_at'] = verifiedAt.toIso8601String();
    updated['verified_safety_number'] = safetyNumber;
    await store.put(updated);
    await txn.completed;
  }

  /// Clears `verified_at` on every contact (leaves
  /// `verified_safety_number` as a historical record). Called by
  /// [LocalAppService.rotateIdentityKeypair] — once the local
  /// identity key changes, every contact's safety number is by
  /// definition different and must be re-verified by the user.
  Future<void> clearAllContactsVerifiedAt() async {
    await _ensureInitialized();
    final txn = _db!.transaction(contactsStore, idbModeReadWrite);
    final store = txn.objectStore(contactsStore);
    final rows = await store.getAll();
    for (final raw in rows) {
      final contact = Map<String, dynamic>.from(raw as Map);
      if (contact['verified_at'] == null) {
        continue;
      }
      contact['verified_at'] = null;
      await store.put(contact);
    }
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
}
