# ⚡ Оптимизация тестов — Implementation Plan

**Branch:** `feature/test-speed-optimization-implementation`
**Created:** 2026-06-19
**Based on:** `.ai-factory/plans/test-speed-optimization.md` (стратегия)

---

## 🎯 Цель

Сократить время E2E-прогона пачки сценариев (registration + call + chat) с текущих ~3×75s = 225s до **<120s**, без решения IndexedDB-проблемы (AES-GCM master key несохраняем между сессиями).

---

## 📐 Настройки

| Параметр | Значение |
|---|---|
| Тесты | Включены |
| Логирование | Verbose (DEBUG) |
| Документация | Mandatory checkpoint |
| Milestone | M12 — Two-device manual QA program |

---

## 🧠 Ключевые решения

1. **IndexedDB блокирует полноценный session snapshot** между запусками (`storageState` не копирует IndexedDB, AES-GCM ключ `extractable: false`). Принимаем: переиспользуем контекст в рамках одного процесса (вариант A), но не сохраняем сессию между запусками (варианты C/D откладываем).
2. **Главный тормоз сейчас** — `field.focus()` (~35s) из-за Playwright stability checks на CanvasKit DOM. Нашли рабочий path, ускорение без изменения Flutter engine невозможно.
3. **DRY-рефакторинг** — `registerUser`, `readPbToken`, `pbId` растащены по 3 файлам. Выносим в `core/scenario-helpers.mjs`.

---

## 📋 Задачи

### Phase A — DRY + Ускорение Runner (high impact, ~10-15s savings)

#### A1: Вынести shared helpers в `core/scenario-helpers.mjs`

**Файлы:**
- NEW `pw-test/core/scenario-helpers.mjs`
- EDIT `pw-test/scenarios/registration.mjs`
- EDIT `pw-test/scenarios/call-basic.mjs`
- EDIT `pw-test/scenarios/chat-basic.mjs`

**Что сделать:**
- Перенести `registerUser()`, `readPbToken()`, `pbId()`, `decodeBundle()`, `dummySdp` в общий файл
- Все три сценария импортируют из одного места
- `registerUser()` использует единый код (сейчас registration.mjs отличается от call/chat)

**Логирование:**
- DEBUG: `[helpers] registerUser(${nickname}) start`
- INFO: `[helpers] registerUser(${nickname}) done in Xms`
- WARN: если a11y retry потребовался

**Критерий:** все 3 сценария проходят после рефакторинга

---

#### A2: Reuse browser context между сценариями

**Файлы:**
- EDIT `pw-test/core/runner.mjs`
- EDIT `pw-test/core/client.mjs`

**Что сделать:**
- Раннер регистрирует обоих пользователей ОДИН раз перед запуском сценария
- Передаёт `{ alice, bob }` в сценарий уже готовыми (на Chats screen)
- Сценарии call/chat не вызывают `registerUser()` — они уже залогинены
- `Client.launch()` опционально принимает уже готовый `browser` (переиспользование инстанса)
- Добавить метод `Client.register(nickname)` — обёртку над registerUser

**Логирование:**
- INFO: `[runner] registering users once`
- DEBUG: замер времени регистрации
- INFO: `[runner] scenario ${name} started (users pre-registered)`

**Критерий:** call и chat сценарии не регистрируются повторно, экономя ~75s каждый

---

#### A3: Добавить `--headless` флаг в runner и config

**Файлы:**
- EDIT `pw-test/config.mjs` — добавить `HEADLESS` (default: true)
- EDIT `pw-test/core/client.mjs` — использовать `HEADLESS` в `launch()`
- EDIT `pw-test/core/runner.mjs` — прокидывать флаг

**Что сделать:**
- `config.mjs`: `const HEADLESS = process.env.STEALTH_HEADLESS !== "false"` (default true)
- `Client.launch()`: передавать `headless: HEADLESS`
- Убедиться, что `SCREENSHOT_ON_FAILURE` тоже конфигурируется

**Логирование:** не требуется (infra)

**Критерий:** `STEALTH_HEADLESS=false` запускает headed режим для дебага

---

#### A4: Screenshot-on-failure в runner

**Файлы:**
- EDIT `pw-test/core/runner.mjs`
- EDIT `pw-test/core/client.mjs` — добавить `screenshot(path)`

**Что сделать:**
- В `catch` блоке runner: сохранять скриншоты `alice-page-fail.png`, `bob-page-fail.png`
- `Client.screenshot(path)`: `await this._page.screenshot({ path })`
- Сохранять рядом с `run.mjs` или в `pw-test/artifacts/`

**Логирование:**
- WARN: `[runner] screenshot saved: ${path}`

**Критерий:** при падении сценария скриншот сохраняется

---

### Phase B — CanvasKit Input Acceleration (medium impact, ~5-10s savings)

#### B1: Ускорить `typeIntoFlutterTextField` через `page.keyboard.insertText`

**Файлы:**
- EDIT `pw-test/core/flutter-helpers.mjs`

**Что сделать:**
- Исследовать: после `field.focus()` (через a11y, ~35s) можно ли вызывать `page.keyboard.insertText(text)` вместо evaluate с dispatchEvent?
- `insertText` CDP команда отправляет trusted InputEvent — Flutter должен обработать
- Если работает: заменить evaluate блок на `insertText`, убрать `delay(200)` в конце

**Логирование:**
- DEBUG: `[type] focus done in Xms`
- DEBUG: `[type] insertText done in Yms`

**Критерий:** Скорость typing < 2s после focus (сейчас evaluate ~400ms, но insertText может быть быстрее)

---

### Phase C — Лёгкие победы (low impact, ~2-5s savings each)

#### C1: Убрать `delay(2000)` после клика по Chats в call/chat сценариях

**Файлы:**
- EDIT `pw-test/scenarios/call-basic.mjs`
- EDIT `pw-test/scenarios/chat-basic.mjs`

**Что сделать:** Заменить на waitForSelector конкретного элемента (например, `[role="tab"]`) вместо слепого delay

**Логирование:** не требуется

---

#### C2: Добавить таймауты для скриншотов и экспорт в CI-артефакты

**Файлы:**
- EDIT `.github/workflows/ci.yml` (если существует)

**Что сделать:** В `pw-test-e2e` job добавить upload артефактов при failure

**Логирование:** не требуется

---

### Phase D — Chats/Contacts E2E (если успеваем)

#### D1: Реализовать send message через PB API

**Файлы:**
- EDIT `pw-test/scenarios/chat-basic.mjs`

**Что сделать:**
- После регистрации: Alice отправляет сообщение через PB API напрямую (dummy offer с purpose chat или через DataChannel API)
- Bob ожидает `MessageReceived` event
- Это проверяет P2P DataChannel без UI-взаимодействия

**Логирование:**
- INFO: `[chat] message sent via PB`
- INFO: `[chat] Bob received message`

---

#### D2: Add Contact через PB API

**Файлы:**
- EDIT `pw-test/scenarios/chat-basic.mjs`

**Что сделать:**
- Alice и Bob добавляют друг друга как контакты через прямой запрос к PB (коллекция `user_contacts` или `user_profiles`)
- Проверка: контакт появляется в UI

---

## 📊 Ожидаемые результаты

| Фаза | Экономия | Кумулятивно |
|---|---|---|
| A2 (reuse context) | ~150s (две регистрации) | 225s → 75s |
| A1, A3, A4, C1 | ~5s | 75s → 70s |
| B1 (insertText) | ~5s если сработает | 70s → 65s |
| Phase D | Новые тесты | — |

**Итог после A2:** пачка (registration + call + chat) = **~75s** (один раз регистрация, call/chat до~0s)
**Итог после всех фаз:** **~65-75s** за всю пачку

---

## 🔗 Milestone Linkage

**Milestone:** M12 — Two-device manual QA program
**Rationale:** Ускорение E2E тестов — prerequisites для pre-release QA цикла на двух устройствах. Быстрые тесты позволяют чаще гонять регрессию.

---

## 🔒 Constraints

- Не трогаем `extractable: false` в `storage_service_web.dart` (security hardening)
- Не меняем `RegistrationScreen` или `IdentityService.registerUser` — UI-флоу должен остаться нетронутым для production
- Все изменения только в `pw-test/` и `.github/workflows/`

---

## 📝 Commit Plan

| Commit | Задачи | Сообщение |
|---|---|---|
| 1 | A1 | `refactor(pw-test): extract shared helpers into scenario-helpers.mjs` |
| 2 | A2, A3 | `perf(pw-test): reuse browser context across scenarios, add --headless flag` |
| 3 | A4 | `feat(pw-test): add screenshot-on-failure` |
| 4 | B1 | `perf(pw-test): explore insertText for flutter typing` |
| 5 | C1, C2 | `chore(pw-test): replace hardcoded delays, add CI artifacts` |
| 6 | D1, D2 | `feat(pw-test): chat E2E with PB API messaging` |
