import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase/supabase.dart';

/// Diagnostic: subscribe to `user_calls:<userId>` broadcast channels for the
/// two nicknames passed as arguments and log every event that arrives.
///
/// Usage: dart run tool/call_listen.dart `<nick1>` `<nick2>`
Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: dart run tool/call_listen.dart <nick1> <nick2>');
    exitCode = 1;
    return;
  }

  final env = await _loadEnv(File('.env'));
  final url = env['SUPABASE_URL'];
  final anonKey = env['SUPABASE_ANON_KEY'];
  if (url == null || anonKey == null) {
    stderr.writeln('Missing SUPABASE_URL / SUPABASE_ANON_KEY in .env');
    exitCode = 1;
    return;
  }

  final client = SupabaseClient(url, anonKey);
  await client.auth.signInAnonymously();

  final ids = <String, String>{};
  for (final nick in args) {
    final row = await client
        .from('users')
        .select('id')
        .eq('nickname', nick)
        .maybeSingle();
    if (row == null) {
      stderr.writeln('user not found: $nick');
      continue;
    }
    ids[nick] = row['id'] as String;
    stdout.writeln('[listen] $nick -> ${row['id']}');
  }

  for (final entry in ids.entries) {
    final nick = entry.key;
    final id = entry.value;
    final channel = client.channel('user_calls:$id');
    channel
        .onBroadcast(
          event: 'call_initiation',
          callback: (payload) {
            stdout.writeln(
              '[$nick] call_initiation ${DateTime.now()} ${jsonEncode(payload)}',
            );
          },
        )
        .onBroadcast(
          event: 'call_accept',
          callback: (payload) {
            stdout.writeln(
              '[$nick] call_accept ${DateTime.now()} ${jsonEncode(payload)}',
            );
          },
        )
        .onBroadcast(
          event: 'call_end',
          callback: (payload) {
            stdout.writeln(
              '[$nick] call_end ${DateTime.now()} ${jsonEncode(payload)}',
            );
          },
        )
        .subscribe((status, [error]) {
          stdout.writeln('[$nick] subscription status: $status error=$error');
        });
  }

  stdout.writeln('[listen] listening... Ctrl+C to exit');
  await Completer<void>().future;
}

Future<Map<String, String>> _loadEnv(File file) async {
  if (!await file.exists()) {
    return const {};
  }
  final text = await file.readAsString();
  final result = <String, String>{};
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    final key = trimmed.substring(0, eq).trim();
    final value = trimmed.substring(eq + 1).trim();
    result[key] = value;
  }
  return result;
}
