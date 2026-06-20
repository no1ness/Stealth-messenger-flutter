# ⚡ Stealth Messenger — Test Speed Optimization Plan

## 🎯 Goal

Reduce full E2E test runtime from **5–10 minutes → <60 seconds** by eliminating redundant work:

* no repeated builds
* no repeated service startups
* no cold environments
* no UI-driven flows

---

## 🧠 Core Principle

```
BUILD ONCE → REUSE MANY TIMES
```

---

## ⚠️ Current Bottlenecks

### 1. Repeated Flutter builds

* `flutter build web` executed per test run
* wastes 30–120 seconds each time

### 2. Servers restarted every run

* PocketBase
* TURN
* Web server

### 3. Cold-start environment

* browser launched per test
* no session reuse
* WebRTC ICE always cold

### 4. No state reuse

* login every time
* contact exchange every time

---

## 🚀 Optimization Plan

---

# Phase 1 — Build Caching

## Task 1.1: Separate build from test

### ❌ Current

```
flutter build web
run tests
```

### ✅ Target

```
# run only when code changes
flutter build web → /build-cache/web/

# tests reuse build
run tests
```

---

## Task 1.2: Add build hash check

Implement:

* hash of `lib/`, `pubspec.lock`
* rebuild only if hash changes

---

## Task 1.3: Static build directory

```
/build-cache/web/
```

Tests must serve files from this directory only.

---

# Phase 2 — Persistent Runtime Services

## Task 2.1: Do NOT start services inside tests

Remove:

* PowerShell orchestration
* per-test server startup

---

## Task 2.2: Use persistent services via Docker

Use:

* PocketBase
* TURN server

via:

```
docker compose up -d
```

Run once, reuse always.

---

## Task 2.3: Health check instead of restart

Tests must:

```
wait until service is ready
```

NOT:

```
restart service
```

---

# Phase 3 — Persistent Web Server

## Task 3.1: Replace per-test server start

### ❌ Current

* start server per test

### ✅ Target

* single long-running dev server

```
node dev-server.js
```

---

## Task 3.2: Reuse server between test runs

Tests connect to:

```
http://localhost:58585
```

---

# Phase 4 — Browser Reuse

## Task 4.1: Single browser instance

### ❌ Current

* launch browser per test

### ✅ Target

```
global.browser = launch once
```

---

## Task 4.2: Use contexts per test

```
browser.newContext()
```

Isolation without restart.

---

# Phase 5 — Session Snapshot

## Task 5.1: Save authenticated state

After login + contacts:

```
context.storageState({ path: 'state.json' })
```

---

## Task 5.2: Reuse state

```
newContext({ storageState: 'state.json' })
```

Removes:

* login
* bundle exchange

---

# Phase 6 — In-Memory Test Mode

## Task 6.1: Add TEST_MODE

```
TEST_MODE=true
```

---

## Task 6.2: Behavior in test mode

* in-memory DB
* deterministic identity
* fixed keys
* no disk IO

---

# Phase 7 — WebRTC Warmup

## Task 7.1: Pre-warm ICE

Before tests:

* create call
* immediately hang up

---

## Result

* ICE cache populated
* TURN ready
* faster connection setup

---

# Phase 8 — Parallel Execution

## Task 8.1: Enable parallel tests

* 2–4 concurrent tests max

---

## Constraint

* avoid TURN overload
* avoid ICE collisions

---

# Phase 9 — Test Tiering

## Task 9.1: Split test types

### Fast (PR)

* messaging
* signaling

### Medium

* basic WebRTC

### Heavy (nightly)

* full calls
* attachments

---

# Phase 10 — Unified Test Runner

## Task 10.1: Replace PowerShell scripts

### ❌ Current

* emulator start
* appium start
* server start

### ✅ Target

Single command:

```
node test-runner.js
```

---

## Task 10.2: Runner responsibilities

* check services
* reuse environment
* start tests immediately

---

# 📊 Expected Performance Gains

| Step                | Improvement |
| ------------------- | ----------- |
| remove rebuild      | -30–120 sec |
| persistent services | -20–60 sec  |
| browser reuse       | ×5 faster   |
| snapshot login      | -5–15 sec   |
| ICE warmup          | -3–10 sec   |

---

## 🎯 Final Target

```
Full suite runtime: 20–40 seconds
```

---

# 🧠 Success Criteria

* no `flutter build` during tests
* no service restart during tests
* no browser relaunch per test
* no login per test
* no cold WebRTC start

---

# 🚀 Future Improvements (Optional)

* network simulation (latency / packet loss)
* deterministic TURN behavior
* call trace replay
* CI caching of build artifacts

---

# 🔒 Constraints

* TestController disabled in release builds
* bundle-based contacts only
* encryption must remain intact

---

# 🧩 Summary

Speed comes from:

* eliminating repetition
* reusing state
* keeping environment warm

NOT from optimizing test code itself.
