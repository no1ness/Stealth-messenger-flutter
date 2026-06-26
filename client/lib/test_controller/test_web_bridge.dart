import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:stealth/local_app_service.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/test_controller/test_controller.dart';
import 'package:web/web.dart' as web;

@JS('window.eval')
external JSAny? _eval(JSString code);

void attachWebTestBridge(LocalAppService appService) {
  try {
    _WebTestBridge(appService).install();
    Logger.info('[test-bridge] attached');
  } catch (e) {
    Logger.warn('[test-bridge] failed to attach', extras: {'error': '$e'});
  }
}

class _WebTestBridge {
  _WebTestBridge(this._app);
  final LocalAppService _app;

  void install() {
    final app = _app;

    final script = web.document.createElement('script') as web.HTMLScriptElement;
    script.text = 'window.__test = { _ready: true, _queue: [], _result: undefined };';
    web.document.head!.appendChild(script);

    _eval('''
      window.__test.register = function(nick) {
        window.__test._queue.push({cmd: 'register', args: [nick]});
      };
      window.__test.getContactBundle = function(cb) {
        window.__test._queue.push({cmd: 'getContactBundle', cb: cb});
      };
      window.__test.searchUsers = function(q, cb) {
        window.__test._queue.push({cmd: 'searchUsers', args: [q], cb: cb});
      };
      window.__test.addContact = function(uid) {
        window.__test._queue.push({cmd: 'addContact', args: [uid]});
      };
      window.__test.getUserId = function(cb) {
        window.__test._queue.push({cmd: 'getUserId', cb: cb});
      };
      window.__test.waitForEvent = function(type, timeout, cb) {
        window.__test._queue.push({cmd: 'waitForEvent', args: [type, String(timeout)], cb: cb});
      };
      window.__test.createChat = function(uid, cb) {
        window.__test._queue.push({cmd: 'createChat', args: [uid], cb: cb});
      };
    '''.toJS);

    Timer.periodic(const Duration(milliseconds: 50), (_) {
      _drainQueue(app);
    });
  }

  String? _evalToString(String jsCode) {
    final result = _eval(jsCode.toJS);
    if (result == null) return null;
    if (result.isA<JSString>()) return (result as JSString).toDart;
    return result.toString();
  }

  void _drainQueue(LocalAppService app) {
    try {
      final raw = _evalToString('(function() {'
          'var q = window.__test._queue;'
          'if (!q || q.length === 0) return null;'
          'var item = q.shift();'
          'return JSON.stringify({cmd: item.cmd, args: item.args || [], hasCb: !!item.cb});'
          '})()');

      if (raw == null || raw == 'null' || raw == 'undefined') return;

      final data = jsonDecode(raw) as Map<String, dynamic>;
      final cmd = data['cmd'] as String;
      final args = (data['args'] as List?)?.cast<String>() ?? [];
      _dispatch(cmd, args, app);
    } catch (_) {}
  }

  void _dispatch(String cmd, List<String> args, LocalAppService app) {
    switch (cmd) {
      case 'register':
        Logger.debug('[test-bridge] dispatch register: ${args[0]}');
        app.registerUser(args[0]).then((_) {
          Logger.info('[test-bridge] register done for ${args[0]}');
          // Force SharedPreferences to reload from localStorage
          _evalToString('window.location.reload()');
        }).catchError((e, st) {
          Logger.warn('[test-bridge] register failed: $e\n$st');
        });
        break;
      case 'addContact':
        app.addContact(args[0]).then((_) {
          _evalToString('window.__test._result = "ok"');
        }).catchError((e) {
          Logger.warn('[test-bridge] addContact: $e');
          _evalToString('window.__test._result = null');
        });
        break;
      case 'getContactBundle':
        app.generateQRCode().then((b) {
          _evalToString('window.__test._result = ${jsonEncode(b)}');
        }).catchError((e) { Logger.warn('[test-bridge] bundle: $e'); return null; });
        break;
      case 'searchUsers':
        app.searchUsers(args[0]).then((r) {
          _evalToString('window.__test._result = ${jsonEncode(r)}');
        }).catchError((e) { Logger.warn('[test-bridge] search: $e'); return null; });
        break;
      case 'getUserId':
        app.getUserId().then((id) {
          _evalToString('window.__test._result = ${jsonEncode(id ?? '')}');
        }).catchError((e) { Logger.warn('[test-bridge] getUserId: $e'); return null; });
        break;
      case 'createChat':
        app.findOrCreatePrivateChatWith(args[0]).then((chatId) {
          _evalToString('window.__test._result = ${jsonEncode(chatId ?? '')}');
        }).catchError((e) {
          Logger.warn('[test-bridge] createChat: $e');
          _evalToString('window.__test._result = null');
        });
        break;
      case 'waitForEvent':
        final type = args[0];
        final timeoutMs = args.length > 1 ? int.parse(args[1]) : 15000;
        TestController.instance
            .waitForEvent(type, timeout: Duration(milliseconds: timeoutMs))
            .then((e) {
          _evalToString('window.__test._result = ${jsonEncode(e.serialize())}');
        }).catchError((_) {
          _evalToString('window.__test._result = null');
        });
        break;
    }
  }
}
