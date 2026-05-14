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

## Sessions

_(empty)_
