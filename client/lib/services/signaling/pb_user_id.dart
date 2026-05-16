// Mapping between the local user UUID (canonical 36-char form with four
// dashes) and the PocketBase record id used in `rtc_signaling`.
//
// PocketBase requires custom record ids of EXACTLY 15 characters. A canonical
// UUID v4 carries 128 bits of entropy and cannot be encoded losslessly into
// 15 chars over the allowed alphabet. We therefore derive the PB id as the
// first 15 hex characters of `SHA-256(localUuid)` (60 bits — collision
// probability for an individual user with thousands of contacts is < 2^-50).
//
// The mapping is one-way (UUID → pbId is deterministic; pbId → UUID is a
// lookup against known peers). For the reverse direction callers must build
// a [PbUserIdResolver] over the set of UUIDs they expect to encounter (self
// + locally-stored contacts) and use [PbUserIdResolver.localUuidFromPbId].
//
// The helpers are intentionally idempotent for non-UUID inputs (test fixtures
// like `smoke_a_<stamp>` and `user-A` pass through unchanged in both
// directions). This keeps the existing unit-test surface stable.

import 'dart:convert';
import 'package:crypto/crypto.dart';

final RegExp _canonicalUuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// PocketBase requires custom record ids to be exactly 15 chars long.
const int kPbIdLength = 15;

/// Returns the PocketBase record id corresponding to [localUuid].
///
/// For canonical UUIDs returns the first 15 hex characters of
/// `SHA-256(localUuid)`. Non-UUID inputs are returned unchanged so that
/// existing fixtures (`user-A`, `smoke_a_<stamp>`) keep working.
String pbIdFromLocalUuid(String localUuid) {
  if (!_canonicalUuidRegex.hasMatch(localUuid)) {
    return localUuid;
  }
  final digest = sha256.convert(utf8.encode(localUuid));
  return digest.toString().substring(0, kPbIdLength);
}

/// Reverse lookup from PocketBase id to local UUID.
///
/// Built from a known set of local UUIDs (self + contacts). Construction
/// hashes each UUID once; lookups are O(1) thereafter. Unknown ids pass
/// through unchanged — this preserves the previous "non-UUID idempotent"
/// behaviour and lets test fixtures bypass the resolver.
class PbUserIdResolver {
  PbUserIdResolver(Iterable<String> knownLocalUuids)
      : _pbToLocal = <String, String>{
          for (final uuid in knownLocalUuids)
            if (_canonicalUuidRegex.hasMatch(uuid)) pbIdFromLocalUuid(uuid): uuid,
        };

  /// Empty resolver — every lookup is a passthrough. Useful in code paths
  /// that do not yet have a contacts source wired in.
  static final PbUserIdResolver empty = PbUserIdResolver(const <String>[]);

  final Map<String, String> _pbToLocal;

  /// Returns the local UUID for [pbId] if known, otherwise echoes the
  /// input unchanged (passthrough for non-UUID test fixtures and for ids
  /// not in the known set).
  String localUuidFromPbId(String pbId) => _pbToLocal[pbId] ?? pbId;

  /// True if [pbId] resolves to a known local UUID.
  bool knows(String pbId) => _pbToLocal.containsKey(pbId);
}
