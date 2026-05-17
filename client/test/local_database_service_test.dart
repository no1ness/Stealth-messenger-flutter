import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:stealth/helpers/crypto_helper.dart';
import 'package:stealth/local_database_service.dart';

/// Tests for [LocalDatabaseService.saveMessage] and friends.
///
/// The class normally pulls its IDB factory from `idb_io.dart`, its
/// path from `path_provider`, and its encryption key from
/// `StorageService` (which goes through `flutter_secure_storage_x` on
/// mobile / Web Crypto on the browser). None of those work in the
/// plain test runner, so we install
/// `LocalDatabaseServiceOverrides` to swap them for in-memory /
/// in-test fakes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecretKey dbKey;

  setUp(() async {
    dbKey = await CryptoHelper.generateSymmetricKey();
    // `idbFactoryMemoryFs` is sembast-backed (matches the production
    // `idbFactorySembastIo` behaviour) but writes to an in-memory
    // filesystem so each test gets a fresh DB without touching the
    // real filesystem. `newIdbFactoryMemory()` follows strict IDB
    // transaction semantics that production code does not actually
    // satisfy — using it here would fail tests that pass on real
    // sembast/IDB backends.
    LocalDatabaseService.testOverrides = LocalDatabaseServiceOverrides(
      factory: idbFactoryMemoryFs,
      // Unique path per test prevents state from leaking between
      // tests sharing the same in-memory FS.
      dbPath: 'test-${DateTime.now().microsecondsSinceEpoch}.db',
      dbKey: dbKey,
    );
  });

  tearDown(() {
    LocalDatabaseService.testOverrides = null;
  });

  group('saveMessage', () {
    test('roundtrip — payload is encrypted at rest and decrypts back',
        () async {
      final db = LocalDatabaseService();
      const chatId = 'chat-1';
      final message = <String, dynamic>{
        'id': 'msg-1',
        'chat_id': chatId,
        'sender_id': 'alice',
        'content': 'Hello, world',
        'created_at': '2026-01-01T00:00:00Z',
      };

      await db.saveMessage(message);

      final loaded = await db.getMessages(chatId);
      expect(loaded, hasLength(1));
      expect(loaded.first['id'], 'msg-1');
      expect(loaded.first['content'], 'Hello, world');
      expect(loaded.first['sender_id'], 'alice');
    });

    test('dedup — same messageId only writes one row', () async {
      final db = LocalDatabaseService();
      const chatId = 'chat-dedup';
      final original = <String, dynamic>{
        'id': 'msg-dedup',
        'chat_id': chatId,
        'sender_id': 'alice',
        'content': 'first body',
      };
      await db.saveMessage(original);

      // Save the same id with a different body — saveMessage should
      // overwrite the encrypted payload in-place rather than insert a
      // second row.
      final updated = Map<String, dynamic>.from(original)
        ..['content'] = 'second body';
      await db.saveMessage(updated);

      final loaded = await db.getMessages(chatId);
      expect(loaded, hasLength(1),
          reason:
              'dedup by `id` index must keep the messages table at one row');
      expect(loaded.first['content'], 'second body');
    });

    test('cross-chat isolation — getMessages returns only that chat',
        () async {
      final db = LocalDatabaseService();
      await db.saveMessage(<String, dynamic>{
        'id': 'a-1',
        'chat_id': 'chat-a',
        'content': 'A1',
      });
      await db.saveMessage(<String, dynamic>{
        'id': 'b-1',
        'chat_id': 'chat-b',
        'content': 'B1',
      });
      await db.saveMessage(<String, dynamic>{
        'id': 'a-2',
        'chat_id': 'chat-a',
        'content': 'A2',
      });

      final inA = await db.getMessages('chat-a');
      final inB = await db.getMessages('chat-b');

      expect(inA.map((m) => m['content']).toSet(), {'A1', 'A2'});
      expect(inB.map((m) => m['content']).toSet(), {'B1'});
    });

    test('unsynced messages surface in getPendingSyncMessages', () async {
      final db = LocalDatabaseService();
      await db.saveMessage(
        <String, dynamic>{'id': 'pending-1', 'chat_id': 'chat', 'content': 'p'},
        synced: false,
      );
      await db.saveMessage(
        <String, dynamic>{'id': 'sent-1', 'chat_id': 'chat', 'content': 's'},
      );

      final pending = await db.getPendingSyncMessages();
      expect(pending.map((m) => m['id']).toList(), ['pending-1']);
    });

    test('wrong key cannot decrypt the stored payload', () async {
      // Write with one key, then swap the override to a different
      // key and confirm the read fails (proves the on-disk payload
      // is genuinely encrypted, not just base64-wrapped).
      final db = LocalDatabaseService();
      await db.saveMessage(<String, dynamic>{
        'id': 'enc-1',
        'chat_id': 'enc',
        'content': 'secret',
      });

      final wrongKey = await CryptoHelper.generateSymmetricKey();
      LocalDatabaseService.testOverrides = LocalDatabaseServiceOverrides(
        factory: LocalDatabaseService.testOverrides!.factory,
        dbPath: LocalDatabaseService.testOverrides!.dbPath,
        dbKey: wrongKey,
      );
      final db2 = LocalDatabaseService();
      // The factory keeps a single named DB across instances, so db2
      // sees the same store. With the wrong key the AES-GCM tag
      // check fails on decrypt.
      expect(
        () => db2.getMessages('enc'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });
}
