import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Length of PocketBase record ids used in `rtc_signaling`.
///
/// PocketBase 0.23+ enforces exact 15-char custom record ids
/// (`^[a-zA-Z0-9_]{15,}$`). The project uses deterministic 15-char
/// ids derived via SHA-256 prefix to avoid collisions.
const int kPbIdLength = 15;

final RegExp _canonicalUuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Returns the PocketBase record id corresponding to [localUuid].
///
/// PocketBase 0.23+ limits record `id` to 15 chars. For canonical UUIDs,
/// this function computes SHA-256 of the UUID and returns the first 15 hex
/// characters (60 bits of entropy). This gives deterministic, collision-resistant
/// ids — unlike the previous strip-dashes + truncate approach which discarded
/// 17 hex chars non-uniformly.
///
/// Non-UUID inputs (e.g. test fixtures like `smoke_a_<stamp>`) pass through
/// unchanged (truncated to 15 chars if longer).
String pbIdFromLocalUuid(String localUuid) {
  if (_canonicalUuidRegex.hasMatch(localUuid)) {
    return sha256.convert(utf8.encode(localUuid)).toString().substring(0, 15);
  }
  return localUuid.length > kPbIdLength
      ? localUuid.substring(0, kPbIdLength)
      : localUuid;
}

/// Resolves 15-char PocketBase record ids back to local UUIDs.
///
/// Since SHA-256 is one-way, the resolver pre-computes PB-ids for a known
/// set of UUIDs (self + contacts) and provides O(1) reverse lookup. Unknown
/// PB-ids (legacy test fixtures, records from pre-hash builds) pass through
/// unchanged for backward compatibility.
class PbUserIdResolver {
  /// Builds a resolver from a known set of local UUID strings.
  ///
  /// Each UUID is hashed via [pbIdFromLocalUuid] and stored in an internal
  /// map for O(1) reverse lookup.
  PbUserIdResolver(Iterable<String> knownLocalUuids) {
    for (final uuid in knownLocalUuids) {
      _pbToLocal[pbIdFromLocalUuid(uuid)] = uuid;
    }
    debugPrint('[pb-id] resolver built with ${_pbToLocal.length} entries');
  }

  final Map<String, String> _pbToLocal = <String, String>{};

  /// Singleton empty resolver for code paths without contacts wired in.
  static final PbUserIdResolver empty = PbUserIdResolver([]);

  /// Returns the local UUID corresponding to [pbId], or [pbId] itself if
  /// unknown (passthrough for non-UUID test fixtures).
  String localUuidFromPbId(String pbId) {
    return _pbToLocal[pbId] ?? pbId;
  }

  /// Whether this resolver can map [pbId] to a known local UUID.
  bool knows(String pbId) => _pbToLocal.containsKey(pbId);
}
