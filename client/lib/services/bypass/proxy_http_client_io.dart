import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';
import 'package:http/http.dart' as http;

import 'bypass_manager.dart';

http.Client proxyAwareClient() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return IOClient(
      HttpClient()
        ..findProxy = (url) {
          return 'PROXY 127.0.0.1:${BypassManager.HTTP_PORT}';
        }
        ..connectionTimeout = const Duration(seconds: 10),
    );
  }
  return http.Client();
}
