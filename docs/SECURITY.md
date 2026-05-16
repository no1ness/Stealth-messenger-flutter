# Модель безопасности Stealth Messenger

## Что защищаем

- Приватные ключи пользователя.
- Plaintext сообщений.
- Вложения до шифрования и после расшифровки.
- Локальную историю контактов, чатов и звонков.

## Криптография

- Identity keypair: X25519.
- Private chat secret: X25519 shared secret.
- Message encryption: AES-256-GCM.
- Ratchet helpers используются для private message keys. **Это НЕ Double
  Ratchet и НЕ обеспечивает Perfect Forward Secrecy.** Текущая
  реализация (`client/lib/crypto/ratchet_service.dart`) — stateless
  symmetric KDF chain поверх X25519 shared secret. План перехода на
  настоящий Double Ratchet зафиксирован в
  [`.ai-factory/RESEARCH.md`](../.ai-factory/RESEARCH.md).
- Local database payloads дополнительно шифруются локальным ключом.

## Хранение ключей

- Android/native: secure storage abstraction поверх device-backed storage.
- Web: browser storage abstraction; это слабее native и остается зоной риска при XSS.
- Приватный ключ не экспортируется из UI.
- Profile показывает contact bundle только с public key.

## Серверная видимость

PocketBase видит только временные signaling events и их metadata: room, target, creator, type, timestamps, SDP/ICE payload. Он не хранит историю сообщений, контакты, вложения или plaintext.

Поле `creator`/`target` — это 15-символьный SHA-256 префикс локального UUID (см. `client/lib/services/signaling/pb_user_id.dart`). Маппинг **односторонний**: оператор PocketBase не может восстановить UUID юзера из PB-id без полной радужной таблицы по всему пространству UUID. Однако `offer`/`hangup` payload содержит исходный `creatorUuid` (нужен callee для resolve незнакомого caller), поэтому полный UUID **виден** оператору в момент звонка. Это устранимо только переходом на end-to-end шифрование signaling payload — в текущей модели не делается.

WebRTC media шифруется механизмами WebRTC (DTLS-SRTP). PocketBase не переносит media packets.

## Главные риски

- Web storage уязвим к XSS.
- Contact bundle нужно сравнивать/проверять через safety number, иначе возможна подмена public key.
- Metadata звонков в signaling layer видима оператору PocketBase.
- Нет полноценного multi-device key management.
- Нет механизма revoke/rotate для identity key.

## Рекомендации

1. Добавить explicit safety-number verification перед первым E2E-чатом.
2. Усилить Web build CSP и убрать inline script риски.
3. Добавить key rotation/revocation.
4. Добавить TTL cleanup для PocketBase signaling collection.
5. Проверить TURN/TURNS deployment и certificate hygiene.
