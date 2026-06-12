@TestOn('chrome')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/ui/screens/calls/web_call_controller.dart';

// Лёгкие state-transition тесты web-контроллера. Зеркало
// native_call_controller_test, но контроллер импортирует
// `package:web/web.dart` через media-bindings — extension-методы
// `.toJS`/`.jsify()` доступны только на web-таргете. Запускать через
// `flutter test -p chrome` (либо отдельным CI job на chrome).

WebCallController _buildController({bool isCaller = true}) {
  return WebCallController(
    chatId: 'test-chat',
    isCaller: isCaller,
    isVideoCall: false,
  );
}

void main() {
  group('WebCallController state flags', () {
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
      expect(controller.signalingState, 'stable');
      expect(controller.iceConnectionState, 'new');
      expect(controller.connectionState, 'new');
      expect(controller.setupError, isNull);
    });

    test('viewType identifiers are derived from chatId', () {
      final a = WebCallController(
          chatId: 'chat-a', isCaller: true, isVideoCall: false);
      final b = WebCallController(
          chatId: 'chat-b', isCaller: true, isVideoCall: false);
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      expect(a.remoteViewType, isNot(b.remoteViewType));
      expect(a.localViewType, isNot(b.localViewType));
      expect(a.remoteViewType, isNot(equals(a.localViewType)));
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

    test('toggleSpeaker flips flag and notifies', () {
      final controller = _buildController();
      addTearDown(controller.dispose);

      controller.toggleSpeaker();
      expect(controller.speakerEnabled, isFalse);

      controller.toggleSpeaker();
      expect(controller.speakerEnabled, isTrue);
    });
  });

  group('WebCallController hangUp', () {
    test('marks closing and invokes onClose when target is null', () async {
      var closed = 0;
      final controller = WebCallController(
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
      final controller = WebCallController(
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
