import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

Future<void> main() async {
  void log(String message) => stdout.writeln('[smoke] $message');

  log('loading env');
  final env = await _loadEnv(File('.env'));
  final url = env['SUPABASE_URL'];
  final anonKey = env['SUPABASE_ANON_KEY'];
  if (url == null || anonKey == null) {
    stderr.writeln('Missing SUPABASE_URL or SUPABASE_ANON_KEY in client/.env');
    exitCode = 1;
    return;
  }

  log('creating supabase client');
  final client = SupabaseClient(url, anonKey);
  final crypto = _MessageCrypto();
  log('creating user A');
  final userA = await _withTimeout(
    'create user A',
    _createUser(client, 'smoke_a_${DateTime.now().millisecondsSinceEpoch}'),
  );
  log('creating user B');
  final userB = await _withTimeout(
    'create user B',
    _createUser(client, 'smoke_b_${DateTime.now().millisecondsSinceEpoch}'),
  );
  String? chatId;

  try {
    log('creating private chat');
    chatId = await _withTimeout(
      'create private chat',
      _createPrivateChat(client, userA.id, userB.id),
    );

    const plainA = 'hello from account A';
    const plainB = 'reply from account B';

    final encryptedA = await crypto.encryptForPeer(
      sender: userA,
      recipient: userB,
      content: plainA,
    );
    final encryptedB = await crypto.encryptForPeer(
      sender: userB,
      recipient: userA,
      content: plainB,
    );

    log('inserting message A -> B');
    await _withTimeout(
      'insert first message',
      client.from('messages').insert({
        'chat_id': chatId,
        'sender_id': userA.id,
        'content': encryptedA,
        'message_type': 'text',
        'metadata': {'encryption': 'e2e'},
      }),
    );
    log('inserting message B -> A');
    await _withTimeout(
      'insert second message',
      client.from('messages').insert({
        'chat_id': chatId,
        'sender_id': userB.id,
        'content': encryptedB,
        'message_type': 'text',
        'metadata': {'encryption': 'e2e'},
      }),
    );

    log('fetching messages');
    final rows = await _withTimeout(
      'fetch messages',
      client
          .from('messages')
          .select('sender_id, content, metadata')
          .eq('chat_id', chatId!)
          .order('created_at'),
    );

    if (rows.length < 2) {
      throw Exception('Expected at least 2 messages in chat, got ${rows.length}.');
    }

    final first = Map<String, dynamic>.from(rows[0] as Map);
    final second = Map<String, dynamic>.from(rows[1] as Map);

    final decryptedForB = await crypto.decryptFromPeer(
      recipient: userB,
      sender: userA,
      payload: first['content'] as String,
    );
    final decryptedForA = await crypto.decryptFromPeer(
      recipient: userA,
      sender: userB,
      payload: second['content'] as String,
    );

    final firstEncrypted = first['content'] != plainA;
    final secondEncrypted = second['content'] != plainB;

    stdout.writeln('chat_id=$chatId');
    stdout.writeln('user_a=${userA.id}');
    stdout.writeln('user_b=${userB.id}');
    stdout.writeln('encrypted_a=$firstEncrypted');
    stdout.writeln('encrypted_b=$secondEncrypted');
    stdout.writeln('decrypted_for_b=$decryptedForB');
    stdout.writeln('decrypted_for_a=$decryptedForA');

    if (!firstEncrypted || !secondEncrypted) {
      throw Exception('Messages were stored as plaintext.');
    }
    if (decryptedForB != plainA || decryptedForA != plainB) {
      throw Exception('Decrypted payload mismatch.');
    }

    stdout.writeln('RESULT: PASS');
  } catch (error, stackTrace) {
    stderr.writeln('RESULT: FAIL');
    stderr.writeln(error);
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    log('cleanup start');
    if (chatId != null) {
      await _ignoreCleanupError(
        () => client.from('messages').delete().eq('chat_id', chatId!),
      );
      await _ignoreCleanupError(
        () => client.from('chat_members').delete().eq('chat_id', chatId!),
      );
      await _ignoreCleanupError(
        () => client.from('chats').delete().eq('id', chatId!),
      );
    }
    await _ignoreCleanupError(
      () => client.from('users').delete().inFilter('id', [userA.id, userB.id]),
    );
    log('cleanup done');
  }
}

Future<T> _withTimeout<T>(String label, Future<T> future) {
  return future.timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw TimeoutException('Timed out during $label'),
  );
}

Future<void> _ignoreCleanupError(Future<dynamic> Function() action) async {
  try {
    await action().timeout(const Duration(seconds: 15));
  } catch (_) {}
}

Future<Map<String, String>> _loadEnv(File file) async {
  final result = <String, String>{};
  final lines = await file.readAsLines();
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final separator = line.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    result[line.substring(0, separator)] = line.substring(separator + 1);
  }
  return result;
}

Future<_TestUser> _createUser(SupabaseClient client, String nickname) async {
  final algorithm = X25519();
  final uuid = Uuid();
  final keyPair = await algorithm.newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final privateKey = await keyPair.extractPrivateKeyBytes();
  final user = _TestUser(
    id: uuid.v4(),
    nickname: nickname,
    keyPair: SimpleKeyPairData(
      privateKey,
      publicKey: publicKey,
      type: KeyPairType.x25519,
    ),
  );

  await client.from('users').insert({
    'id': user.id,
    'nickname': user.nickname,
    'public_key': base64Encode(publicKey.bytes),
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': DateTime.now().toIso8601String(),
  });
  return user;
}

Future<String> _createPrivateChat(
  SupabaseClient client,
  String userA,
  String userB,
) async {
  final uuid = Uuid();
  final chatId = uuid.v4();
  await client.from('chats').insert({
    'id': chatId,
    'name': '',
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': DateTime.now().toIso8601String(),
  });
  await client.from('chat_members').insert([
    {'chat_id': chatId, 'user_id': userA},
    {'chat_id': chatId, 'user_id': userB},
  ]);
  return chatId;
}

class _TestUser {
  const _TestUser({
    required this.id,
    required this.nickname,
    required this.keyPair,
  });

  final String id;
  final String nickname;
  final SimpleKeyPairData keyPair;
}

class _MessageCrypto {
  final X25519 _algorithm = X25519();
  final AesGcm _aes = AesGcm.with256bits();

  Future<String> encryptForPeer({
    required _TestUser sender,
    required _TestUser recipient,
    required String content,
  }) async {
    final sharedSecret = await _algorithm.sharedSecretKey(
      keyPair: sender.keyPair,
      remotePublicKey: recipient.keyPair.publicKey,
    );
    final secretBox = await _aes.encrypt(
      Uint8List.fromList(utf8.encode(content)),
      secretKey: sharedSecret,
    );

    final combined = Uint8List(
      secretBox.nonce.length +
          secretBox.cipherText.length +
          secretBox.mac.bytes.length,
    );
    combined.setRange(0, secretBox.nonce.length, secretBox.nonce);
    combined.setRange(
      secretBox.nonce.length,
      secretBox.nonce.length + secretBox.cipherText.length,
      secretBox.cipherText,
    );
    combined.setRange(
      secretBox.nonce.length + secretBox.cipherText.length,
      combined.length,
      secretBox.mac.bytes,
    );
    return base64Encode(combined);
  }

  Future<String> decryptFromPeer({
    required _TestUser recipient,
    required _TestUser sender,
    required String payload,
  }) async {
    final sharedSecret = await _algorithm.sharedSecretKey(
      keyPair: recipient.keyPair,
      remotePublicKey: sender.keyPair.publicKey,
    );
    final combined = base64Decode(payload);
    const nonceLength = 12;
    const macLength = 16;
    final nonce = combined.sublist(0, nonceLength);
    final mac = Mac(combined.sublist(combined.length - macLength));
    final cipherText = combined.sublist(
      nonceLength,
      combined.length - macLength,
    );
    final clearBytes = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: sharedSecret,
    );
    return utf8.decode(clearBytes);
  }
}
