import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/di.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/local_database_service.dart';
import 'package:stealth/p2p_service.dart';
import 'package:stealth/storage_service.dart';

void main() {
  group('DI provider registry smoke', () {
    test('all core providers resolve without throwing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(storageServiceProvider), isA<StorageService>());
      expect(container.read(localDatabaseServiceProvider),
          isA<LocalDatabaseService>());
      expect(container.read(localAppServiceProvider), isA<LocalAppService>());
      expect(container.read(p2pServiceProvider), isA<P2PService>());
    });

    test('p2pServiceProvider returns the process-wide singleton', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        identical(container.read(p2pServiceProvider), P2PService.instance),
        isTrue,
        reason:
            'Provider must expose P2PService.instance, not a fresh instance, '
            'so signaling state shared with other call sites stays consistent.',
      );
    });

    test('localAppServiceProvider caches the same instance per container', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = container.read(localAppServiceProvider);
      final second = container.read(localAppServiceProvider);

      expect(identical(first, second), isTrue,
          reason: 'Riverpod Provider must cache for the lifetime of the '
              'container so screens share a single LocalAppService.');
    });

    test('overrides replace the underlying service for tests', () {
      final fake = LocalAppService();
      final container = ProviderContainer(
        overrides: [localAppServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      expect(identical(container.read(localAppServiceProvider), fake), isTrue);
    });
  });
}
