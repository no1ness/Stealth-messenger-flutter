// Conditional export of the platform-specific [StorageService] backend.
//
// Backends
// --------
//
// - `storage_service_io.dart`  – iOS/Android. Backed by
//   `flutter_secure_storage_x` (Keychain on iOS, EncryptedSharedPreferences
//   on Android).
// - `storage_service_web.dart` – Web. AES-256-GCM with a non-extractable
//   key generated through Web Crypto and persisted in IndexedDB; the
//   resulting ciphertext is stored in SharedPreferences. The key cannot
//   leave the IndexedDB store, which protects it from XSS exfiltration.
// - `storage_service_stub.dart` – fallback when platform detection fails.
//   Plain SharedPreferences. **NOT** safe for sensitive material.
//
// Sensitive-key policy
// --------------------
//
// The following keys MUST always be read/written through `StorageService`
// (never directly via `SharedPreferences`). They contain cryptographic
// material or auth credentials whose disclosure would let an attacker
// impersonate the user, decrypt past messages, or take over the signaling
// session:
//
// - `privateKey`      — X25519 identity private key (base64).
// - `publicKey`       — X25519 identity public key (base64). Storage
//                       location is kept symmetric with `privateKey` so the
//                       pair always live together; the public value alone
//                       is not secret but mismatched halves break shared
//                       secret derivation.
// - `pb_token`        — PocketBase JWT auth token.
// - `pb_password`     — PocketBase account password (derived on first
//                       login and reused for token refresh).
// - `pb_user_id`      — PocketBase user record id (15-char SHA-256 prefix
//                       of the local UUID; see
//                       `services/signaling/pb_user_id.dart`).
// - `local_db_key`    — symmetric key used by [LocalDatabaseService] to
//                       encrypt message payloads at rest.
// - `group_key_<id>`  — per-group AES-GCM secrets.
// - `userId`,
//   `nickname`,
//   `registeredAt`    — local identity material. Tied to the X25519
//                       keypair above; rotating one without the others
//                       would break message history lookups.
//
// Future additions (placeholder, written as part of Phase 5 of
// `.ai-factory/plans/hardening-di-secure-storage.md`):
//
// - `privateKey_prev`,
//   `publicKey_prev`,
//   `prev_rotated_at`  — short-lived snapshot of the previous identity
//                        keypair kept during the rotation grace window so
//                        in-flight messages encrypted to the old key can
//                        still be decrypted.
//
// Low-sensitivity keys that MAY live in `SharedPreferences` directly
// (no PII, no cryptographic material):
//
// - `themeMode` – UI theme index (Light/Dark/System).
// - `useP2P`    – boolean toggle for direct P2P messaging.
//
// Anything new that does not fit in this second list MUST use
// `StorageService`. A regression guard
// (`test/security/secure_storage_policy_test.dart`) enforces this by
// scanning `lib/` for direct `SharedPreferences` reads/writes of the
// sensitive keys above.

export 'storage_service_stub.dart'
    if (dart.library.io) 'storage_service_io.dart'
    if (dart.library.js_interop) 'storage_service_web.dart';
