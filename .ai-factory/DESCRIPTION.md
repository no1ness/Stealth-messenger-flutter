# Stealth Messenger

## Обзор

Stealth Messenger — кроссплатформенный приватный мессенджер на Flutter с end-to-end шифрованием и архитектурой **local-first / Direct P2P First**. Регистрация без номера телефона: при первом запуске генерируется локальный UUID и пара ключей X25519, приватный ключ никогда не покидает устройство.

Приоритет — приватность и оффлайн-работа. Сообщения и звонки идут напрямую между устройствами через WebRTC; Supabase используется как вспомогательный канал для сигналинга, обхода NAT и резервного хранилища (History Cloud) для синхронизации в фоне.

## Ключевая функциональность

- 1-on-1 и групповые чаты с E2E-шифрованием (X25519 + AES-256-GCM, Double Ratchet)
- Аудио- и видеозвонки через WebRTC P2P
- Мгновенный обмен сообщениями через WebRTC DataChannel (с фоллбэком на Supabase Realtime)
- Обмен зашифрованными файлами и изображениями
- Полная работа в оффлайне: чтение и запись из локальной БД, ленивая синхронизация при появлении сети
- Гибридная доставка: P2P → Supabase Realtime → Background Sync
- Кастомный signal relay для обхода блокировок Supabase
- Дизайн в стиле Apple Liquid (glassmorphism)

## Технологический стек

- **Язык:** Dart (SDK `>=3.0.0 <4.0.0`)
- **Фреймворк:** Flutter (Material + кастомная тема Apple Liquid)
- **Криптография:** `cryptography` (X25519, AES-256-GCM, Double Ratchet)
- **WebRTC:** `flutter_webrtc` (audio/video + DataChannel)
- **Локальная БД:** `idb_shim` (IndexedDB) + `sqflite` для Android, `sembast_io` для FS
- **Безопасное хранилище ключей:** `flutter_secure_storage_x` (Android Keystore)
- **Backend (вспомогательный):** Supabase (PostgreSQL + Realtime + Storage)
- **Service discovery (LAN):** `nsd` (mDNS / Bonjour)
- **Сетевые состояния:** `connectivity_plus`
- **Конфиг и preferences:** `flutter_dotenv`, `shared_preferences`
- **Медиа:** `record`, `audioplayers`, `permission_handler`, `file_picker`
- **E2E-тесты:** Playwright (web), Appium + WebDriverIO (Android), Node.js
- **Линтер:** `flutter_lints`

## Архитектурные решения

- **Local-first.** Все сообщения сначала пишутся в зашифрованную локальную БД, UI читает из неё мгновенно. Облако — резерв.
- **Direct P2P First.** WebRTC PeerConnection + DataChannel для прямого обмена. Если P2P недоступно — фоллбэк на Supabase Realtime.
- **Background Sync.** Каждые ~30 секунд (или при восстановлении сети) локальные сообщения копируются в Supabase. Дедупликация по message ID.
- **Платформенные абстракции.** Файлы вида `storage_service_io.dart` / `storage_service_web.dart` / `storage_service_stub.dart` для разделения web vs native.
- **Тематизация.** `themes/apple_liquid/` содержит виджеты с glassmorphism (`glass_bottom_nav_bar`, `glass_message_input`, `glass_text_field`).
- **Разделение слоёв.** `lib/` — сервисы и доменная логика; `lib/ui/screens/` — экраны (18 шт.); `lib/ui/widgets/` — переиспользуемые виджеты.

## Нефункциональные требования

- **Логирование:** Verbose в dev (детальные DEBUG-логи через `debugPrint`); чувствительные данные не должны попадать в логи.
- **Безопасность:** ключи только в Android Keystore / Web localStorage; вся передача сообщений и файлов — после E2E-шифрования; никаких credentials в репозитории (`.env` в `.gitignore`).
- **Обработка ошибок:** структурированный startup-error экран; восстановление при corrupted secure storage (BAD_DECRYPT) — однократный wipe и retry.
- **Оффлайн-устойчивость:** приложение должно полностью функционировать при `useSupabase=false` (toggle в Settings).
- **Сборка:** Android в первую очередь; Web — second-class; iOS — отключён в `flutter_native_splash` / `flutter_launcher_icons`.

## Точки входа

- `client/lib/main.dart` — bootstrap: инициализация Supabase, выбор offline-режима, recovery от corrupted storage
- `client/lib/registration_screen.dart` — генерация ключей при первом запуске
- `client/lib/main_tabs.dart` — корневая навигация (4 таба: Chats, Contacts, Profile, Settings)
- `client/lib/supabase_service.dart` — ядро: синхронизация, криптография, WebRTC сигналинг (~65 KB)
- `client/lib/local_database_service.dart` — зашифрованное локальное хранилище
- `client/lib/p2p_service.dart` + `p2p_discovery_service.dart` — WebRTC DataChannel и LAN discovery
- `client/lib/sync_service.dart` — фоновая синхронизация локальной БД с Supabase
- `client/supabase/migrations/` — 8+ SQL-миграций схемы БД

## Связанные документы

- `docs/ARCHITECTURE.md` — детальная архитектура с диаграммами БД и потоками данных
- `docs/SECURITY.md` — модель безопасности
- `docs/ТЕХНИЧЕСКОЕ_ЗАДАНИЕ.md` — функциональные требования
- `INSTALL_ANDROID.md` — инструкции по сборке для Android
- `MANUAL_CALL_TEST.md` — сценарий ручного тестирования звонков
- `.ai-factory/PLAN.md` — план активной фазы реализации
