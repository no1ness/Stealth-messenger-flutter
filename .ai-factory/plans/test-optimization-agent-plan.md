🧠 Plan: Optimization of E2E Test System (Stealth Messenger)
🎯 Goal

Transform current E2E system (pw-test, Playwright + Appium + emulator scripts) into:

deterministic
fast (<60s full suite)
fully automated
low-flakiness system
capable of testing:
chat
encryption
WebRTC calls
file transfer
PocketBase signaling
⚠️ Current Problems (must be detected by agent)

Agent must first analyze repository and confirm:

Performance issues
excessive use of sleep()
emulator cold start dependency
Appium used for core flows
UI-driven contact creation
no event synchronization layer
Stability issues
flaky WebRTC handshake timing
signaling race conditions (PocketBase SSE)
no deterministic test state reset
Architecture issues
no test API layer in Flutter client
no headless multi-client abstraction
tests depend on UI instead of protocol
🧩 Phase 1 — Introduce Test Control Layer (CRITICAL)
Task 1.1: Add TestController (Flutter debug-only)

Agent must implement:

class TestController {
  Future<void> login(String userId);
  Future<String> getBundle();
  Future<void> addContact(String bundle);

  Future<void> sendMessage(String to, String text);

  Future<void> startCall(String to);
  Future<void> acceptCall();
  Future<void> hangup();

  Stream<TestEvent> events;
}
Requirements:
only enabled in debug/profile
exposed via window.test (web)
or debug HTTP/WebSocket server
must NOT exist in release builds
Task 1.2: Event System (mandatory)

Agent must implement deterministic event stream:

Events:

MessageSent
MessageReceived
ContactAdded
CallOfferCreated
CallAnswered
IceConnected
CallEnded

✔ Tests MUST rely on events, not sleep

🚀 Phase 2 — Replace UI-driven tests with Headless Clients
Task 2.1: Remove UI dependency from core tests

Agent must refactor:

NO UI clicks for:
login
contacts
messaging
calls

Replace with:

window.test.*
Task 2.2: Introduce Multi-Client Runner

Replace Appium/emulator flows with:

Web mode (primary)
Playwright

Run:

2 isolated browser contexts
fake media streams enabled
--use-fake-device-for-media-stream
--use-fake-ui-for-media-stream
Task 2.3: Multi-client abstraction

Agent must implement:

class Client {
  constructor(context)

  login()
  getBundle()
  addContact()
  sendMessage()
  startCall()
  waitEvent()
}
📡 Phase 3 — Deterministic Synchronization Layer
Task 3.1: Replace all sleeps

Agent must remove:

sleep()
fixed timeouts
polling loops

Replace with:

await client.waitForEvent("MessageReceived")
await client.waitForEvent("IceConnected")
Task 3.2: Introduce event bus matcher

Implementation requirement:

waitForEvent(type, timeout)

With:

strict ordering support
per-client event isolation
📞 Phase 4 — WebRTC Test Verification Layer

Agent must validate calls at 3 levels:

Level 1 — Signaling
offer sent
answer received via PocketBase
Level 2 — ICE

via WebRTC:

iceConnectionState == connected
Level 3 — Media
inbound RTP packets exist
outbound RTP exists
🧪 Phase 5 — Test Suite Refactor
Task 5.1: Replace pw-test scripts

Current:

appium-web-call-test.mjs
emulator orchestration scripts

New structure:

pw-test/
  core/
    client.mjs
    events.mjs
    webrtc.mjs

  scenarios/
    chat-basic.mjs
    call-basic.mjs
    file-transfer.mjs
Task 5.2: Standard scenario format
export default async function scenario(env) {
  const A = await env.createClient()
  const B = await env.createClient()

  await A.login()
  await B.login()

  await A.addContact(await B.getBundle())
  await B.addContact(await A.getBundle())

  await A.sendMessage(B, "hello")

  await B.waitForEvent("MessageReceived")
}
⚡ Phase 6 — Performance Optimization
Task 6.1: Remove emulator dependency (default path)

Agent must:

stop using Android emulator for CI path
keep only for smoke tests
Task 6.2: Parallel execution

All tests must support:

parallel client execution
isolated contexts
no shared state
Task 6.3: Reduce startup time

Target:

Metric	Before	After
full suite	5–10 min	<60 sec
call test	40–90 sec	<10 sec
🧱 Phase 7 — CI Integration

Agent must integrate:

GitHub Actions pipeline
split:
fast tests (web)
slow tests (emulator)

Rule:

PR gating = web-only tests
nightly = full matrix
🔒 Constraints

Agent MUST ensure:

no production code leakage (TestController disabled in release)
no raw user ID contact creation
bundle-only contact system preserved
encryption layer untouched
🧠 Success Criteria

System is considered optimized when:

no sleep() in E2E core
100% tests event-driven
2-client scenarios run in <60s
WebRTC calls validated deterministically
emulator used only for fallback
🚀 Optional Advanced Phase (future)
simulate packet loss / latency injection
chaos testing for ICE failures
replay system for call traces
deterministic cryptographic test vectors