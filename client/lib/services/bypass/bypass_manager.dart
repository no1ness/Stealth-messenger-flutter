import 'package:flutter/services.dart';

class BypassManager {
  static const _channel = MethodChannel('com.stealth.messenger/bypass');
  static const SOCKS_PORT = 10808;
  static const HTTP_PORT = 10809;

  static Future<void> start({
    required String serverIp,
    required String uuid,
    required String publicKey,
    required String shortId,
  }) async {
    try {
      await _channel.invokeMethod('start', {
        'serverIp': serverIp,
        'uuid': uuid,
        'publicKey': publicKey,
        'shortId': shortId,
      });
    } on MissingPluginException {
      throw UnsupportedError('BypassManager is Android-only');
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } on MissingPluginException {
      throw UnsupportedError('BypassManager is Android-only');
    }
  }

  static Future<bool> isRunning() async {
    try {
      return await _channel.invokeMethod('state') ?? false;
    } on MissingPluginException {
      throw UnsupportedError('BypassManager is Android-only');
    }
  }
}
