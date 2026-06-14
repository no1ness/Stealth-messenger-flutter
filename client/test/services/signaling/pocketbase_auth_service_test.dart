import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/services/signaling/pb_user_id.dart';
import 'package:stealth/services/signaling/pocketbase_auth_service.dart';
import 'package:stealth/storage_service.dart';

/// In-memory storage implementing [StorageService].
class _FakeStorage implements StorageService {
  final Map<String, String> _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<void> delete(String key) async => _store.remove(key);

  @override
  Future<void> deleteAll() async => _store.clear();

  @override
  Future<void> init() async {}
}

class _FakeAuthStore extends AuthStore {
  bool _isValid = false;
  RecordModel? _record;

  @override
  bool get isValid => _isValid;

  @override
  RecordModel? get record => _record;

  @override
  void save(String token, RecordModel? newRecord) {
    _isValid = true;
    _record = newRecord;
  }

  @override
  void clear() {
    _isValid = false;
    _record = null;
  }
}

class _FakePocketBase extends PocketBase {
  _FakePocketBase({AuthStore? authStore})
      : super('http://fake.local', authStore: authStore ?? _FakeAuthStore());

  bool createCalled = false;
  String? createId;
  String? createEmail;
  String? authEmail;
  String? authPassword;

  @override
  RecordService collection(String collectionIdOrName) {
    return _FakeRecordService(this, collectionIdOrName);
  }
}

class _FakeRecordService extends RecordService {
  final _FakePocketBase _pb;

  _FakeRecordService(super.client, super.collectionIdOrName)
      : _pb = client as _FakePocketBase;

  @override
  Future<RecordAuth> authWithPassword(
    String email,
    String password, {
    String? expand,
    String? fields,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    _pb.authEmail = email;
    _pb.authPassword = password;
    if (_pb.createCalled) {
      return RecordAuth(
        record: RecordModel({
          'id': _pb.createId ??
              pbIdFromLocalUuid(
                  '550e8400-e29b-41d4-a716-446655440000'),
          'collectionId': 'users',
          'collectionName': 'users',
        }),
      );
    }
    _pb.createCalled = true;
    throw ClientException(statusCode: 400, response: <String, dynamic>{});
  }

  @override
  Future<RecordModel> create({
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<dynamic> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    _pb.createCalled = true;
    _pb.createId = body['id']?.toString();
    _pb.createEmail = body['email']?.toString();
    return RecordModel({
      'id': body['id'],
      'collectionId': 'users',
      'collectionName': 'users',
      ...Map<String, dynamic>.from(body),
    });
  }
}

void main() {
  group('PocketBaseAuthService', () {
    test('ensureAuth creates user with deterministic PB id on first call',
        () async {
      final authStore = _FakeAuthStore();
      final pb = _FakePocketBase(authStore: authStore);
      final storage = _FakeStorage();
      final service = PocketBaseAuthService(
        pocketBase: pb,
        storage: storage,
      );

      await service.ensureAuth('550e8400-e29b-41d4-a716-446655440000');

      expect(pb.createCalled, true);
      expect(pb.createId, 'a3a9e1ed9732cab');
      expect(pb.createEmail, 'a3a9e1ed9732cab@stealth.local');
      expect(pb.authEmail, 'a3a9e1ed9732cab@stealth.local');
    });

    test('ensureAuth is idempotent on repeated calls', () async {
      final authStore = _FakeAuthStore();
      final pb = _FakePocketBase(authStore: authStore);
      final storage = _FakeStorage();
      final service = PocketBaseAuthService(
        pocketBase: pb,
        storage: storage,
      );

      await service.ensureAuth('550e8400-e29b-41d4-a716-446655440000');
      await service.ensureAuth('550e8400-e29b-41d4-a716-446655440000');

      expect(pb.createCalled, true);
      expect(pb.createId, 'a3a9e1ed9732cab');
    });
  });
}
