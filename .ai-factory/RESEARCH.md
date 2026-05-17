# Research Notes

Open research items captured during planning. Not implementation tasks
yet — they live here until promoted into an `aif-plan` entry.

## Active Summary (input for /aif-plan)

- **Topic:** Crypto upgrade — real Double Ratchet on top of X25519
- **Why now:** the current `client/lib/crypto/ratchet_service.dart`
  ships a stateless symmetric KDF chain, NOT a Double Ratchet. The
  hardening plan (Phase 6) made the documentation honest about this,
  but the underlying limitation remains: a leak of any chat's root
  chain key compromises every past and future message in that chat
  (no Perfect Forward Secrecy, no post-compromise security).

## Crypto upgrade: real Double Ratchet (X3DH + DH step per message)

### Goal

Replace the symmetric KDF chain with a true Double Ratchet
construction so that:

1. Every sent message rotates a new DH ephemeral key, so a leak of any
   single message key does not reveal past messages (forward secrecy).
2. The chain self-heals after a single message exchange in each
   direction, restoring confidentiality after a temporary compromise
   (post-compromise security).
3. Out-of-order delivery still decrypts correctly — the recipient
   keeps a small skipped-message-key cache per active chain.

### Sketch

- Bootstrap with X3DH so the first message can be sent before the
  peer is online (matches the Signal X3DH spec: identity key + signed
  pre-key + one-time pre-key bundle).
- Per-direction sending chain seeded by the X3DH shared secret; each
  send re-derives a chain key + message key (HKDF), then ratchets the
  chain key once and discards the previous chain key value.
- DH ratchet step: every time the peer's ephemeral public key
  changes, derive a new root key + sending chain key from
  `HKDF(rootKey, ECDH(ourPrivate, theirPublic))`; rotate our
  ephemeral private key; advertise the new ephemeral in the next
  outbound header.
- Skipped-message-key cache bounded (e.g. 1000 keys / 1 hour per
  chain) to tolerate reordering and dropped messages without
  unbounded memory growth.

### Open questions

- Wire format for the new header (ephemeral pub key + chain
  counters). The PocketBase signaling collection is the wrong place
  for chat-message metadata — this needs to live in the
  P2P/DataChannel envelope.
- Storage layout: per-chain state (root key, chain keys, skipped
  keys) must be persisted and encrypted by the local secure storage
  layer.
- Migration: existing chats only have the symmetric-chain history.
  Either rotate chains at the first new-format message exchange, or
  treat the upgrade as a clean break and let old conversations stay
  on the legacy KDF until both peers update.
- Group chats: Double Ratchet is point-to-point only. For groups we
  need a separate sender-key mechanism (Signal "Sender Keys" / MLS).
  Out of scope for the initial 1:1 implementation.

### Why not now

Substantial cross-cutting change touching crypto, P2P framing,
storage and migration. Tracked as a deliberate follow-up to the
Phase 6 honesty pass; only proceed after the post-PocketBase
hardening plan has landed in main.

## Signaling payload E2E encryption

### Goal

Удалить из видимости оператора PocketBase plaintext-метаданные
звонков: `creatorUuid`, `nickname`, SDP `offer`/`answer`, ICE
`candidate`. Сейчас signaling-сообщения хранятся в `rtc_signaling`
как чистый JSON и читаются server-side при оценке API rules
(`@request.data.creator = @request.auth.id` смотрит только `creator`
поле, но всё тело видно админу инстанса).

### Why now / Why captured

`fix(signaling): use 15-char SHA-256 PB id` (`ae47280`) сознательно
**усугубил** server-side видимость: PB-id поля `creator`/`target`
стали односторонним hash UUID (60 бит), но в payload `offer`/`hangup`
теперь явно лежит полный `creatorUuid` (нужен для resolve callee'ем
неизвестного caller'а). Это закреплённый trade-off — UX resolve
оказался важнее метаданных-приватности при single-tenant self-hosted
signaling.

> **Pre-condition для перехода на E2E signaling:** убрать
> `creatorUuid` из payload как первый шаг, заменив на симметричную
> схему «обе стороны заранее знают друг друга через contact bundle
> exchange до первого звонка». Альтернатива — оставить `creatorUuid`,
> но зашифровать весь payload общим ключом, derived через X25519 +
> contact bundle (см. ниже).

### Sketch

- **Symmetric envelope per recipient pair.** Caller и callee уже
  обмениваются `public_key` через contact bundle (см.
  `docs/getting-started.md`/`local_app_service.dart::searchUsers`).
  ECDH(callerPriv, calleePub) даёт shared secret → HKDF → symmetric
  key. Каждый signaling-payload `seal(plaintext, sharedKey)` →
  AES-256-GCM(nonce || ct || tag).
- **Wire format в `payload`:**
  ```json
  { "v": 1, "n": "<base64 nonce>", "ct": "<base64 ciphertext+tag>" }
  ```
  PocketBase видит только opaque blob; не может прочитать SDP, ICE,
  nickname, или creatorUuid.
- **`creator`/`target` поля остаются открытыми** (нужны для
  PocketBase rules `target = @request.auth.id`). Они уже hash UUID —
  60-bit one-way, что даёт лучший privacy baseline.
- **Resolve unknown caller на receive-side:** перед звонком contact
  bundle уже должен быть обменян. Если нет — signaling payload
  невозможно дешифровать (нет shared key) → callee показывает
  "unknown caller" и предлагает добавить контакт. Это **breaking
  change** для cold-call UX (раньше можно было дозвониться по UUID
  без bundle exchange).

### Open questions

- **Backward compatibility.** Старая сборка отправит plaintext
  payload, новая ждёт sealed envelope. Либо опциональная
  расшифровка (try-seal, fall-back to plaintext с deprecation
  warning), либо version bump `v: 1` → `v: 2` + period co-existence.
- **Key rotation.** Сейчас identity X25519 keypair длительный (на
  всю жизнь установки). Если он скомпрометирован, всё прошлое
  signaling-traffic ретроспективно расшифровывается оператором PB
  (если у того есть сохранённые SSE-логи). Нужен ephemeral DH per
  call, либо хотя бы per session — но это снова про Double Ratchet.
- **Group calls.** Текущее signaling 1:1. Если будут groups,
  envelope становится sender-key или MLS-style — координируется с
  «Crypto upgrade: real Double Ratchet» (sender keys для group).
- **TURN credentials.** TURN/TURNS логин/пароль сейчас фиксированы в
  `.env` и одинаковы для всех пользователей одного инстанса. Это
  отдельный vector ослабления, но к signaling E2E не относится.

### Why not now

- Phase 6.1-6.3 уже сделали `docs/SECURITY.md` честным про текущее
  состояние; `creatorUuid` exposure тоже зафиксирован
  (`docs/SECURITY.md` Section "Серверная видимость").
- Заказчик single-tenant self-hosted deployments — operator-видимая
  метадата звонков не является критической угрозой пока сам инстанс
  доверенный.
- Реализация требует: cryptographic envelope в P2P framing,
  миграция активных чатов, breaking change cold-call UX. Этот объём
  оправдан только синхронно с переходом на Double Ratchet (общий
  crypto upgrade).
- **Promote в `/aif-plan` together with** «Crypto upgrade: real
  Double Ratchet» — обе работы трогают X3DH bundle exchange и
  symmetric/AEAD wrapping.

## Sessions

_(empty)_
