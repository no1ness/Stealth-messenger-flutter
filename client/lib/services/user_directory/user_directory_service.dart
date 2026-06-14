import 'dart:async';

import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/contacts/contact_service.dart';
import 'package:stealth/services/signaling/pocketbase_auth_service.dart';
import 'package:stealth/services/signaling/pocketbase_client.dart';
import 'package:stealth/services/user_directory/presence_service.dart';
import 'package:stealth/storage_service.dart';

const String _kProfilesCollection = 'user_profiles';

class UserDirectoryService {
  factory UserDirectoryService() => _instance;
  UserDirectoryService._({
    PocketBase? pocketBase,
  }) : _pb = pocketBase ?? PocketBaseClient.instance.pb;

  static final UserDirectoryService _instance = UserDirectoryService._();

  final PocketBase _pb;

  final PocketBaseAuthService _authService = PocketBaseAuthService(
    pocketBase: PocketBaseClient.instance.pb,
    storage: StorageService(),
  );

  final ContactService _contacts = ContactService();
  final PresenceService _presence = PresenceService();

  List<Map<String, dynamic>> _cachedProfiles = [];
  StreamSubscription<Map<String, dynamic>>? _presenceSub;

  Future<List<Map<String, dynamic>>> fetchAllProfiles(
      String selfUserId) async {
    Logger.info('[user-directory] fetchAllProfiles');
    await _authService.ensureAuth(selfUserId);
    try {
      final result = await _pb
          .collection(_kProfilesCollection)
          .getList(page: 1, perPage: 200);
      final profiles = result.items.map((record) {
        return <String, dynamic>{
          'userId': record.getStringValue('userId'),
          'publicKey': record.getStringValue('publicKey'),
          'deviceModel': record.getStringValue('deviceModel'),
          'platform': record.getStringValue('platform'),
          'appVersion': record.getStringValue('appVersion'),
          'registeredAt': record.getStringValue('registeredAt'),
          'isOnline': record.getBoolValue('isOnline'),
          'lastSeen': record.getStringValue('lastSeen'),
        };
      }).toList();
      _cachedProfiles = profiles;
      Logger.info('[user-directory] fetched ${profiles.length} profiles');
      return profiles;
    } catch (error) {
      Logger.warn('[user-directory] fetch error', extras: {'error': error});
      return [];
    }
  }

  Future<void> syncToLocalContacts(
      List<Map<String, dynamic>> profiles) async {
    Logger.info('[user-directory] syncToLocalContacts',
        extras: {'count': profiles.length});
    for (final profile in profiles) {
      try {
        await _contacts.addOrUpdateContact(profile);
      } catch (error) {
        Logger.warn('[user-directory] sync error for profile',
            extras: {'userId': profile['userId'], 'error': error});
      }
    }
    _subscribeToPresence();
  }

  List<Map<String, dynamic>> getCachedProfiles() =>
      List<Map<String, dynamic>>.from(_cachedProfiles);

  void clearCache() {
    Logger.info('[user-directory] clearCache');
    _cachedProfiles.clear();
    _presenceSub?.cancel();
    _presenceSub = null;
  }

  void _subscribeToPresence() {
    _presenceSub?.cancel();
    _presenceSub = _presence.onPresenceChange.listen((profile) {
      final userId = profile['userId'] as String?;
      if (userId == null) return;
      final idx = _cachedProfiles.indexWhere((p) => p['userId'] == userId);
      if (idx >= 0) {
        _cachedProfiles[idx] = Map<String, dynamic>.from(profile);
      } else {
        _cachedProfiles.add(Map<String, dynamic>.from(profile));
      }
      Logger.debug('[user-directory] cache updated from presence',
          extras: {'userId': userId, 'isOnline': profile['isOnline']});
      unawaited(_contacts.addOrUpdateContact(profile));
    });
  }
}
