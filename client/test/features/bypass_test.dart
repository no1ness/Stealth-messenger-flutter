import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/bypass/bypass_manager.dart';

void main() {
  const channel = MethodChannel('com.stealth.messenger/bypass');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('BypassManager', () {
    test('isRunning returns false by default', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'state') return false;
        return null;
      });
      expect(await BypassManager.isRunning(), false);
    });

    test('start and isRunning roundtrip', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'start') return true;
        if (call.method == 'state') return true;
        return null;
      });
      await BypassManager.start(
        serverIp: '203.0.113.10',
        uuid: '550e8400-e29b-41d4-a716-446655440000',
        publicKey: 'test-public-key',
        shortId: 'abcd1234',
      );
      expect(await BypassManager.isRunning(), true);
    });

    test('stop sets state to false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'stop') return true;
        if (call.method == 'state') return false;
        return null;
      });
      await BypassManager.stop();
      expect(await BypassManager.isRunning(), false);
    });

    test('start passes correct arguments', () async {
      String? passedServerIp;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'start') {
          passedServerIp = call.arguments['serverIp'] as String?;
          return true;
        }
        return null;
      });
      await BypassManager.start(
        serverIp: '203.0.113.10',
        uuid: '550e8400-e29b-41d4-a716-446655440000',
        publicKey: 'test-public-key',
        shortId: 'abcd1234',
      );
      expect(passedServerIp, '203.0.113.10');
    });
  });
}
