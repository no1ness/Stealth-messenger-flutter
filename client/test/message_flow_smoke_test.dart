import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('two temporary accounts can exchange encrypted messages', () async {
    final env = await _loadEnv(File('.env'));
    final url = env['SUPABASE_URL'];
    final anonKey = env['SUPABASE_ANON_KEY'];
    expect(url, isNotNull, reason: 'Missing SUPABASE_URL in client/.env');
    expect(
      anonKey,
      isNotNull,
      reason: 'Missing SUPABASE_ANON_KEY in client/.env',
    );
    final resolvedUrl = url!;
    final resolvedAnonKey = anonKey!;

    final crypto = _MessageCrypto();
    final userA = await _createAuthenticatedUser(
      resolvedUrl,
      resolvedAnonKey,
      'smoke_a_${DateTime.now().millisecondsSinceEpoch}',
    );
    final userB = await _createAuthenticatedUser(
      resolvedUrl,
      resolvedAnonKey,
      'smoke_b_${DateTime.now().millisecondsSinceEpoch}',
    );
    String? chatId;

    try {
      chatId = await _createPrivateChat(userA.client, userA.id, userB.id);
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

      await userA.client.from('messages').insert({
        'chat_id': chatId,
        'sender_id': userA.id,
        'content': encryptedA,
        'message_type': 'text',
        'metadata': {'encryption': 'e2e'},
      });
      await userB.client.from('messages').insert({
        'chat_id': chatId,
        'sender_id': userB.id,
        'content': encryptedB,
        'message_type': 'text',
        'metadata': {'encryption': 'e2e'},
      });

      final rows = await userA.client
          .from('messages')
          .select('sender_id, content, metadata')
          .eq('chat_id', chatId)
          .order('created_at');

      expect(rows.length, greaterThanOrEqualTo(2));

      final firstByA = rows
          .cast<Map<String, dynamic>>()
          .firstWhere((row) => row['sender_id'] == userA.id);
      final firstByB = rows
          .cast<Map<String, dynamic>>()
          .firstWhere((row) => row['sender_id'] == userB.id);

      final decryptedForB = await crypto.decryptFromPeer(
        recipient: userB,
        sender: userA,
        payload: firstByA['content'] as String,
      );
      final decryptedForA = await crypto.decryptFromPeer(
        recipient: userA,
        sender: userB,
        payload: firstByB['content'] as String,
      );

      expect(firstByA['content'], isNot(plainA));
      expect(firstByB['content'], isNot(plainB));
      expect(decryptedForB, plainA);
      expect(decryptedForA, plainB);
    } finally {
      if (chatId != null) {
        await _safeDelete(
          () => userA.client.from('messages').delete().eq('chat_id', chatId!),
        );
        await _safeDelete(
          () => userA.client.from('chat_members').delete().eq('chat_id', chatId!),
        );
        await _safeDelete(
          () => userA.client.from('chats').delete().eq('id', chatId!),
        );
      }
      await _safeDelete(
        () => userA.client.from('users').delete().eq('id', userA.id),
      );
      await _safeDelete(
        () => userB.client.from('users').delete().eq('id', userB.id),
      );
    }
  });
}

Future<Map<String, String>> _loadEnv(File file) async {
  final result = <String, String>{};
  for (final rawLine in await file.readAsLines()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
      continue;
    }
    final separator = line.indexOf('=');
    result[line.substring(0, separator)] = line.substring(separator + 1);
  }
  return result;
}

Future<_TestUser> _createAuthenticatedUser(
  String url,
  String anonKey,
  String nickname,
) async {
  final algorithm = X25519();
  final authClient = SupabaseClient(url, anonKey);
  final authResponse = await authClient.auth.signInAnonymously();
  final authUser = authResponse.user;
  final session = authResponse.session;
  if (authUser == null || session == null) {
    throw Exception(
      'Supabase anonymous auth did not return an authenticated session.',
    );
  }

  final client = SupabaseClient(
    url,
    anonKey,
    accessToken: () async => session.accessToken,
  );
  final keyPair = await algorithm.newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final privateKey = await keyPair.extractPrivateKeyBytes();
  final user = _TestUser(
    id: authUser.id,
    nickname: nickname,
    client: client,
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
  final chatId = const Uuid().v4();
  await client.from('chats').insert({
    'id': chatId,
    'name': 'Smoke chat',
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': DateTime.now().toIso8601String(),
  });
  await client.from('chat_members').insert([
    {'chat_id': chatId, 'user_id': userA},
    {'chat_id': chatId, 'user_id': userB},
  ]);
  return chatId;
}

Future<void> _safeDelete(Future<dynamic> Function() action) async {
  try {
    await action();
  } catch (_) {}
}

class _TestUser {
  const _TestUser({
    required this.id,
    required this.nickname,
    required this.client,
    required this.keyPair,
  });

  final String id;
  final String nickname;
  final SupabaseClient client;
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
    final clearText = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: sharedSecret,
    );
    return utf8.decode(clearText);
  }
}
