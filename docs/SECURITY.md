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

Все cryptographic material и auth credentials идут через
`StorageService` — единственную абстракцию для secure storage. Список
sensitive-ключей и политика hardcoded в doc-комментарии
[`client/lib/storage_service.dart`](../client/lib/storage_service.dart);
regression-тест
[`client/test/security/secure_storage_policy_test.dart`](../client/test/security/secure_storage_policy_test.dart)
проверяет что ни один из них не попадает в `SharedPreferences`
напрямую.

| Платформа | Backend `StorageService` | Защита |
|-----------|--------------------------|--------|
| iOS / Android | `flutter_secure_storage_x` | Keychain (iOS), EncryptedSharedPreferences (Android) — device-backed |
| Web | Non-extractable AES-256-GCM ключ в IndexedDB через Web Crypto, ciphertext в `SharedPreferences` | Master-ключ нельзя выгрузить из IndexedDB, что блокирует XSS-exfiltration. Все sensitive значения шифруются client-side перед сохранением |
| Stub (fallback) | Plain `SharedPreferences` | **Не безопасно** для sensitive material; используется только если platform detection не сработал |

Sensitive ключи (обязательно через `StorageService`): `privateKey`,
`publicKey`, `pb_token`, `pb_password`, `pb_user_id`, `local_db_key`,
`group_key_<chatId>`, `userId`, `nickname`, `registeredAt`, а также
зарезервированные слоты для key rotation (`privateKey_prev`,
`publicKey_prev`, `prev_rotated_at`).

Низкочувствительные UI-настройки (`themeMode`, `useP2P`) разрешены в
`SharedPreferences` напрямую — это явная политика, не упущение.

Приватный ключ не экспортируется из UI. Regression-guard:
[`client/test/security/private_key_no_export_test.dart`](../client/test/security/private_key_no_export_test.dart).
Profile показывает contact bundle только с public key.

## Safety number verification

После добавления контакта по `stealth:<bundle>` оба пира должны
сравнить **safety number** out-of-band (вживую, по другому защищённому
каналу, по телефону). Это единственная защита от MITM-подмены
public-key в bundle.

- **Что это:** SHA-256(ownPublicKey || ":" || otherPublicKey),
  base64-кодировка, первые 32 символа. Реализация —
  `LocalAppService.getSafetyNumber(otherUserId)`.
- **UI flow:** в `Contacts → long-press → Verify Safety Number`
  открывается диалог
  ([`client/lib/ui/screens/chats/safety_number_dialog.dart`](../client/lib/ui/screens/chats/safety_number_dialog.dart))
  с fingerprint'ом и кнопкой "Mark as verified". Подтверждение
  записывает `verified_at` (ISO-8601) и снимок `verified_safety_number`
  в локальную запись контакта.
- **Индикатор статуса:** в списке контактов рядом с именем — ✓
  (verified) или ⚠ (mismatch: сохранённый snapshot отличается от
  текущего → ключ одной из сторон поменялся, нужна re-верификация).
  Решение: `LocalAppService.isContactVerified(userId)` и
  `LocalAppService.detectSafetyMismatch(userId)`.

Гейт "блокировать первое сообщение/звонок до верификации" — открытая
работа: `chats_screen.dart` и `call_manager.dart` пока работают через
старый сервисный путь и не на Riverpod-провайдерах, поэтому
интеграция отложена до миграции этих экранов.

## Identity key rotation

`LocalAppService.rotateIdentityKeypair()` генерирует свежую X25519
keypair и закладывает 24-часовое окно совместимости с in-flight
сообщениями.

- **Поток:**
  1. Текущие `privateKey`/`publicKey` копируются в
     `privateKey_prev`/`publicKey_prev` плюс `prev_rotated_at`
     (ISO-8601 timestamp).
  2. Генерируется новая keypair и записывается в основные слоты.
  3. Внутренние кеши `_sharedSecretCache` и `_prevSharedSecretCache`
     очищаются.
  4. У всех контактов обнуляется `verified_at` — safety number
     поменялся по построению, требуется re-верификация. Снимок
     `verified_safety_number` остаётся как "было верифицировано до
     ротации".
- **UI:** Profile → Security → "Rotate identity key" вызывает
  подтверждение, объясняющее последствия (новый QR/contact bundle,
  все контакты помечаются ⚠, 24 ч grace для in-flight).
- **Decryption fallback:** `decryptMessage` при сбое AES-GCM пробует
  shared secret, derived через prev-keypair (если `prev_rotated_at`
  ещё в окне). Успех логируется
  `[FIX:local-only] decryptMessage fallback to prev identity key
  succeeded`. По истечении 24 ч prev-материал стирается
  (`_prunePrevKey`) и попытка fallback вернёт `null`.
- **Настройка окна:** `LocalAppService.kPrevKeyGracePeriod`.

> **Что rotation НЕ восстанавливает:** PocketBase-id (`pb_user_id`)
> производный от локального UUID, не от identity-key — он не
> меняется. Signaling-доступ остаётся в силе с тем же PB-аккаунтом.

## Web hardening

Bundle для веба несёт строгий
[Content Security Policy](web-csp.md): `default-src 'self'`,
`script-src 'self'`, никаких external CDN, `object-src 'none'`,
`frame-ancestors 'none'`. Это блокирует XSS-инъекции внешних
скриптов и clickjacking. Smoke-чек и upgrade-path описаны в
`docs/web-csp.md`.

## Серверная видимость

PocketBase видит только временные signaling events и их metadata:
`roomId`, `target`, `creator` (15-char SHA-256 prefix локального
UUID), `type`, `created`/`updated`, SDP/ICE payload. В `offer` и
`hangup` payload дополнительно лежит `creatorUuid` для resolve
неизвестного пира — это закреплённый trade-off
([RESEARCH](../.ai-factory/RESEARCH.md) — Signaling payload E2E
encryption). PocketBase **не** хранит историю сообщений, контакты,
вложения или plaintext.

Старые записи `rtc_signaling` чистятся cron-хуком
[`pb_hooks/rtc_cleanup.pb.js`](../pb_hooks/rtc_cleanup.pb.js):
ежечасный sweep, TTL=24 ч. Это ограничивает окно, в которое
оператор PocketBase может реконструировать call graph.

WebRTC media шифруется механизмами WebRTC (DTLS-SRTP). PocketBase не
переносит media packets.

## Главные риски

- Web storage уязвим к XSS — non-extractable AES-ключ в IndexedDB
  поднимает планку, но не делает невозможным.
- Contact bundle нужно сравнивать через safety number перед первым
  чатом, иначе возможна подмена public key. **Гейт перед первой
  отправкой пока не блокирующий** (см. выше).
- Metadata звонков в signaling layer видна оператору PocketBase
  (timestamps, кто кому). TTL 24 ч ограничивает retention; полное
  скрытие требует payload-encryption (планируется отдельно).
- Identity-key rotation теперь поддерживается, но multi-device key
  management всё ещё отсутствует: каждое устройство — отдельная
  identity.
- TURN/TURNS креды одинаковые для всех пользователей одного
  инстанса.

## Рекомендации (status)

1. ~~Добавить explicit safety-number verification перед первым
   E2E-чатом.~~ Реализована UX-часть (verify dialog + индикатор).
   Блокирующий гейт перед первой отправкой — открытая работа.
2. ~~Усилить Web build CSP и убрать inline script риски.~~ Готово
   (см. `docs/web-csp.md`). Inline-CSS лоадера всё ещё требует
   `style-src 'unsafe-inline'`; вынос в `loading.css` — follow-up.
3. ~~Добавить key rotation/revocation.~~ Готово
   (`rotateIdentityKeypair`, 24 ч grace).
4. ~~Добавить TTL cleanup для PocketBase signaling collection.~~
   Готово (`pb_hooks/rtc_cleanup.pb.js`, TTL 24 ч).
5. Проверить TURN/TURNS deployment и certificate hygiene — открыто.
6. Перейти на настоящий Double Ratchet с PFS — открыто, см.
   `.ai-factory/RESEARCH.md`.
7. Зашифровать signaling-payload (убрать `creatorUuid` и SDP из
   plaintext) — открыто, синхронно с Double Ratchet (общая X3DH
   обвязка).
