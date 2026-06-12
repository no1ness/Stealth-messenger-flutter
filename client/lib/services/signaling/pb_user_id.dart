// Mapping between the local user UUID (canonical 36-char form with dashes)
// and the PocketBase record id used in `rtc_signaling`.
//
// PocketBase record ids are shorter than canonical UUIDs in the deployment
// version this project targets, so `pbIdFromLocalUuid` is intentionally lossy
// for UUID-shaped input. Signaling records therefore carry full local ids in
// their JSON payload (`creatorLocalId` / `targetLocalId`) while wire-level
// `creator` / `target` remain PB ids for API-rule enforcement.
//
// The helpers are intentionally idempotent for short non-UUID inputs (test
// fixtures like `smoke_a_<stamp>` and `user-A` pass through unchanged).

final RegExp _canonicalUuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

final RegExp _strippedUuidRegex = RegExp(r'^[0-9a-fA-F]{32}$');

/// Returns the PocketBase record id corresponding to [localUuid].
///
/// PocketBase 0.23+ limits record `id` to 15 chars. Strips dashes from a
/// canonical UUID (32 hex), then truncates to 15. Non-UUID inputs are also
/// truncated if longer.
String pbIdFromLocalUuid(String localUuid) {
  final id = _canonicalUuidRegex.hasMatch(localUuid)
      ? localUuid.replaceAll('-', '')
      : localUuid;
  return id.length > 15 ? id.substring(0, 15) : id;
}

/// Best-effort legacy converter for pre-truncation 32-hex ids.
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
