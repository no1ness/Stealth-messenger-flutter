import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart';

import 'bypass_manager.dart';

IOClient proxyAwareClient() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return IOClient(
      HttpClient()
        ..findProxy = (url) {
          return 'PROXY 127.0.0.1:${BypassManager.HTTP_PORT}';
        }
        ..connectionTimeout = const Duration(seconds: 10),
    );
  }
  return IOClient(HttpClient());
}
