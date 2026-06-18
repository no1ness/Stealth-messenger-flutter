# Testing

## Unit tests (Flutter)

```bash
cd client
flutter test
```

Test coverage via `--coverage`:

```bash
flutter test --coverage
```

## E2E tests (Playwright)

### Prerequisites

```bash
cd pw-test
npm install
npx playwright install chromium
```

### Run scenarios

```bash
# Start a Flutter web dev server (separate terminal):
cd client && flutter run -d web-server --web-port 4444 --web-renderer canvaskit

# In another terminal:
cd pw-test
export STEALTH_WEB_URL=http://127.0.0.1:4444
node scenarios/chat-basic.mjs
node scenarios/call-basic.mjs
node scenarios/registration.mjs
```

### Using npm scripts

```bash
cd pw-test
npm run test:e2e:chat
npm run test:e2e:call
npm run test:e2e:registration
```

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `STEALTH_WEB_URL` | `http://127.0.0.1:57575` | Flutter web app URL |
| `STEALTH_TEST_API_URL` | `http://127.0.0.1:9876` | TestController HTTP API |
| `STEALTH_WEB_PORT` | `4444` | Web server port |

## TestController (debug-only test API)

TestController is a debug-only API available when the app runs in `kDebugMode`.
It exposes an event bus and control methods via HTTP on `localhost:9876`.

### Events

| Event | Fields | Description |
|---|---|---|
| `MessageSent` | `chatId`, `text` | Outgoing message sent |
| `MessageReceived` | `chatId`, `fromUserId`, `text` | Incoming message received |
| `ContactAdded` | `userId` | Contact added |
| `CallOfferCreated` | `roomId`, `targetUserId` | Outgoing call offer |
| `CallAnswered` | `roomId`, `fromUserId` | Incoming call answer |
| `IceConnected` | `roomId` | ICE connection established |
| `CallEnded` | `chatId` | Call ended |
| `Error` | `message` | Test error |

### HTTP API

- `GET /events` — returns pending events as JSON array
- Events are consumed once per poll

### Architecture

```
┌──────────────┐  TestEvent  ┌─────────────────┐  HTTP poll  ┌──────────┐
│ Service      │────────────▶│ TestController   │◀────────────│ Playwright│
│ (callback)   │             │ (event bus)      │────────────▶│ (E2E)    │
└──────────────┘             └─────────────────┘  JSON array  └──────────┘
```

Services emit `TestEvent` via `attachTestEventEmitter()` callbacks.
`TestController` collects events and serves them via HTTP.
E2E tests poll `/events` until expected events appear.
