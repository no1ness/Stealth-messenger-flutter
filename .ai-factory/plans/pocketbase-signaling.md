# PocketBase Signaling

## Scope

PocketBase is the only network signaling service in the current architecture.
It carries temporary WebRTC events:

- `offer`
- `answer`
- `candidate`
- `hangup`

It must not store contacts, message history, call history, plaintext, encrypted message backups, or attachments.

## Runtime Files

- `client/lib/services/signaling/webrtc_signaling_service.dart`
- `client/lib/services/signaling/incoming_call_service.dart`
- `client/lib/services/signaling/peer_resolver.dart`
- `client/lib/p2p_service.dart`
- `client/lib/ui/screens/webrtc_call_screen_native_impl.dart`
- `client/lib/ui/screens/webrtc_call_screen_web.dart`

## Required Env

```env
POCKETBASE_URL=https://signal.example.com
TURN_URL=turn:example.com:3478
TURN_USERNAME=
TURN_PASSWORD=
TURNS_URL=turns:example.com:443?transport=tcp
TURNS_USERNAME=
TURNS_PASSWORD=
```

## Rules

- Signaling payloads are transient and should be cleaned up with TTL.
- Message history remains local.
- Contact exchange uses local contact bundles.
- Any future directory/discovery feature must be scoped separately.
