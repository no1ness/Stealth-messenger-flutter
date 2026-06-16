import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/bypass/proxy_http_client.dart';

class PocketBaseClient {
  PocketBaseClient._(this.pb);

  final PocketBase pb;

  static PocketBaseClient? _instance;

  static PocketBaseClient get instance {
    final cached = _instance;
    if (cached != null) return cached;
    final url = dotenv.env['POCKETBASE_URL']?.trim();
    if (url == null || url.isEmpty) {
      throw StateError(
        'POCKETBASE_URL is not configured in .env. Calls cannot be initiated. '
        'See docs/POCKETBASE_SETUP.md.',
      );
    }
    Logger.info('[signaling] PocketBase client init', extras: {'url': url});
    final fresh = PocketBaseClient._(PocketBase(url));
    _instance = fresh;
    return fresh;
  }

  static final _reconfigureController = StreamController<void>.broadcast();
  static Stream<void> get onReconfigure => _reconfigureController.stream;

  static void reconfigure({bool useProxy = false}) {
    final old = _instance;
    old?.pb.close();
    final url = dotenv.env['POCKETBASE_URL']?.trim();
    if (url == null || url.isEmpty) {
      _instance = null;
      return;
    }
    final pb = useProxy
        ? PocketBase(url, httpClientFactory: proxyAwareClient)
        : PocketBase(url);
    _instance = PocketBaseClient._(pb);
    Logger.info('[signaling] PocketBase client reconfigured',
        extras: {'useProxy': '$useProxy'});
    _reconfigureController.add(null);
  }

  static void resetForTests() {
    _instance = null;
  }
}
