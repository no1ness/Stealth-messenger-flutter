# M14 — TURN/relay reliability survey

**Roadmap milestone:** [M14 — TURN/relay reliability](../.ai-factory/ROADMAP.md) (`Committed, not started`)
**Status:** survey + recommendation; no code changes
**Created:** 2026-05-19
**Author:** /aif-implement (M14 scope)

This document surveys the current ICE/TURN configuration in the Stealth client, identifies a bifurcation between two code paths, compares TURN provisioning options, and recommends a path forward. **No code is changed in this PR** — the recommendation requires a stakeholder decision on hosting before implementation can begin.

---

## TL;DR

1. **Real bug found during the survey** (not a hypothetical). The DataChannel path in `client/lib/p2p_service.dart:31` only configures Google STUN; the call media path in `client/lib/ui/screens/calls/native_call_media_bindings.dart:370` configures STUN + TURN/TURNS from env. **Result: text messages can fail across symmetric NAT or carrier-grade NAT while a call from the same device pair would succeed.** This is asymmetric reliability and the user-visible symptom is "calls work but my messages don't send."
2. **Recommended provisioning:** start with a self-hosted coturn on a small VPS ($5–15/month). Privacy-first project (M1 rule) makes self-hosting strongly preferred over Twilio — TURN relays see only ciphertext, but the metadata (IP pairs, session timing, byte counts) is exactly the metadata the project rule says we don't outsource.
3. **Recommended code change:** extract a shared `_buildIceServers()` helper so both `p2p_service.dart` and `native_call_media_bindings.dart` consume the same TURN-aware ICE config. Two PRs: (a) the helper extraction (low risk, can ship pre-TURN-rollout), (b) wiring the project's actual TURN credentials (gated on provisioning).

---

## Current state (code survey)

### 1. ICE config is bifurcated

Two code paths build ICE server lists, and they don't agree.

**Path A — Call media** (`client/lib/ui/screens/calls/native_call_media_bindings.dart:370–399`):

```dart
final servers = <Map<String, dynamic>>[
  {
    'urls': [
      'stun:stun.l.google.com:19302',
      'stun:stun1.l.google.com:19302',
    ],
  },
];
_appendTurnServer(servers, label: 'TURN',
  urlsEnv:  dotenv.env['TURN_URL'],
  userEnv:  dotenv.env['TURN_USERNAME'],
  passEnv:  dotenv.env['TURN_PASSWORD']);
_appendTurnServer(servers, label: 'TURNS',
  urlsEnv:  dotenv.env['TURNS_URL'],
  userEnv:  dotenv.env['TURNS_USERNAME'],
  passEnv:  dotenv.env['TURNS_PASSWORD']);
if (servers.length == 1) {
  debugPrint('[stealth-call] WARNING: no TURN/TURNS in .env — P2P will fail '
             'across NAT/VPN. ...');
}
```

This path reads 6 env keys, supports comma-separated multi-URL TURN lists, supports optional `username`/`credential`, and warns at runtime if TURN is missing.

**Path B — DataChannel messaging** (`client/lib/p2p_service.dart:29–36`):

```dart
final config = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    // TODO: Add TURN servers for better reliability
  ],
  'sdpSemantics': 'unified-plan',
};
```

This path uses STUN-only, hardcoded, no env read. The `TODO` predates the work that built Path A.

### 2. NAT traversal failure modes by topology

| Topology | STUN-only (Path B) | STUN + TURN (Path A) |
|---|---|---|
| Both endpoints on full-cone NAT (home routers, typical Wi-Fi) | ✅ works | ✅ works |
| One endpoint on symmetric NAT (some corporate / carrier networks) | ❌ fails | ✅ relays via TURN |
| Carrier-grade NAT (CGN, common on mobile data) | ⚠️ unreliable | ✅ relays via TURN |
| Either endpoint behind VPN (especially WireGuard / corporate VPN) | ❌ fails most of the time | ✅ relays via TURN |
| Both endpoints offline / mobile-data with strict firewalls | ❌ fails | ⚠️ depends on TURN provider's edge presence |

**Implication for the bifurcation:** a user on home Wi-Fi (full-cone NAT) talking to a user on T-Mobile (CGN) can place a call but can't send chat messages reliably. This is the kind of partial failure that makes users blame the messenger rather than the network.

### 3. Env / CI surface for TURN

The env contract is already in place:

- `client/lib/main.dart:19–22, 44–51` — `TURN_URL`, `TURN_USERNAME`, `TURNS_URL` are in `expectedKeys` and routed through `String.fromEnvironment` for `--dart-define` overrides.
- `.github/workflows/ci.yml:44` — CI's `Validate env files completeness` step requires all 7 keys (`POCKETBASE_URL TURN_URL TURN_USERNAME TURN_PASSWORD TURNS_URL TURNS_USERNAME TURNS_PASSWORD`) to be present in `.env.example` and `.env.defaults`. So the keys are already wired through the build pipeline.
- `_appendTurnServer` (Path A) is the canonical builder — supports comma-separated URL lists for failover, handles missing username/credential gracefully.

The plumbing is in place. What's missing is (a) Path B using it and (b) the actual TURN server.

---

## TURN provider options

### Self-hosted coturn (recommended)

**Setup**: one Linux VPS (Hetzner CX22 €4.5/mo, DO $6/mo, Vultr $5/mo), `apt install coturn`, configure realm + cert + shared-secret credentials, point DNS. Documented in dozens of guides (see Mozilla MDN, Webrtc.org).

| Pro | Con |
|---|---|
| Project rule (M1): no external backend for traffic-class data. TURN sees ciphertext only, but **session metadata** (IP pairs, byte counts, timing) flows through it. Self-hosting keeps that metadata under project control. | DevOps burden: cert rotation (Let's Encrypt automation), monitoring, capacity sizing. Project doesn't currently run other always-on infra besides PocketBase (which is also self-hosted, so the discipline already exists). |
| Predictable flat cost: ~$5–15/month regardless of traffic up to VPS bandwidth limits. Typical VPS bandwidth allocation (1–20 TB/month) covers hundreds of concurrent relayed sessions. | Capacity ceiling: a single small VPS handles ~50–200 concurrent relayed audio/video sessions; chat-only DataChannel is much lighter. Past that, need to scale horizontally with `turn:` URL list. |
| **Reuses PocketBase ops model**: project already self-hosts signaling. TURN is the same operational mental model. | One more thing to monitor. Coturn has good Prometheus/syslog integration; can be added to whatever observability stack PocketBase uses. |

### Twilio Network Traversal Service

| Pro | Con |
|---|---|
| Turnkey, global edge presence, well-documented. | Per-GB pricing (~$0.40/GB outbound at low volume, scales down to ~$0.10/GB at TB scale). For a privacy-first messenger this is the same data class that M1's project rule says we don't outsource. |
| Failover-by-default. | Twilio's data retention policy applies; their SOC2/HIPAA story is good but is exactly the kind of vendor-trust dependency M1 was designed to remove. |
| Time-limited credential issuance via REST API (don't have to ship long-lived TURN creds to the client). | Credential-issuance endpoint becomes a new server-side dependency (need a credential service). |

### Cloudflare Calls (TURN component)

Newer product (GA in 2024–2025 window); generous free tier; same vendor-trust concern as Twilio. Worth re-evaluating if self-hosted coturn capacity becomes a problem. Not recommended as v1.

### Metered.ca / Xirsys

Smaller TURN-as-a-service providers; similar pricing to Twilio; same vendor-trust concern; no privacy advantage over self-hosting. Not recommended.

---

## Recommendation

### Phase 1 — Codebase alignment (no provisioning required)

**Ship before TURN goes live.** Extract a shared `IceServersBuilder` (or `_buildIceServers()` top-level function) into a new file `client/lib/services/webrtc/ice_servers.dart`. Both `p2p_service.dart` and `native_call_media_bindings.dart` consume it. Single source of truth for ICE config.

**Why ship this first:** removes the asymmetric-reliability bug structurally, even before the TURN server is live. With no TURN configured, both paths still work (STUN-only) and behave consistently. The moment TURN env vars are populated, both paths benefit at once.

**Estimated scope:** ~80 lines of new code (the helper + a refactor in each consumer), 2 tests (helper unit tests, no integration test needed — the WebRTC stack is untestable in `flutter test` anyway). Suitable for a fast plan.

### Phase 2 — Provisioning (gated on stakeholder decision)

**Default recommendation: self-host coturn on Hetzner CX22 (€4.5/month).** Aligns with project's existing self-hosting discipline for PocketBase. Document setup in a new `docs/turn-setup.md` mirroring `docs/POCKETBASE_SETUP.md`'s structure.

**Decision tree** if self-host is rejected:

1. **"Can't justify ops burden"** → Twilio with a thin credential-service shim. Accept the vendor-trust trade-off; document in `docs/SECURITY.md` threat model.
2. **"Want to defer entirely"** → ship Phase 1 only. STUN-only is acceptable for early users on residential Wi-Fi. Document the failure modes in user-facing docs so users on CGN/VPN know to expect intermittent failures.

### Phase 3 — Observability (optional, post-provisioning)

After Phase 2 lands:

- Add a relay-vs-direct telemetry counter (locally aggregated, never exfiltrated — respects M1) so users can see in Settings whether their last N connections relayed or went direct. Helpful for diagnosing "why are my messages slow" without uploading any data.
- Track aggregate `[stealth-call] WARNING: no TURN/TURNS in .env` log occurrences locally; surface in the diagnostics screen.

---

## Open questions for the project owner

1. **Self-host or vendor?** The recommendation is self-host based on M1's rule, but the cost/benefit calculus is owner-territory.
2. **TURN credential rotation policy.** Self-hosted coturn supports static long-lived shared-secret creds (simpler, less secure) or time-limited HMAC-derived creds (more secure, requires a credential endpoint). Recommendation: start with static creds in the env, migrate to time-limited if/when there's evidence of credential leakage.
3. **`TURNS_URL` (TLS-wrapped TURN) priority.** Path A reads both `TURN_URL` and `TURNS_URL`; should we prefer `turns:` over `turn:` (more bandwidth-efficient over hostile networks) or list both for failover? Recommendation: list both, with `turns:` first.
4. **Geographic distribution.** A single-region TURN server (e.g. EU-Central) adds latency for Americas users. Worth surveying user geography (anonymously, from PocketBase signaling logs) before committing.

---

## Next concrete step

When ready: `/aif-plan fast extract shared ice-servers builder + wire to p2p_service` for Phase 1.

Phase 2 needs human input on the provisioning decision before a plan can be drafted.
