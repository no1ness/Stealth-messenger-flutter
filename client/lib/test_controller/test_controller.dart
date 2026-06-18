import 'dart:async';

import 'package:stealth/logging/logger.dart';
import 'package:stealth/test_controller/test_event.dart';

/// Debug-only test API for E2E tests.
///
/// Entry point in `main.dart`:
/// ```dart
/// if (kDebugMode) { TestController.instance.attach(); }
/// ```
///
/// Provides a singleton that exposes control methods and a stream of
/// [TestEvent]s. On web, it's available via `window.test`. On mobile,
/// it starts a debug HTTP server on `localhost:9876`.
class TestController {
  static TestController get instance => _instance;
  factory TestController() => _instance;
  TestController._();
  static final TestController _instance = TestController._();

  bool _attached = false;

  /// Attach to the app. Idempotent — safe to call multiple times.
  void attach() {
    if (_attached) return;
    _attached = true;
    Logger.debug('[test-controller] attached');
  }

  // --- Event bus ---

  final StreamController<TestEvent> _eventController =
      StreamController<TestEvent>.broadcast();

  Stream<TestEvent> get events => _eventController.stream;

  /// Wait for an event of [type] within [timeout].
  Future<TestEvent> waitForEvent(String type, {Duration timeout = const Duration(seconds: 5)}) {
    return events
        .firstWhere((e) => e.type == type)
        .timeout(timeout);
  }

  void emit(TestEvent event) {
    Logger.debug('[test-controller] emit ${event.type}');
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  /// Hook for services to emit events via the controller.
  void Function(TestEvent)? get emitter => emit;

  // --- Control methods ---

  String? _currentUserId;

  String? get currentUserId => _currentUserId;

  Future<void> login(String userId) async {
    _currentUserId = userId;
    Logger.debug('[test-controller] login $userId');
  }

  Future<Map<String, dynamic>> getBundle() async {
    Logger.debug('[test-controller] getBundle');
    return <String, dynamic>{};
  }

  Future<void> addContact(Map<String, dynamic> bundle) async {
    Logger.debug('[test-controller] addContact');
  }

  Future<void> sendMessage(String to, String text) async {
    Logger.debug('[test-controller] sendMessage to=$to text=$text');
  }

  // --- Lifecycle ---

  void dispose() {
    if (!_eventController.isClosed) {
      _eventController.close();
    }
    _attached = false;
  }
}
