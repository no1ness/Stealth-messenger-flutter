import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../logging/logger.dart';

/// Single source of truth for the WebRTC ICE-server configuration used
/// by both [P2PService] (DataChannel messaging) and the call screens
/// (RTC voice/video). Reads TURN/TURNS credentials from `.env` via
/// `flutter_dotenv`; STUN always falls back to Google's public servers.
///
/// TURNS on 443/TLS is what gets through ТСПУ in Russia — without it the
/// connection collapses to ICE timeout. The warning fired below makes a
/// misconfiguration loud rather than silent.
///
/// Extracted from `p2p_service.dart:62-91` and
/// `native_call_media_bindings.dart:369-418` as task #8 of the
/// post-PocketBase hardening plan. Both call sites now delegate here.
///
/// `envOverride` is optional — exists only so unit tests can inject a
/// mock map without booting `dotenv`. Production callers pass nothing.
///
/// Note: The sing-box bypass proxy (SOCKS5 :10808 / HTTP :10809) does NOT
/// affect WebRTC ICE/STUN/TURN — those use system-level UDP/TCP sockets
/// and bypass the local proxy entirely. ICE candidates still carry the
/// real public IP.
List<Map<String, dynamic>> buildIceServers({
  Map<String, String>? envOverride,
}) {
  final env = envOverride ?? dotenv.env;
  final servers = <Map<String, dynamic>>[
    {
      'urls': [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    },
  ];
  _appendTurnServer(
    servers,
    label: 'TURN',
    urlsEnv: env['TURN_URL'],
    userEnv: env['TURN_USERNAME'],
    passEnv: env['TURN_PASSWORD'],
  );
  _appendTurnServer(
    servers,
    label: 'TURNS',
    urlsEnv: env['TURNS_URL'],
    userEnv: env['TURNS_USERNAME'],
    passEnv: env['TURNS_PASSWORD'],
  );
  if (servers.length == 1) {
    Logger.warn(
        '[ice-config] no TURN/TURNS in .env — P2P will fail across NAT/VPN. '
        'Set TURN_URL/TURN_USERNAME/TURN_PASSWORD or '
        'TURNS_URL/TURNS_USERNAME/TURNS_PASSWORD.');
  } else {
    Logger.debug('[ice-config] resolved',
        extras: {'serverCount': servers.length});
  }
  return servers;
}

void _appendTurnServer(
  List<Map<String, dynamic>> servers, {
  required String label,
  required String? urlsEnv,
  required String? userEnv,
  required String? passEnv,
}) {
  final urls = urlsEnv?.trim();
  if (urls == null || urls.isEmpty) return;
  final user = userEnv?.trim();
  final pass = passEnv?.trim();
  servers.add({
    'urls': urls
        .split(',')
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList(),
    if (user != null && user.isNotEmpty) 'username': user,
    if (pass != null && pass.isNotEmpty) 'credential': pass,
  });
  Logger.info('[ice-config] $label configured', extras: {'urls': urls});
}
