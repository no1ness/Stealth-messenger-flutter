import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../local_database_service.dart';
import '../../logging/logger.dart';
import '../../storage_service.dart';
import '../../test_controller/test_event.dart';
import '../identity/identity_service.dart';

/// Contact-book facade: peer bundles, nicknames, safety numbers, search.
/// Stateless singleton; backing storage lives in [LocalDatabaseService].
///
/// Extracted from `LocalAppService` as task #5 of the post-PocketBase
/// hardening plan (`.ai-factory/plans/client-hardening-followup.md`).
/// Owns its own in-memory caches (`_nicknameCache`, `_lastSearchResults`)
/// — call [clearCaches] from [LocalAppService.logout] to invalidate them.
class ContactService {
  factory ContactService() => _instance;
  ContactService._();
  static final ContactService _instance = ContactService._();

  final LocalDatabaseService _localDb = LocalDatabaseService();
  final StorageService _storage = StorageService();
  final IdentityService _identity = IdentityService();

  /// userId → nickname (own id and peers). Populated lazily by
  /// [getNicknameForUser] and [getNicknamesBatch]; cleared by [clearCaches].
  final Map<String, String?> _nicknameCache = {};

  /// userId → last successful search hit. Required so [addContact] knows
  /// the peer's public key — search results carry the bundle, the
  /// `addContact(userId)` call site only forwards the id.
  final Map<String, Map<String, dynamic>> _lastSearchResults = {};

  void Function(TestEvent)? _onTestEvent;

  void attachTestEventEmitter(void Function(TestEvent) cb) =>
      _onTestEvent = cb;

  // ------------- public API -------------

  Future<List<dynamic>> getContacts() async {
    final contacts = await _localDb.getContacts();
    return contacts.map((contact) {
      final copy = Map<String, dynamic>.from(contact);
      copy['user_id'] ??= copy['contact_user_id'];
      copy['name'] ??= copy['nickname'] ?? copy['user_id'];
      return copy;
    }).toList();
  }

  Future<void> deleteContact(String userId) async {
    Logger.info('[contacts] deleteContact', extras: {'userId': userId});
    await _localDb.deleteContact(userId);
    _nicknameCache.remove(userId);
    _lastSearchResults.remove(userId);
  }

  Future<Map<String, String?>> getNicknamesBatch(Set<String> userIds) async {
    final result = <String, String?>{};
    final uncached = <String>{};
    final me = await _identity.getUserId();

    for (final id in userIds) {
      if (_nicknameCache.containsKey(id)) {
        result[id] = _nicknameCache[id];
      } else {
        uncached.add(id);
      }
    }
    if (uncached.isEmpty) return result;

    for (final contact in await _localDb.getContacts()) {
      final id =
          (contact['contact_user_id'] ?? contact['user_id'])?.toString();
      if (id != null && uncached.contains(id)) {
        final nickname =
            (contact['nickname'] ?? contact['name'] ?? id).toString();
        _nicknameCache[id] = nickname;
        result[id] = nickname;
        uncached.remove(id);
      }
    }
    for (final id in uncached.toList()) {
      if (id == me) {
        final nickname = await _identity.getNickname();
        _nicknameCache[id] = nickname;
        result[id] = nickname;
        uncached.remove(id);
      }
    }
    for (final id in uncached) {
      _nicknameCache[id] = null;
      result[id] = null;
    }
    return result;
  }

  Future<void> getNicknames(Set<String> userIds) async {
    await getNicknamesBatch(userIds);
  }

  Future<String?> getNicknameForUser(String userId) async {
    if (_nicknameCache.containsKey(userId)) {
      return _nicknameCache[userId];
    }
    final me = await _identity.getUserId();
    if (userId == me) {
      final nickname = await _identity.getNickname();
      _nicknameCache[userId] = nickname;
      return nickname;
    }
    for (final contact in await _localDb.getContacts()) {
      final id = (contact['contact_user_id'] ?? contact['user_id'])?.toString();
      if (id == userId) {
        final nickname =
            (contact['nickname'] ?? contact['name'] ?? userId).toString();
        _nicknameCache[userId] = nickname;
        return nickname;
      }
    }
    return null;
  }

  Future<String?> getUserNicknameById(String userId) =>
      getNicknameForUser(userId);

  Future<String?> getUserNickname() => _identity.getNickname();

  /// Batch variant of [getOtherPublicKey]. Loads contacts once and returns
  /// a map of userId → SimplePublicKey (or throws if any key is missing).
  Future<Map<String, SimplePublicKey>> getOtherPublicKeysBatch(
      Set<String> userIds) async {
    final me = await _identity.getUserId();
    final result = <String, SimplePublicKey>{};
    final remaining = <String>{...userIds};

    if (me != null && remaining.contains(me)) {
      final ownPublicKey = await _storage.read('publicKey');
      if (ownPublicKey != null && ownPublicKey.isNotEmpty) {
        result[me] = SimplePublicKey(
          base64Decode(ownPublicKey),
          type: KeyPairType.x25519,
        );
        remaining.remove(me);
      }
    }
    if (remaining.isEmpty) return result;

    final contacts = await _localDb.getContacts();
    for (final contact in contacts) {
      final id =
          (contact['contact_user_id'] ?? contact['user_id'])?.toString();
      if (id != null && remaining.contains(id)) {
        final publicKey = contact['public_key']?.toString();
        if (publicKey != null && publicKey.isNotEmpty) {
          result[id] = SimplePublicKey(
            base64Decode(publicKey),
            type: KeyPairType.x25519,
          );
          remaining.remove(id);
        }
      }
    }
    if (remaining.isNotEmpty) {
      throw StateError(
        'Missing public key for ${remaining.first}. '
        'Add the contact from a Stealth contact bundle.',
      );
    }
    return result;
  }

  /// Returns the peer's X25519 public key. For our own id reads from
  /// [StorageService] (same source [IdentityService] persists into); for
  /// peers, scans the local contacts store. Throws when the peer has no
  /// stored public key — contact must be added from a `stealth:` bundle.
  Future<SimplePublicKey> getOtherPublicKey(String userId) async {
    final me = await _identity.getUserId();
    if (userId == me) {
      final ownPublicKey = await _storage.read('publicKey');
      if (ownPublicKey == null || ownPublicKey.isEmpty) {
        throw StateError('Own public key is missing.');
      }
      return SimplePublicKey(
        base64Decode(ownPublicKey),
        type: KeyPairType.x25519,
      );
    }

    final contacts = await _localDb.getContacts();
    for (final contact in contacts) {
      final id = (contact['contact_user_id'] ?? contact['user_id'])?.toString();
      if (id == userId) {
        final publicKey = contact['public_key']?.toString();
        if (publicKey != null && publicKey.isNotEmpty) {
          return SimplePublicKey(
            base64Decode(publicKey),
            type: KeyPairType.x25519,
          );
        }
      }
    }
    throw StateError(
        'Missing public key for $userId. Add the contact from a Stealth contact bundle.');
  }

  /// 32-char safety-number derived from `Sha256(ownPublic + ":" + otherPublic)`.
  /// Returns `null` when either key is missing or the peer is unknown.
  Future<String?> getSafetyNumber(String otherUserId) async {
    final ownPublic = await _storage.read('publicKey');
    late final String otherPublic;
    try {
      final key = await getOtherPublicKey(otherUserId);
      otherPublic = base64Encode(key.bytes);
    } catch (_) {
      return null;
    }
    if (ownPublic == null || ownPublic.isEmpty || otherPublic.isEmpty) {
      return null;
    }
    final bytes = utf8.encode('$ownPublic:$otherPublic');
    final hash = await Sha256().hash(bytes);
    return base64Encode(hash.bytes).replaceAll('=', '').substring(0, 32);
  }

  /// Adds a contact to the local store. The peer's public key must be
  /// available — either pre-cached by a prior [searchUsers] call (which
  /// happens when the UI paste-search'es a `stealth:` bundle), or the
  /// caller must supply a fresh search first. Without a public key the
  /// call is rejected with a warn-level log.
  Future<void> addContact(String userId) async {
    final cached = _lastSearchResults[userId];
    if (cached == null ||
        (cached['public_key']?.toString().isNotEmpty != true)) {
      Logger.warn(
        '[contacts] addContact blocked: missing contact bundle/public key',
        extras: {'userId': userId},
      );
      return;
    }
    final now = DateTime.now().toIso8601String();
    final contact = {
      'contact_user_id': userId,
      'user_id': userId,
      'name': cached['name'] ?? userId,
      'nickname': cached['nickname'] ?? cached['name'] ?? userId,
      'public_key': cached['public_key'],
      'created_at': now,
    };
    await _localDb.saveContact(contact);
    _nicknameCache[userId] = contact['nickname']?.toString();
    _onTestEvent?.call(ContactAdded(userId: userId));
    Logger.info('[contacts] saved local contact', extras: {'userId': userId});
  }

  /// Search by raw id, nickname substring, or — most importantly — by
  /// pasted `stealth:` bundle. A successful bundle decode caches the
  /// peer's public key for the subsequent [addContact] call.
  Future<List<dynamic>> searchUsers(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final bundle = _decodeContactBundle(trimmed);
    if (bundle != null) {
      _lastSearchResults[bundle['user_id'] as String] = bundle;
      return [bundle];
    }

    final results = <Map<String, dynamic>>[];
    final me = await _identity.getUserId();
    final nickname = await _identity.getNickname();
    final publicKey = await _storage.read('publicKey');
    if (me != null &&
        (me == trimmed ||
            (nickname ?? '').toLowerCase().contains(trimmed.toLowerCase()))) {
      final self = {
        'user_id': me,
        'contact_user_id': me,
        'name': nickname ?? me,
        'nickname': nickname ?? me,
        'public_key': publicKey ?? '',
      };
      _lastSearchResults[me] = self;
      results.add(self);
    }

    for (final contact in await getContacts()) {
      final id = contact['user_id']?.toString() ?? '';
      final name = contact['name']?.toString() ?? '';
      if (id == trimmed || name.toLowerCase().contains(trimmed.toLowerCase())) {
        final row = Map<String, dynamic>.from(contact as Map);
        _lastSearchResults[id] = row;
        results.add(row);
      }
    }

    return results;
  }

  /// Creates or updates a local contact from a PB user_profiles record.
  /// Used by [UserDirectoryService] for auto-populated contacts.
  ///
  /// Does NOT replace manually set nickname — only updates presence fields
  /// (isOnline, lastSeen, deviceInfo) and publicKey for existing contacts.
  Future<void> addOrUpdateContact(Map<String, dynamic> profile) async {
    final userId = profile['userId']?.toString();
    if (userId == null || userId.isEmpty) return;

    final contacts = await _localDb.getContacts();
    final existingIdx = contacts.indexWhere(
      (c) => (c['contact_user_id']?.toString() ?? c['user_id']?.toString()) == userId,
    );

    if (existingIdx >= 0) {
      final existing = Map<String, dynamic>.from(contacts[existingIdx] as Map);
      existing['isOnline'] = profile['isOnline'] ?? existing['isOnline'];
      existing['lastSeen'] = profile['lastSeen'] ?? existing['lastSeen'];
      existing['publicKey'] = profile['publicKey'] ?? existing['publicKey'];
      existing['deviceInfo'] = {
        'deviceModel': profile['deviceModel'],
        'platform': profile['platform'],
        'appVersion': profile['appVersion'],
      };
      if (profile['deviceModel'] != null) existing['deviceModel'] = profile['deviceModel'];
      if (profile['platform'] != null) existing['platform'] = profile['platform'];
      if (profile['appVersion'] != null) existing['appVersion'] = profile['appVersion'];
      await _localDb.saveContact(existing);
      Logger.debug('[contacts] upsert updated contact',
          extras: {'userId': userId, 'isOnline': existing['isOnline']});
    } else {
      final now = DateTime.now().toIso8601String();
      final contact = <String, dynamic>{
        'contact_user_id': userId,
        'user_id': userId,
        'name': userId,
        'nickname': userId,
        'public_key': profile['publicKey'] ?? '',
        'publicKey': profile['publicKey'] ?? '',
        'isOnline': profile['isOnline'] ?? false,
        'lastSeen': profile['lastSeen'] ?? '',
        'deviceModel': profile['deviceModel'] ?? '',
        'platform': profile['platform'] ?? '',
        'appVersion': profile['appVersion'] ?? '',
        'deviceInfo': {
          'deviceModel': profile['deviceModel'],
          'platform': profile['platform'],
          'appVersion': profile['appVersion'],
        },
        'auto_populated': true,
        'created_at': now,
      };
      await _localDb.saveContact(contact);
      Logger.info('[contacts] created auto-populated contact',
          extras: {'userId': userId});
    }
  }

  /// Drops in-memory caches. Called by `LocalAppService.logout` so the
  /// next session starts cold.
  void clearCaches() {
    _nicknameCache.clear();
    _lastSearchResults.clear();
  }

  /// Drops just the cached nickname for `userId`. Used after own-nickname
  /// updates so the next [getNicknameForUser] re-reads from storage.
  void invalidateNicknameFor(String userId) {
    _nicknameCache.remove(userId);
  }

  Map<String, dynamic>? _decodeContactBundle(String input) =>
      decodeContactBundle(input);
}

/// Parses a `stealth:<base64url(JSON)>` bundle into a contact-shaped
/// map. Returns `null` for malformed input (bad base64, missing fields,
/// wrong prefix, wrong version). Pure top-level so unit tests can call
/// it without spinning up a service.
///
/// Accepted shape (v1):
/// ```
/// { "v": 1, "user_id": "...", "name": "...", "public_key": "..." }
/// ```
Map<String, dynamic>? decodeContactBundle(String input) {
  final trimmed = input.trim();
  if (!trimmed.startsWith('stealth:')) return null;
  try {
    final encoded = trimmed.substring('stealth:'.length);
    final decoded = utf8.decode(
      base64Url.decode(_normalizeBase64Url(encoded)),
    );
    final data = jsonDecode(decoded) as Map<String, dynamic>;
    final version = data['v'];
    if (version != null && version != 1) {
      // Only v1 is recognised today. Reject explicitly so test fixtures
      // with a forward-incompatible version don't pass silently.
      Logger.warn(
        '[contacts] unsupported contact bundle version',
        extras: {'version': version.toString()},
      );
      return null;
    }
    final userId = data['user_id']?.toString();
    final publicKey = data['public_key']?.toString();
    if (userId == null ||
        userId.isEmpty ||
        publicKey == null ||
        publicKey.isEmpty) {
      return null;
    }
    return {
      'user_id': userId,
      'contact_user_id': userId,
      'name': data['name']?.toString() ?? userId,
      'nickname': data['name']?.toString() ?? userId,
      'public_key': publicKey,
    };
  } catch (error) {
    Logger.warn(
      '[contacts] invalid contact bundle',
      extras: {'error': error},
    );
    return null;
  }
}

String _normalizeBase64Url(String value) {
  final remainder = value.length % 4;
  return remainder == 0
      ? value
      : value.padRight(value.length + 4 - remainder, '=');
}
