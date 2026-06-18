import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/bypass/bypass_manager.dart';
import 'package:stealth/services/signaling/pocketbase_client.dart';

class BypassStateController {
  static const _prefsKey = 'bypass_enabled';

  static bool _enabled = false;

  static bool get isEnabled => _enabled;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefsKey) ?? false;
    if (saved) {
      await enable();
    }
  }

  static Future<bool> enable() async {
    if (_enabled) return true;

    final serverIp = dotenv.env['BYPASS_SERVER_IP']?.trim();
    final uuid = dotenv.env['BYPASS_UUID']?.trim();
    final publicKey = dotenv.env['BYPASS_PUBLIC_KEY']?.trim();
    final shortId = dotenv.env['BYPASS_SHORT_ID']?.trim();
    if (serverIp == null || serverIp.isEmpty ||
        uuid == null || uuid.isEmpty ||
        publicKey == null || publicKey.isEmpty ||
        shortId == null || shortId.isEmpty) {
      Logger.warn('[bypass] missing env config — bypass not started');
      return false;
    }

    try {
      await BypassManager.start(
        serverIp: serverIp,
        uuid: uuid,
        publicKey: publicKey,
        shortId: shortId,
      );
      PocketBaseClient.reconfigure(useProxy: true);
      _enabled = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, true);
      Logger.info('[bypass] enabled');
      return true;
    } catch (e) {
      Logger.error('[bypass] enable failed: $e');
      return false;
    }
  }

  static Future<void> disable() async {
    if (!_enabled) return;

    try {
      await BypassManager.stop();
      PocketBaseClient.reconfigure(useProxy: false);
      _enabled = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, false);
      Logger.info('[bypass] disabled');
    } catch (e) {
      Logger.error('[bypass] disable failed: $e');
    }
  }
}
