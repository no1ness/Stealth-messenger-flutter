
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';

void main() {
  group('E2E Encryption', () {
    final algorithm = X25519();
    final aes = AesGcm.with256bits();

    test('Key Generation and Shared Secret Derivation', () async {
      // User A (Alice) generates keys
      final aliceKeyPair = await algorithm.newKeyPair();
      final alicePublicKey = await aliceKeyPair.extractPublicKey();

      // User B (Bob) generates keys
      final bobKeyPair = await algorithm.newKeyPair();
      final bobPublicKey = await bobKeyPair.extractPublicKey();

      // Alice calculates shared secret using Bob's public key
      final aliceSharedSecret = await algorithm.sharedSecretKey(
        keyPair: aliceKeyPair,
        remotePublicKey: bobPublicKey,
      );

      // Bob calculates shared secret using Alice's public key
      final bobSharedSecret = await algorithm.sharedSecretKey(
        keyPair: bobKeyPair,
        remotePublicKey: alicePublicKey,
      );

      final aliceSecretBytes = await aliceSharedSecret.extractBytes();
      final bobSecretBytes = await bobSharedSecret.extractBytes();

      // Both secrets must be identical
      expect(aliceSecretBytes, equals(bobSecretBytes));
      debugPrint('Shared secret derived successfully.');
    });

    test('Encryption and Decryption Flow', () async {
      // 1. Setup Keys
      final aliceKeyPair = await algorithm.newKeyPair();
      final bobKeyPair = await algorithm.newKeyPair();
      
      final alicePublicKey = await aliceKeyPair.extractPublicKey();
      final bobPublicKey = await bobKeyPair.extractPublicKey();

      // 2. Derive Shared Secret (Alice side)
      final aliceSharedSecret = await algorithm.sharedSecretKey(
        keyPair: aliceKeyPair,
        remotePublicKey: bobPublicKey,
      );

      // 3. Encrypt Message (Alice -> Bob)
      const message = "Hello, this is a secret message!";
      final messageBytes = utf8.encode(message);
      
      final secretBox = await aes.encrypt(
        messageBytes,
        secretKey: aliceSharedSecret,
      );

      // Simulate sending over network (Base64 encoding)
      // We need to send nonce + ciphertext + mac
      final combined = Uint8List(secretBox.nonce.length + secretBox.cipherText.length + secretBox.mac.bytes.length);
      combined.setRange(0, secretBox.nonce.length, secretBox.nonce);
      combined.setRange(secretBox.nonce.length, secretBox.nonce.length + secretBox.cipherText.length, secretBox.cipherText);
      combined.setRange(secretBox.nonce.length + secretBox.cipherText.length, combined.length, secretBox.mac.bytes);
      
      final networkPayload = base64Encode(combined);
      debugPrint('Encrypted payload: $networkPayload');

      // 4. Derive Shared Secret (Bob side)
      final bobSharedSecret = await algorithm.sharedSecretKey(
        keyPair: bobKeyPair,
        remotePublicKey: alicePublicKey,
      );

      // 5. Decrypt Message (Bob receives)
      final receivedBytes = base64Decode(networkPayload);
      
      const nonceLength = 12;
      const macLength = 16;
      
      final nonce = receivedBytes.sublist(0, nonceLength);
      final mac = Mac(receivedBytes.sublist(receivedBytes.length - macLength));
      final ciphertext = receivedBytes.sublist(nonceLength, receivedBytes.length - macLength);
      
      final receivedBox = SecretBox(ciphertext, nonce: nonce, mac: mac);
      
      final decryptedBytes = await aes.decrypt(
        receivedBox,
        secretKey: bobSharedSecret,
      );
      
      final decryptedMessage = utf8.decode(decryptedBytes);
      
      expect(decryptedMessage, equals(message));
      debugPrint('Decrypted message: $decryptedMessage');
    });
  });
}
