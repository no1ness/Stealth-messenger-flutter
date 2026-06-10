import 'dart:convert';

import 'package:crypto/crypto.dart';

// Bidirectional mapping between the local user UUID and the PocketBase
// record id used in `rtc_signaling` and the `users` auth collection.
//
// PocketBase 0.23+ enforces record ids as exactly 15 lowercase alphanumeric
// characters (`^[a-z0-9]{15}$`). A canonical UUID (even with dashes removed)
// does not fit. We therefore derive a deterministic 15-char id from any
// local identity string via SHA-256 truncation.
//
// Inputs that are already valid PocketBase ids (15-char `[a-z0-9]`) pass
// through unchanged so smoke tests and manual fixtures stay stable.

final RegExp _canonicalUuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

final RegExp _strippedUuidRegex = RegExp(r'^[0-9a-fA-F]{32}$');

final RegExp _pbIdPattern = RegExp(r'^[a-z0-9]{15}$');

/// Returns the PocketBase record id corresponding to [localUuid].
String pbIdFromLocalUuid(String localUuid) {
  final normalized = localUuid.trim();
  if (normalized.isEmpty) return normalized;
  if (_pbIdPattern.hasMatch(normalized)) {
    return normalized;
  }
  return _hashToPbId(normalized.toLowerCase());
}

/// Returns the canonical UUID corresponding to [pbId] when [pbId] is a legacy
/// 32-hex wire id. Modern 15-char PocketBase ids are opaque and returned as-is;
/// resolve them with [wireIdToLocalUuid] against known local user ids.
String localUuidFromPbId(String pbId) {
  if (_strippedUuidRegex.hasMatch(pbId)) {
    return '${pbId.substring(0, 8)}-'
        '${pbId.substring(8, 12)}-'
        '${pbId.substring(12, 16)}-'
        '${pbId.substring(16, 20)}-'
        '${pbId.substring(20, 32)}';
  }
  return pbId;
}

/// Maps a wire-level PocketBase id back to a local user id when [localCandidates]
/// contains the matching identity.
String wireIdToLocalUuid(
  String wireId,
  Iterable<String> localCandidates,
) {
  for (final local in localCandidates) {
    if (local.isEmpty) continue;
    if (pbIdFromLocalUuid(local) == wireId) {
      return local;
    }
  }
  return localUuidFromPbId(wireId);
}

String _hashToPbId(String input) {
  final digest = sha256.convert(utf8.encode(input));
  return digest.toString().substring(0, 15);
}
