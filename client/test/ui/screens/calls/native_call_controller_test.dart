import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/ui/screens/calls/native_call_controller.dart';

// Лёгкие state-transition тесты контроллера. Полный lifecycle (initialize →
// signaling → media-PC) требует мокать flutter_webrtc и PocketBase — это
// делается отдельным интеграционным каналом через CI smoke + ручную
// верификацию двух девайсов (см. plan call-screens-controller-split.md).

NativeCallController _buildController({bool isCaller = true}) {
  return NativeCallController(
    chatId: 'test-chat',
    isCaller: isCaller,
    isVideoCall: false,
  );
}

void main() {
  group('NativeCallController state flags', () {
    test(
        'default state: initializing=true, connected=false, mic/speaker/camera on',
        () {
      final controller = _buildController();
      addTearDown(controller.dispose);

      expect(controller.initializing, isTrue);
      expect(controller.connected, isFalse);
      expect(controller.closing, isFalse);
      expect(controller.microphoneEnabled, isTrue);
      expect(controller.speakerEnabled, isTrue);
      expect(controller.cameraEnabled, isTrue);
      expect(controller.callDurationSeconds, 0);
    });

    test('toggleMicrophone flips flag and notifies', () {
      final controller = _buildController();
      addTearDown(controller.dispose);

      var notified = 0;
      controller.addListener(() => notified++);

      controller.toggleMicrophone();
      expect(controller.microphoneEnabled, isFalse);
      expect(notified, 1);

      controller.toggleMicrophone();
      expect(controller.microphoneEnabled, isTrue);
      expect(notified, 2);
    });

    test('toggleCamera flips flag and notifies', () {
      final controller = _buildController();
      addTearDown(controller.dispose);

      controller.toggleCamera();
      expect(controller.cameraEnabled, isFalse);

      controller.toggleCamera();
      expect(controller.cameraEnabled, isTrue);
    });
  });

  group('NativeCallController hangUp', () {
    test('marks closing and invokes onClose when target is null', () async {
      var closed = 0;
      final controller = NativeCallController(
        chatId: 'test-chat',
        isCaller: true,
        isVideoCall: false,
        onClose: () => closed++,
      );
      addTearDown(controller.dispose);

      await controller.hangUp();

      expect(controller.closing, isTrue);
      expect(closed, 1);
    });

    test('is idempotent — second hangUp is no-op', () async {
      var closed = 0;
      final controller = NativeCallController(
        chatId: 'test-chat',
        isCaller: true,
        isVideoCall: false,
        onClose: () => closed++,
      );
      addTearDown(controller.dispose);

      await controller.hangUp();
      await controller.hangUp();

      expect(controller.closing, isTrue);
      expect(closed, 1, reason: 'onClose should fire only on first hangUp');
    });
  });
}
