import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/di.dart';
import 'package:stealth/local_database_service.dart';
import 'package:stealth/services/signaling/pocketbase_client.dart';
import 'package:stealth/storage_service.dart';

void main() {
  setUpAll(() async {
    await dotenv.load(fileName: '.env.defaults');
  });

  group('DI Providers', () {
    test('storageServiceProvider returns StorageService instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final storage = container.read(storageServiceProvider);
      expect(storage, isA<StorageService>());
    });

    test('localDatabaseServiceProvider returns LocalDatabaseService instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final db = container.read(localDatabaseServiceProvider);
      expect(db, isA<LocalDatabaseService>());
    });

    test('providers can be overridden in tests', () {
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(MockStorageService()),
        ],
      );
      addTearDown(container.dispose);

      final storage = container.read(storageServiceProvider);
      expect(storage, isA<MockStorageService>());
    });

    test('selfUserIdProvider can be overridden', () async {
      final container = ProviderContainer(
        overrides: [
          selfUserIdProvider.overrideWith((ref) async => 'test-user-id'),
        ],
      );
      addTearDown(container.dispose);

      final userId = await container.read(selfUserIdProvider.future);
      expect(userId, 'test-user-id');
    });

    test('selfNicknameProvider can be overridden', () async {
      final container = ProviderContainer(
        overrides: [
          selfNicknameProvider.overrideWith((ref) async => 'TestNick'),
        ],
      );
      addTearDown(container.dispose);

      final nickname = await container.read(selfNicknameProvider.future);
      expect(nickname, 'TestNick');
    });

    test('pocketBaseClientProvider returns PocketBaseClient instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final pbClient = container.read(pocketBaseClientProvider);
      expect(pbClient, isA<PocketBaseClient>());
      expect(pbClient.pb, isNotNull);
    });

    test('pocketBaseClientProvider can be overridden', () {
      final mockPb = MockPocketBaseClient();
      final container = ProviderContainer(
        overrides: [
          pocketBaseClientProvider.overrideWithValue(mockPb),
        ],
      );
      addTearDown(container.dispose);

      final pbClient = container.read(pocketBaseClientProvider);
      expect(pbClient, isA<MockPocketBaseClient>());
    });
  });
}

class MockStorageService implements StorageService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockPocketBaseClient implements PocketBaseClient {
  @override
  PocketBase get pb => throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
