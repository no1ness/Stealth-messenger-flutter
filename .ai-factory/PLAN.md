# Active Plan: Local-First Stealth

## Цель

Закрепить архитектуру: local-first storage, E2E encryption, WebRTC/P2P delivery, PocketBase only for transient signaling.

## Готово

- Runtime client больше не инициализирует внешний cloud backend для контактов/истории.
- UI использует `LocalAppService`.
- Контактный обмен требует локальный contact bundle с public key.
- WebRTC call signaling и DataChannel signaling идут через PocketBase.
- Удалены cloud sync service, cloud service facade, SQL migrations и старые diagnostic tools.

## Следующие задачи

1. Запустить `flutter pub get` после установки Flutter/Dart в PATH.
2. Запустить `flutter analyze` и исправить оставшиеся analyzer замечания.
3. Обновить E2E scripts под contact bundle exchange на всех платформах.
4. Проверить два устройства: контактный bundle, чат, P2P DataChannel, аудио/видеозвонок.
5. Решить, нужен ли PocketBase для address-book discovery; если да, хранить только public directory metadata, не историю.
