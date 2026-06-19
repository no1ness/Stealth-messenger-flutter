import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:stealth/local_app_service.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/test_controller/test_controller.dart';
import 'package:web/web.dart' as web;

void attachWebTestBridge(LocalAppService appService) {
  try {
    final bridge = _WebTestBridge(appService);
    bridge.install();
    Logger.info('[test-bridge] attached');
  } catch (e) {
    Logger.warn('[test-bridge] failed to attach', extras: {'error': '$e'});
  }
}

class _WebTestBridge {
  _WebTestBridge(this._app);

  final LocalAppService _app;

  void install() {
    final obj = web.JSObject();

    obj.setProperty(
      'register'.toJS,
      (JSString jsNickname) async {
        final nickname = jsNickname.toDart;
        Logger.debug('[test-bridge] register "$nickname"');
        await _app.registerUser(nickname);
      }.toJS,
    );

    obj.setProperty(
      'getContactBundle'.toJS,
      (JSFunction jsCallback) async {
        final bundle = await _app.generateQRCode();
        jsCallback.callAsFunction(null, bundle.toJS);
      }.toJS,
    );

    obj.setProperty(
      'searchUsers'.toJS,
      (JSString jsQuery, JSFunction jsCallback) async {
        final query = jsQuery.toDart;
        final results = await _app.searchUsers(query);
        final json = jsonEncode(results);
        jsCallback.callAsFunction(null, json.toJS);
      }.toJS,
    );

    obj.setProperty(
      'addContact'.toJS,
      (JSString jsUserId) async {
        final userId = jsUserId.toDart;
        Logger.debug('[test-bridge] addContact $userId');
        await _app.addContact(userId);
      }.toJS,
    );

    obj.setProperty(
      'getUserId'.toJS,
      (JSFunction jsCallback) async {
        final userId = await _app.getUserId();
        jsCallback.callAsFunction(null, (userId ?? '').toJS);
      }.toJS,
    );

    obj.setProperty(
      'waitForEvent'.toJS,
      (JSString jsType, JSNumber jsTimeout, JSFunction jsCallback) async {
        final type = jsType.toDart;
        final timeoutMs = jsTimeout.toDartInt;
        try {
          final event = await TestController.instance.waitForEvent(
            type,
            timeout: Duration(milliseconds: timeoutMs),
          );
          jsCallback.callAsFunction(null, event.serialize().toJS);
        } catch (e) {
          jsCallback.callAsFunction(null, JSNull());
        }
      }.toJS,
    );

    web.window.setProperty('__test'.toJS, obj);
  }
}
