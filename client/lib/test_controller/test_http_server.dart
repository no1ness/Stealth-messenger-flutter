import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stealth/logging/logger.dart';
import 'package:stealth/test_controller/test_controller.dart';

/// Debug HTTP server for mobile E2E tests.
///
/// Runs on `localhost:9876`. Only active in debug builds.
/// All method calls are dispatched to the main isolate via
/// `Future.delayed(Duration.zero, ...)` to ensure Flutter
/// service compatibility.
class TestHttpServer {
  TestHttpServer({
    required this.controller,
  });

  final TestController controller;
  HttpServer? _server;

  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 9876);
      Logger.debug('[test-http-server] listening on :9876');
      unawaited(_handleRequests());
    } catch (error) {
      Logger.warn('[test-http-server] bind error',
          extras: {'error': error});
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    Logger.debug('[test-http-server] stopped');
  }

  Future<void> _handleRequests() async {
    await for (final request in _server!) {
      try {
        await _handleRequest(request);
      } catch (error) {
        Logger.warn('[test-http-server] handler error',
            extras: {'error': error});
        _respond(request, 500, {'error': '$error'});
      }
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'POST') {
      _respond(request, 405, {'error': 'method not allowed'});
      return;
    }

    final body = jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>;
    final command = body['command'] as String?;

    if (command == null) {
      _respond(request, 400, {'error': 'missing command'});
      return;
    }

    Logger.debug('[test-http-server] command=$command');
    switch (command) {
      case 'login':
        final userId = body['userId'] as String?;
        if (userId == null) {
          _respond(request, 400, {'error': 'missing userId'});
          return;
        }
        await Future.delayed(Duration.zero, () => controller.login(userId));
        _respond(request, 200, {'ok': true});

      case 'getBundle':
        final bundle = await Future.delayed(
          Duration.zero,
          () => controller.getBundle(),
        );
        _respond(request, 200, bundle);

      case 'addContact':
        final bundle = body['bundle'] as Map<String, dynamic>?;
        if (bundle == null) {
          _respond(request, 400, {'error': 'missing bundle'});
          return;
        }
        await Future.delayed(Duration.zero, () => controller.addContact(bundle));
        _respond(request, 200, {'ok': true});

      case 'sendMessage':
        final to = body['to'] as String?;
        final text = body['text'] as String?;
        if (to == null || text == null) {
          _respond(request, 400, {'error': 'missing to or text'});
          return;
        }
        await Future.delayed(
          Duration.zero,
          () => controller.sendMessage(to, text),
        );
        _respond(request, 200, {'ok': true});

      case 'waitForEvent':
        final type = body['type'] as String?;
        final timeoutMs = body['timeoutMs'] as int? ?? 5000;
        if (type == null) {
          _respond(request, 400, {'error': 'missing type'});
          return;
        }
        final event = await controller.waitForEvent(
          type,
          timeout: Duration(milliseconds: timeoutMs),
        );
        _respond(request, 200, event.toJson());

      default:
        _respond(request, 400, {'error': 'unknown command: $command'});
    }
  }

  void _respond(HttpRequest request, int status, Map<String, dynamic> body) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    request.response.close();
  }
}
