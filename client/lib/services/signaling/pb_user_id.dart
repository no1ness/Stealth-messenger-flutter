// Bidirectional mapping between the local user UUID (canonical 36-char form
// with four dashes) and the PocketBase record id used in `rtc_signaling`.
//
// PocketBase rejects record ids that contain dashes; custom ids must match
// `^[a-zA-Z0-9_]{15,}$`. A canonical UUID v4 with dashes does not satisfy
// the pattern, but the same UUID with dashes removed (32 hex chars) does.
// Both peers can therefore derive each other's PocketBase id deterministically
// from the local UUID exchanged via the contact bundle, without any extra
// directory lookup.
//
// The helpers are intentionally idempotent for non-UUID inputs (test fixtures
// like `smoke_a_<stamp>` and `user-A` pass through unchanged in both
// directions). This keeps the existing unit-test surface stable.

final RegExp _canonicalUuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

final RegExp _strippedUuidRegex = RegExp(r'^[0-9a-fA-F]{32}$');

/// Returns the PocketBase record id corresponding to [localUuid].
///
/// Strips dashes from a canonical UUID. Any non-UUID input is returned
/// unchanged.
String pbIdFromLocalUuid(String localUuid) {
  if (_canonicalUuidRegex.hasMatch(localUuid)) {
    return localUuid.replaceAll('-', '');
  }
  return localUuid;
}

/// Returns the canonical UUID corresponding to [pbId].
///
/// Inserts dashes back into the 32-hex form. Any input that is not a
/// 32-hex string is returned unchanged.
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
