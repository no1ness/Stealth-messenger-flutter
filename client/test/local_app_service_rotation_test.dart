import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stealth/helpers/crypto_helper.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/local_database_service.dart';

/// Tests for [LocalAppService.rotateIdentityKeypair] and friends.
///
/// Real `flutter_secure_storage_x` cannot run inside the host test
/// runner, so we mock its method channel with an in-memory map and
/// install the existing `LocalDatabaseServiceOverrides` to swap IDB
/// for the sembast-on-memory factory.
class _InMemorySecureStorage {
  _InMemorySecureStorage();

  final Map<String, String> store = <String, String>{};

  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
    final key = args['key'] as String?;
    switch (call.method) {
      case 'read':
        return store[key];
      case 'readAll':
        return Map<String, String>.from(store);
      case 'write':
        final value = args['value'] as String?;
        if (value == null) {
          store.remove(key);
        } else {
          store[key!] = value;
        }
        return null;
      case 'delete':
        store.remove(key);
        return null;
      case 'deleteAll':
        store.clear();
        return null;
      case 'containsKey':
        return store.containsKey(key);
      default:
        return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.dr1009.com/flutter_secure_storage');
  late _InMemorySecureStorage secure;
  late SecretKey dbKey;

  setUp(() async {
    secure = _InMemorySecureStorage();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, secure.handle);
    // Block sendMessage from invoking P2PService — its WebRTC stack
    // is unavailable in the test runner.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'useP2P': false,
    });
    dbKey = await CryptoHelper.generateSymmetricKey();
    LocalDatabaseService.testOverrides = LocalDatabaseServiceOverrides(
      factory: idbFactoryMemoryFs,
      dbPath: 'rotation-${DateTime.now().microsecondsSinceEpoch}.db',
      dbKey: dbKey,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    LocalDatabaseService.testOverrides = null;
  });

  Future<String> seedPeerContact(LocalDatabaseService db, String peerId) async {
    final peerKeyPair = await X25519().newKeyPair();
    final peerPublic = await peerKeyPair.extractPublicKey();
    final pubB64 = base64Encode(peerPublic.bytes);
    await db.saveContact(<String, dynamic>{
      'contact_user_id': peerId,
      'user_id': peerId,
      'name': peerId,
      'nickname': peerId,
      'public_key': pubB64,
      'created_at': DateTime.now().toIso8601String(),
    });
    return pubB64;
  }

  test('rotation preserves locally stored 1:1 chat history', () async {
    final app = LocalAppService();
    await app.registerUser('Alice');
    final db = LocalDatabaseService();
    await seedPeerContact(db, 'bob');

    final chatId = await app.findOrCreatePrivateChatWith('bob');
    expect(chatId, isNotNull, reason: 'private chat creation must succeed');

    await app.sendMessage(chatId: chatId!, content: 'm1', type: 'text');
    await app.sendMessage(chatId: chatId, content: 'm2', type: 'text');
    await app.sendMessage(chatId: chatId, content: 'm3', type: 'text');

    // Sanity: pre-rotation reads decrypt back to the original plaintext.
    final preRows = await db.getMessages(chatId);
    expect(preRows, hasLength(3));
    final preDecrypted =
        await Future.wait(preRows.map(app.decryptRawMessage));
    expect(
      preDecrypted.map((m) => m['content']).toSet(),
      {'m1', 'm2', 'm3'},
    );

    final result = await app.rotateIdentityKeypair();
    expect(result.migratedMessageCount, 3,
        reason: 'every sent message must be re-encrypted to the new key');
    expect(result.skippedMessageCount, 0);
    expect(result.previousPublicKey, isNot(result.newPublicKey));

    // Post-rotation: decryptMessage now derives the shared secret
    // from the NEW canonical key. If the migration did not rewrite
    // the ciphertexts, every read here would surface base64 gibberish.
    final postRows = await db.getMessages(chatId);
    final postDecrypted =
        await Future.wait(postRows.map(app.decryptRawMessage));
    expect(
      postDecrypted.map((m) => m['content']).toSet(),
      {'m1', 'm2', 'm3'},
      reason: 'Path A re-encryption must keep history readable post-rotation',
    );

    // Simulate the 24h grace expiring — prev material is wiped.
    // Migrated rows must remain readable because they are now
    // canonical-key ciphertexts, not prev-key ones.
    secure.store['prev_rotated_at'] = DateTime.now()
        .subtract(const Duration(hours: 25))
        .toIso8601String();
    await app.pruneExpiredPrevIdentityKey();
    expect(secure.store.containsKey('privateKey_prev'), isFalse);
    expect(secure.store.containsKey('publicKey_prev'), isFalse);
    expect(secure.store.containsKey('prev_rotated_at'), isFalse);

    final afterPruneRows = await db.getMessages(chatId);
    final afterPruneDecrypted =
        await Future.wait(afterPruneRows.map(app.decryptRawMessage));
    expect(
      afterPruneDecrypted.map((m) => m['content']).toSet(),
      {'m1', 'm2', 'm3'},
      reason: 'after the prev key is pruned, history remains decryptable '
          'because the rotation migrated rows to the new shared secret',
    );
  });

  test('rotation in-flight guard coalesces concurrent calls', () async {
    final app = LocalAppService();
    await app.registerUser('Alice');

    final results = await Future.wait(<Future<IdentityRotationResult>>[
      app.rotateIdentityKeypair(),
      app.rotateIdentityKeypair(),
    ]);
    expect(
      results.first.newPublicKey,
      results.last.newPublicKey,
      reason:
          'both concurrent callers must observe the same rotation result',
    );
    expect(
      results.first.previousPublicKey,
      results.last.previousPublicKey,
      reason:
          'previousPublicKey must be the keypair active before EITHER call '
          'started — proves the second call was joined, not raced',
    );

    // Subsequent rotation should swap again — proves the guard
    // resets after completion.
    final third = await app.rotateIdentityKeypair();
    expect(third.previousPublicKey, results.first.newPublicKey);
    expect(third.newPublicKey, isNot(results.first.newPublicKey));
  });

  test('pruneExpiredPrevIdentityKey is a no-op inside the grace window',
      () async {
    final app = LocalAppService();
    await app.registerUser('Alice');

    secure.store['privateKey_prev'] = 'sentinel-priv';
    secure.store['publicKey_prev'] = 'sentinel-pub';
    secure.store['prev_rotated_at'] =
        DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();

    await app.pruneExpiredPrevIdentityKey();

    expect(secure.store['privateKey_prev'], 'sentinel-priv');
    expect(secure.store['publicKey_prev'], 'sentinel-pub');
  });

  test('pruneExpiredPrevIdentityKey clears prev material past 24h', () async {
    final app = LocalAppService();
    await app.registerUser('Alice');

    secure.store['privateKey_prev'] = 'expired-priv';
    secure.store['publicKey_prev'] = 'expired-pub';
    secure.store['prev_rotated_at'] =
        DateTime.now().subtract(const Duration(hours: 25)).toIso8601String();

    await app.pruneExpiredPrevIdentityKey();

    expect(secure.store.containsKey('privateKey_prev'), isFalse);
    expect(secure.store.containsKey('publicKey_prev'), isFalse);
    expect(secure.store.containsKey('prev_rotated_at'), isFalse);
  });

  test('batchVerificationStatuses returns an entry per contact', () async {
    final app = LocalAppService();
    await app.registerUser('Alice');
    final db = LocalDatabaseService();
    final contacts = <Map<String, dynamic>>[];
    for (var i = 0; i < 5; i++) {
      await seedPeerContact(db, 'peer-$i');
      contacts.add((await db.getContacts())
          .firstWhere((c) => c['user_id'] == 'peer-$i'));
    }

    final statuses = await app.batchVerificationStatuses(contacts);

    expect(statuses, hasLength(5));
    for (final entry in statuses.entries) {
      expect(entry.value.verified, isFalse,
          reason: 'fresh contacts have no verified_at snapshot');
      expect(entry.value.hasMismatch, isFalse,
          reason: 'absent snapshot means no mismatch to surface');
    }
  });
}
