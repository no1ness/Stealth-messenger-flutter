# M15 — DH Double Ratchet design (PFS upgrade)

**Roadmap milestone:** [M15 — Cryptographic upgrade: DH Double Ratchet (PFS)](../.ai-factory/ROADMAP.md) (`Future direction, awaiting prerequisite`)
**Status:** design document; no code changes
**Created:** 2026-05-19
**Author:** /aif-implement (M15 scope)
**Prerequisite:** none for design; for implementation, M3 (PocketBase identity contract) must be sealed (it is)
**Companion docs:** `docs/SECURITY.md` (current threat model), `client/lib/crypto/ratchet_service.dart` (current implementation, called out as **NOT** the Signal Double Ratchet in its own doc comment)

This document specifies the upgrade from the project's current **symmetric KDF chain** to a **Signal-style Double Ratchet** that provides Perfect Forward Secrecy (PFS) and Post-Compromise Security (PCS). **No code is changed in this PR.** It is a design + migration plan for review.

---

## TL;DR

1. **Current state:** `RatchetService` is a deterministic symmetric chain rooted at the X25519 ECDH shared secret. A leak of the root chain key compromises **every past and future message** in that conversation. There is no PFS, no PCS, no key deletion. The implementation's own doc comment says so (`ratchet_service.dart:7–18`).
2. **Target state:** Signal-style Double Ratchet — a DH ratchet (root chain) updates every time the direction of conversation flips, plus a symmetric ratchet per direction. Per-message keys are derived once and deleted; DH private keys are deleted on acknowledgment. PFS: a leak at time T cannot decrypt messages from before T. PCS: a leak at time T is healed by any subsequent DH flip the attacker doesn't observe.
3. **Migration strategy:** envelope version negotiation. Existing v1 conversations stay v1 until both peers signal v2 capability; new conversations default to v2. Two-phase rollout, no flag day.
4. **Scope cost:** ~400–600 LOC across `ratchet_service.dart` (or its successor `double_ratchet_service.dart`), `LocalDatabaseService` (per-conversation ratchet state), the message envelope schema, plus ~150 LOC of tests including a regression vector suite cross-checked against `libsignal-protocol-c` test vectors.
5. **Open questions for owner:** group chat semantics (M-speculative), state-corruption recovery story, what to do with the existing v1 chains on rollout day (re-key vs grandfather).

---

## Part 1 — Current state

### What `RatchetService` actually does

From `client/lib/crypto/ratchet_service.dart` (full file is ~120 LOC):

```dart
// Per-message key derivation:
mkMac = HMAC-SHA256(currentChainKey, 0x01)  // messageKey
ckMac = HMAC-SHA256(currentChainKey, 0x02)  // nextChainKey

// To get the Nth message key:
SecretKey getNthMessageKey(rootChainKey, N) {
  current = rootChainKey;
  for (i = 0; i <= N; i++) {
    (msg, current) = advanceSymmetricRatchet(current);
  }
  return msg;
}
```

The root chain key comes from `X25519(myStaticPrivKey, theirStaticPubKey)` — the same shared secret across the entire lifetime of the conversation. `getNthMessageKey(rootKey, N)` is **stateless and deterministic**: peers don't need to store per-message ratchet state because both sides can recompute any historical key from the root.

### What this gets us — and doesn't

**Gets us:**
- Per-message AES-256-GCM keys (no key reuse across messages).
- Stateless peers: no per-conversation ratchet state to corrupt or migrate.
- Deterministic out-of-order tolerance: receive message 7 before message 5? Just compute `getNthMessageKey(rootKey, 5)` whenever message 5 arrives.

**Does not get us:**
- **No PFS.** Root key compromise = every message ever sent in the conversation compromised, retroactively. Mainstream messengers (Signal, WhatsApp, iMessage) have offered PFS for ~10 years.
- **No PCS.** If an attacker steals the root key and walks away, every future message is also compromised. The conversation can never heal.
- **No key deletion.** `getNthMessageKey` recomputes from root every time, so the root and every chain key are kept in memory / storage forever.
- **Single point of failure.** The root key is in `StorageService` (which goes through `flutter_secure_storage_x`); a single device compromise compromises that conversation's entire history.

### What `docs/SECURITY.md` currently says

The doc was updated in M6 (post-pocketbase-hardening Phase 6) to explicitly *not* claim PFS. The claim is honest about the limitation, not a denial that the limitation matters. M15 closes the gap.

---

## Part 2 — Target design

The target is the **Signal Double Ratchet** as specified by Open Whisper Systems (now Signal Foundation). Reference: https://signal.org/docs/specifications/doubleratchet/ — this design follows the spec; deltas are called out explicitly.

### High-level diagram

```
Peer A's state:                    Peer B's state:
┌──────────────────┐               ┌──────────────────┐
│ rootKey (32B)    │═══════════════│ rootKey (32B)    │  (synced via DH ratchet)
│ sendChain (32B)  │               │ recvChain (32B)  │  (A's send = B's recv)
│ recvChain (32B)  │               │ sendChain (32B)  │  (A's recv = B's send)
│ sendDHkp (priv)  │               │ peerDHPub        │  (A's DH key pair)
│ peerDHPub        │               │ sendDHkp (priv)  │  (B's DH key pair)
│ sendN, recvN     │               │ sendN, recvN     │  (message counters)
│ skippedKeys[]    │               │ skippedKeys[]    │  (out-of-order buffer)
└──────────────────┘               └──────────────────┘
```

Every conversation owns its own state (no sharing). State is encrypted at rest in `LocalDatabaseService`.

### Two ratchets, two purposes

**1. Symmetric ratchet (per direction).** Same as the current `RatchetService.advanceSymmetricRatchet`:

```
mk = HMAC(chainKey, 0x01)   // message key
ck = HMAC(chainKey, 0x02)   // next chain key
DELETE chainKey  // <-- new: explicit erasure
```

Each peer has a `sendChain` and a `recvChain`. Sending advances `sendChain` by one; receiving advances `recvChain` by one. Out-of-order: receiver advances `recvChain` ahead, stores the skipped message keys in `skippedKeys[]`, and decrypts the late message later when it arrives.

**2. DH ratchet (per direction flip).** This is what's new vs the current code:

```
On send-after-receive (direction flip from "I was just listening" to "now I'm talking"):
  1. Generate fresh ephemeral DH keypair (X25519): (dhPriv_new, dhPub_new)
  2. dh_shared = X25519(dhPriv_new, peerDHPub)
  3. (rootKey, sendChain) = HKDF(rootKey, dh_shared, "send-direction")
  4. sendN = 0  // reset send-chain counter
  5. Attach dhPub_new in the OUTGOING envelope header
  6. DELETE dhPriv_old  // <-- key deletion: this is where PCS comes from

On receive of a message whose envelope header has a NEW peer DH pubkey:
  1. dh_shared = X25519(myCurrentDHPriv, theirNewDHPub)
  2. (rootKey, recvChain) = HKDF(rootKey, dh_shared, "recv-direction")
  3. peerDHPub = theirNewDHPub
  4. recvN = 0  // reset recv-chain counter
```

The DH ratchet runs at most once per direction flip — typically much less frequent than the symmetric ratchet. Each DH flip mixes new entropy into `rootKey`, which both peers compute independently from their respective shares of the new DH exchange.

### Why this gets PFS and PCS

**PFS:** `dhPriv_old` is deleted on send-after-receive. An attacker who steals the device today cannot recompute past `rootKey` values because the past DH privates are gone. Even if the attacker has `currentRootKey` + `sendChain` + `recvChain`, they cannot derive any earlier chain key (HMAC is one-way, and the DH ratchet folded in fresh entropy at every flip).

**PCS:** an attacker who steals device state at time T learns `currentRootKey` + chains + `dhPriv_current`. They can read messages in the current chain. But the *next* time the conversation flips direction, the legitimate peer generates a fresh DH keypair the attacker doesn't see → the rootKey advances with unknown DH entropy → the attacker can't follow the chain forward. The conversation **self-heals** after one direction flip the attacker doesn't observe.

### Out-of-order message handling

Standard Signal behavior: when receiver expects `recvN = 5` but receives `recvN = 7`:

1. Advance `recvChain` once → compute and store `skippedKeys[recvN=5] = mk5`.
2. Advance again → store `skippedKeys[recvN=6] = mk6`.
3. Now decrypt msg 7 with the chain key at `recvN=7`.
4. When msg 5 (or 6) finally arrives, look up `skippedKeys[5]`, decrypt, then delete the entry.

Skipped-key buffer size: cap at 1000 entries per chain (Signal's default). Beyond that, drop oldest and report `MessageOutOfWindowError` to the caller.

### Envelope schema (v2)

Current v1 envelope (inferred from `encryptMessage`):

```json
{
  "nonce": "<base64>",
  "ciphertext": "<base64>",
  "mac": "<base64>"
}
```

Proposed v2 envelope:

```json
{
  "v": 2,
  "dhPub": "<base64 X25519 pub>",   // sender's current DH ratchet pub (NEW)
  "pn": 12,                         // previous chain's message count (for skip buffer)
  "n":  3,                          // sendN in this chain
  "nonce": "<base64>",
  "ciphertext": "<base64>",
  "mac": "<base64>"
}
```

- `dhPub` is the field that triggers the DH ratchet step on the receiver side. If the receiver has already incorporated this pubkey (it matches their stored `peerDHPub`), they skip the DH ratchet and just advance the symmetric ratchet.
- `pn` ("previous chain length") tells the receiver how many messages they may still need to decrypt from the *previous* recv-chain via `skippedKeys[]`. Needed when the conversation flips direction quickly.
- `n` is the message index within the current send-chain.

**Authenticated-data field**: `dhPub | pn | n` are bound into AES-GCM's AAD so they can't be tampered with without invalidating the MAC.

### State storage

A new table `ratchet_state` in `LocalDatabaseService` (encrypted at rest like everything else):

| Column | Type | Purpose |
|---|---|---|
| `chat_id` | TEXT primary key | one row per conversation |
| `version` | INTEGER | 1 = legacy symmetric, 2 = double ratchet |
| `root_key` | BLOB (encrypted) | 32-byte rootKey |
| `send_chain` | BLOB (encrypted) | 32-byte sendChain |
| `recv_chain` | BLOB (encrypted) | 32-byte recvChain |
| `send_dh_priv` | BLOB (encrypted) | X25519 private (deleted on flip) |
| `send_dh_pub` | BLOB | X25519 public (advertised in envelope) |
| `peer_dh_pub` | BLOB | last seen peer DH pubkey |
| `send_n` | INTEGER | messages sent in current send-chain |
| `recv_n` | INTEGER | messages received in current recv-chain |
| `prev_send_chain_n` | INTEGER | length of the previous send-chain (for `pn` field) |
| `skipped_keys` | JSON BLOB (encrypted) | `{dhPubFingerprint: {n: mk}}` |
| `updated_at` | INTEGER | for debugging only |

The encryption-at-rest uses `StorageService` (already gated by `secure_storage_policy_test.dart`); no new secret-handling primitives are introduced.

---

## Part 3 — Migration plan

### Constraints

- **No flag day.** Users on old clients must still be able to message users on new clients (one direction at a time, for as long as the old user takes to update).
- **No re-keying of existing conversations** if avoidable. Re-keying breaks all in-flight ratchet state and forces every conversation to restart, which is user-hostile.
- **Stateless v1 stays available** for v1↔v1 paths until v1 is sunset (target: post one full release cycle of v2 stability).

### Envelope version negotiation

The envelope `v` field is the negotiation lever:

1. **Sender** that supports v2 always sends v2 envelopes if the conversation state has `version: 2`. Otherwise sends v1 (legacy `RatchetService` codepath).
2. **Receiver** dispatches by envelope version:
   - `v == undefined || v == 1` → call legacy `RatchetService.decryptMessage`.
   - `v == 2` → call new `DoubleRatchetService.decryptMessage`.
3. **Upgrade trigger**: when a v2-capable client receives a v2 envelope from a peer for the first time, it migrates that conversation's `version` to 2 and stores the new state. From then on, send-side emits v2.

### What happens to existing conversations?

Existing conversations on `main` are v1. Two options:

**Option A — Grandfather v1 indefinitely.** Old conversations stay v1 forever; new conversations open with v2. Pros: zero migration risk. Cons: existing users get no security improvement for their existing chats; over time, an increasing fraction of "the conversations that matter" stay vulnerable.

**Option B — Opportunistic re-key.** When both sides are detected to be v2-capable (e.g. via a one-shot signaling-channel handshake), the conversation is re-keyed via a fresh X25519 ECDH and migrates to v2. Pros: existing conversations benefit. Cons: requires a coordinated handshake, recovery story if one side fails mid-migration.

**Recommendation: A first, B later.** Ship A in the M15 implementation PR. Ship B as a separate "M15.1 — Opportunistic v1→v2 re-key" plan once the v2 codepath has been live ~30 days with no incident reports.

### Detection of v2 capability

The simplest detection mechanism: every contact-bundle exchange (`stealth:<base64url(json)>` URL) carries a `protocolVersion` field. Old bundles (no field) → v1. New bundles → v2. On connection setup, both sides see each other's max-supported version and pick the lower. This is the same pattern TLS uses for cipher negotiation.

For *existing* contacts who've already exchanged bundles before the protocolVersion field existed: their bundles in the local DB don't carry the field. Treat the absence as "v1 only" (don't upgrade unless they re-share their bundle, which they'd do anyway when re-installing or rotating keys).

---

## Part 4 — Testing strategy

Settings (per the original project plan): **testing = yes** (crypto plans require regression tests).

### Test categories

1. **Unit tests** for `DoubleRatchetService`:
   - DH ratchet step produces deterministic output given fixed seeds.
   - Symmetric ratchet advances correctly; key deletion called on every advance.
   - Skipped-key buffer caps at 1000; eviction is FIFO.
   - Out-of-order message decryption succeeds for `pn` < 1000, fails predictably for `pn` >= 1000.

2. **Vector tests** cross-checked against `libsignal-protocol-c` reference vectors. The Signal Double Ratchet has published test vectors (KAT — Known Answer Tests). Port a subset to Dart and assert byte-for-byte equivalence. This is the regression gate that proves we implement the *spec*, not "something that looks like the spec".

3. **Integration tests** for migration:
   - v1 envelope received by v2 client → decrypts via legacy path, conversation stays v1.
   - v2 envelope received by v2 client (first time on this chat) → conversation migrates to v2, subsequent sends are v2.
   - v2 client tries to send to v1 peer (per protocolVersion negotiation) → sends v1.
   - Storage roundtrip: write `ratchet_state` row, reboot, read back, decrypt a fresh message correctly.

4. **Fuzz/property tests** (optional, but recommended for crypto):
   - Random order of message delivery (shuffle 1000 messages, assert all decrypt correctly).
   - Random direction flips (alternate send/recv at random intervals, assert chains stay in sync).

5. **Existing tests must survive.** `private_key_no_export_test`, `secure_storage_policy_test`, and any signaling smoke tests should pass unmodified. The DoubleRatchet state goes through `StorageService` exactly like every other sensitive key, so `secure_storage_policy_test` automatically gates it.

### Test code location

- `client/test/crypto/double_ratchet_service_test.dart` (NEW) — unit + property tests.
- `client/test/crypto/double_ratchet_vectors_test.dart` (NEW) — KAT vectors.
- `client/test/crypto/migration_v1_to_v2_test.dart` (NEW) — integration tests for envelope-version dispatch.
- `client/test/security/secure_storage_policy_test.dart` (existing) — should auto-cover the new `ratchet_state` blobs once they go through `StorageService`.

---

## Part 5 — SECURITY.md threat-model updates

Once M15 lands, `docs/SECURITY.md` needs the following deltas:

### Add: "Forward and post-compromise secrecy" section

> The Stealth client uses a Signal-style Double Ratchet for v2 conversations. Past messages remain secret if a device is compromised today (PFS), and ongoing conversations heal after any direction flip the attacker does not observe (PCS). Legacy v1 conversations (opened before client version X.Y) do NOT have PFS or PCS — see "Migration" below.

### Update: "What an attacker with device access can decrypt"

Replace the current vague statement with a specific matrix:

| Attacker capability | v1 conversation | v2 conversation |
|---|---|---|
| Reads `root_chain_key` from disk at time T | Every message, past + future | Current chain only; healed at next DH flip |
| Steals `messageKey` for one message | One message only | One message only |
| Records device → reboots → reads state | Every message, past + future | Future messages on current chain until next flip |

### Update: "Future-work" pointers

Remove the "Double Ratchet upgrade is future-work" pointer (it's no longer future-work post-M15) and replace with:

> The Double Ratchet implementation follows the Signal specification (Open Whisper Systems, 2016). KAT regression vectors are cross-checked against `libsignal-protocol-c`. The migration path from v1 to v2 is documented in `docs/m15-pfs-ratchet-design.md`.

---

## Part 6 — Open questions for the project owner

1. **v1 re-key strategy (Migration Option A vs B).** Recommendation is A first, B later, but the user might prefer to ship both at once to avoid the "we have two ratchet versions in production" phase.
2. **Group chat.** Currently 1:1 only (per ROADMAP.md speculative list). Double Ratchet doesn't compose cleanly to N:N — Signal uses the Sender Keys protocol (a separate construction) for groups. If group chat is on the long-term roadmap, the M15 design should leave room for it; the proposed envelope schema (with `dhPub` in the header) is compatible with later adding a Sender-Keys-style group envelope.
3. **State corruption recovery.** If `ratchet_state` row gets corrupted (disk bit-flip, app crash mid-write), the conversation becomes undecryptable. Recovery options: (a) hard-reset that conversation back to v1 fresh ECDH, (b) snapshot every Nth message and restore-then-replay. Recommendation: hard-reset with a user-visible "this conversation was reset because crypto state corruption was detected" warning. Belongs in scope or out?
4. **Library vs from-scratch.** Building Double Ratchet from primitives (HMAC, X25519, HKDF, AES-GCM — all available via `cryptography` package) is ~400 LOC. Using a higher-level library that bundles the protocol (libsignal-protocol-dart exists, if maintained) is ~50 LOC but adds a vendor surface. **Recommendation: from-scratch with KAT vectors as the correctness gate.** Lower vendor risk, fits the project's self-reliance posture. Open to disagreement.
5. **Key deletion strategy on iOS.** `flutter_secure_storage_x` uses Keychain on iOS; deletion is effective but the Keychain may keep deleted-item metadata. Document the limitation in SECURITY.md.

---

## Part 7 — Implementation plan (when M15 unblocks)

When the owner is ready to ship M15, the implementation plan is:

```
/aif-plan full
  Implement Signal-style Double Ratchet (PFS + PCS) per docs/m15-pfs-ratchet-design.md.
  Backward-compatible envelope versioning. v1 stays available; v2 is opt-in via
  protocolVersion negotiation in contact bundles.
```

Suggested phase split for the full plan:

- **Phase 1:** `DoubleRatchetService` core (~200 LOC) + KAT vector tests.
- **Phase 2:** `ratchet_state` table in `LocalDatabaseService` + state persistence + storage tests.
- **Phase 3:** Envelope v2 schema + sender/receiver dispatch in `P2PService` (or wherever encrypt/decrypt is currently called).
- **Phase 4:** `protocolVersion` field in contact bundles + capability detection.
- **Phase 5:** SECURITY.md update + threat-model matrix.
- **Phase 6:** Migration Option A grandfather behavior, regression-tested.
- **Future:** Option B (`/aif-plan full opportunistic v1 to v2 re-key`).

Estimated total scope: 600–900 LOC of code + 250 LOC of tests + 50–100 LOC of docs. Probably 2–4 work sessions depending on KAT-vector porting velocity.

---

## Next concrete step

When ready, the owner answers the 5 open questions above (especially #1, #3, #4) and then `/aif-plan full` is invoked with this document as input. The plan will reference this design doc as its primary requirements source.

No further work is recommended on this design doc until owner input arrives — adding more depth without that input would be speculative.
