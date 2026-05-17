[← Архитектура](architecture.md) · [Back to README](../README.md) · [Конфигурация →](configuration.md)

# Модель безопасности Stealth Messenger

## Что защищаем

- Приватные ключи пользователя
- Plaintext сообщений
- Вложения до шифрования и после расшифровки
- Локальную историю контактов, чатов и звонков

## Криптография

| Компонент | Алгоритм | Примечание |
|-----------|----------|------------|
| Identity keypair | X25519 | Генерируется на устройстве |
| Private chat secret | X25519 shared secret | Diffie-Hellman key agreement |
| Message encryption | AES-256-GCM | Authenticated encryption |
| Ratchet | Symmetric KDF chain | **НЕ** Double Ratchet, **НЕ** обеспечивает PFS |
| Local DB | Дополнительное шифрование локальным ключом | — |

> **Важно:** текущая реализация ratchet (`client/lib/crypto/ratchet_service.dart`) —
> stateless symmetric KDF chain поверх X25519 shared secret. План перехода на
> настоящий Double Ratchet зафиксирован в `.ai-factory/RESEARCH.md`.

## Хранение ключей

| Платформа | Механизм | Уровень защиты |
|-----------|----------|---------------|
| Android/native | Secure storage (device-backed) | Высокий |
| Web | Browser storage abstraction | Низкий — уязвим при XSS |

- Приватный ключ **не экспортируется** из UI
- Profile показывает contact bundle только с public key

## Серверная видимость

PocketBase видит только временные signaling events и их metadata:
`room`, `target`, `creator`, `type`, timestamps, SDP/ICE payload.

**Не хранит:** историю сообщений, контакты, вложения, plaintext.

Поля `creator`/`target` — 15-символьный SHA-256 префикс локального UUID
(см. `client/lib/services/signaling/pb_user_id.dart`).
Маппинг **односторонний**: оператор PocketBase не может восстановить UUID
из PB-id без полной радужной таблицы.

Однако `offer`/`hangup` payload содержит `creatorUuid` — полный UUID
виден оператору в момент звонка. Устранимо только E2E-шифрованием
signaling payload (в текущей модели не реализовано).

WebRTC media шифруется DTLS-SRTP. PocketBase не переносит media packets.

## Главные риски

- Web storage уязвим к XSS
- Contact bundle нужно верифицировать через safety number (подмена public key)
- Metadata звонков видима оператору PocketBase
- Нет multi-device key management
- Нет механизма revoke/rotate для identity key

## Рекомендации

1. Добавить safety-number verification перед первым E2E-чатом
2. Усилить Web CSP, убрать inline script риски
3. Добавить key rotation / revocation
4. Добавить TTL cleanup для PocketBase signaling
5. Проверить TURN/TURNS deployment и certificate hygiene

## See Also

- [Архитектура](architecture.md) — как устроен проект
- [Конфигурация](configuration.md) — переменные окружения
- [PocketBase Setup](pocketbase-setup.md) — настройка API rules
