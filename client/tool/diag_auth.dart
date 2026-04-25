import 'dart:convert';
import 'dart:io';

import 'package:supabase/supabase.dart';

Future<Map<String, String>> _loadEnv(File file) async {
  final out = <String, String>{};
  final lines = await file.readAsLines();
  for (final l in lines) {
    final t = l.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final eq = t.indexOf('=');
    if (eq <= 0) continue;
    out[t.substring(0, eq)] = t.substring(eq + 1);
  }
  return out;
}

Future<void> main() async {
  final env = await _loadEnv(File('.env'));
  final client = SupabaseClient(env['SUPABASE_URL']!, env['SUPABASE_ANON_KEY']!);

  stdout.writeln('signing in anonymously...');
  final session = await client.auth.signInAnonymously();
  final me = session.user?.id;
  stdout.writeln('signed in as $me');

  const user1 = '695c1a74-5227-4b4e-84c4-b14b38276332';
  const user2 = 'f8e67c01-00fb-493d-958a-0bff69a4cf87';

  stdout.writeln('\n--- chat_members for user1 (authed as different user) ---');
  try {
    final r1 = await client
        .from('chat_members')
        .select('chat_id')
        .eq('user_id', user1);
    stdout.writeln('rows: ${jsonEncode(r1)}');
  } catch (e) {
    stdout.writeln('err: $e');
  }

  stdout.writeln('\n--- chat_members for user2 ---');
  try {
    final r2 = await client
        .from('chat_members')
        .select('chat_id')
        .eq('user_id', user2);
    stdout.writeln('rows: ${jsonEncode(r2)}');
  } catch (e) {
    stdout.writeln('err: $e');
  }

  stdout.writeln('\n--- all chat_members visible to me ---');
  try {
    final r3 = await client.from('chat_members').select();
    stdout.writeln('count: ${r3.length}');
    for (final row in r3.take(20)) {
      stdout.writeln(jsonEncode(row));
    }
  } catch (e) {
    stdout.writeln('err: $e');
  }

  stdout.writeln('\n--- all chats ---');
  try {
    final r4 = await client.from('chats').select('id,name,created_at,updated_at').order('updated_at', ascending: false).limit(10);
    for (final row in r4) {
      stdout.writeln(jsonEncode(row));
    }
  } catch (e) {
    stdout.writeln('err: $e');
  }

  stdout.writeln('\n--- all messages visible to me ---');
  try {
    final r5 = await client.from('messages').select('id,chat_id,sender_id,content,created_at').order('created_at', ascending: false).limit(20);
    for (final row in r5) {
      stdout.writeln(jsonEncode(row));
    }
  } catch (e) {
    stdout.writeln('err: $e');
  }

  stdout.writeln('\n--- messages by sender user1 ---');
  try {
    final r6 = await client.from('messages').select('id,chat_id,content,created_at').eq('sender_id', user1).order('created_at');
    stdout.writeln('count: ${r6.length}');
    for (final row in r6) {
      stdout.writeln(jsonEncode(row));
    }
  } catch (e) {
    stdout.writeln('err: $e');
  }

  stdout.writeln('\n--- call_history ---');
  try {
    final r7 = await client.from('call_history').select().order('created_at', ascending: false).limit(10);
    for (final row in r7) {
      stdout.writeln(jsonEncode(row));
    }
  } catch (e) {
    stdout.writeln('err: $e');
  }

  // cleanup anon user
  await client.auth.signOut();
}
