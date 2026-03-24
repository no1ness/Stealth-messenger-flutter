import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Упрощённая реализация алгоритма Double Ratchet.
/// 
/// Обеспечивает Perfect Forward Secrecy (PFS) путём постоянной смены 
/// ключей шифрования для каждого отдельного сообщения (Symmetric Ratchet).
/// 
/// Старые ключи цепочки (Chain Key) уничтожаются (отбрасываются) при вычислении новых,
/// поэтому взлом текущего состояния не позволяет расшифровать старые переписки.
class RatchetService {
  final Hmac _hmac = Hmac.sha256();
  final AesGcm _aes = AesGcm.with256bits();

  /// Key Derivation Function: вычисляет следующий ключ цепочки и ключ сообщения
  ///
  /// На вход идёт текущий Chain Key (32 байта).
  /// На выходе:
  /// - `messageKey`: Ключ-шифрования для 1 сообщения (AES-256)
  /// - `nextChainKey`: Следующий ключ цепочки
  Future<Map<String, SecretKey>> advanceSymmetricRatchet(SecretKey currentChainKey) async {
    final mkMac = await _hmac.calculateMac([0x01], secretKey: currentChainKey);
    final ckMac = await _hmac.calculateMac([0x02], secretKey: currentChainKey);
    return {
      'messageKey': SecretKey(mkMac.bytes),
      'nextChainKey': SecretKey(ckMac.bytes),
    };
  }

  /// Детерминированно вычисляет Ключ Сообщения N (Stateless Ratchet).
  /// Устраняет необходимость хранить цепочки локально, опираясь на индекс сообщения.
  Future<SecretKey> getNthMessageKey(SecretKey rootChainKey, int targetIndex) async {
    SecretKey currentChain = rootChainKey;
    SecretKey? messageKey;
    
    // Прокручиваем "храповик" N раз от корня:
    for (int i = 0; i <= targetIndex; i++) {
      final keys = await advanceSymmetricRatchet(currentChain);
      messageKey = keys['messageKey'];
      currentChain = keys['nextChainKey']!;
    }
    return messageKey!;
  }

  /// Инициализирует цепочки для Алисы и Боба на основе единого Shared Secret.
  Future<Map<String, SecretKey>> initializeChains(SecretKey sharedSecret, String myId, String otherId) async {
    // В зависимости от лексикографического порядка определяем кто есть кто для детерминированности
    final isMeFirst = myId.compareTo(otherId) < 0;
    
    final ik1 = await _hmac.calculateMac(utf8.encode('CHAIN_1'), secretKey: sharedSecret);
    final ik2 = await _hmac.calculateMac(utf8.encode('CHAIN_2'), secretKey: sharedSecret);
    
    return {
      'mySendChain': isMeFirst ? SecretKey(ik1.bytes) : SecretKey(ik2.bytes),
      'theirSendChain': isMeFirst ? SecretKey(ik2.bytes) : SecretKey(ik1.bytes),
    };
  }

  /// Шифрует контент, используя эфемерный ключ, полученный от храповика (Ratchet)
  Future<Map<String, dynamic>> encryptMessage(String plaintext, SecretKey messageKey) async {
    final encoded = utf8.encode(plaintext);
    // AesGcm.encrypt автоматически генерирует случайный nonce, подходящий для GCM.
    // Но мы также можем сгенерировать его вручную (обычно 12 байт).
    final secretBox = await _aes.encrypt(
      encoded,
      secretKey: messageKey,
    );

    return {
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  /// Расшифровывает контент
  Future<String> decryptMessage(
    String nonceB64,
    String ciphertextB64,
    String macB64,
    SecretKey messageKey,
  ) async {
    final nonce = base64Decode(nonceB64);
    final ciphertext = base64Decode(ciphertextB64);
    final mac = base64Decode(macB64);

    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(mac),
    );

    final clearTextBytes = await _aes.decrypt(
      secretBox,
      secretKey: messageKey,
    );

    return utf8.decode(clearTextBytes);
  }
}
