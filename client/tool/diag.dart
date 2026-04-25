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

  stdout.writeln('--- users named "1" / "2" ---');
  final users = await client
      .from('users')
      .select('id, nickname, public_key, created_at')
      .inFilter('nickname', ['1', '2']);
  for (final u in users) {
    stdout.writeln(jsonEncode(u));
  }

  final ids = users.map((u) => u['id'] as String).toList();
  stdout.writeln('\n--- chat_members for those users ---');
  final members = await client
      .from('chat_members')
      .select('chat_id, user_id')
      .inFilter('user_id', ids);
  for (final m in members) {
    stdout.writeln(jsonEncode(m));
  }

  final chatIds = members.map((m) => m['chat_id'] as String).toSet().toList();
  stdout.writeln('\n--- chats ${chatIds.length} ---');
  if (chatIds.isNotEmpty) {
    final chats = await client
        .from('chats')
        .select('id, name, created_at, updated_at')
        .inFilter('id', chatIds);
    for (final c in chats) {
      stdout.writeln(jsonEncode(c));
    }

    stdout.writeln('\n--- messages per chat ---');
    for (final cid in chatIds) {
      final msgs = await client
          .from('messages')
          .select('id, sender_id, content, created_at')
          .eq('chat_id', cid)
          .order('created_at');
      stdout.writeln('chat $cid: ${msgs.length} msgs');
      for (final m in msgs) {
        stdout.writeln('  ${m['created_at']} ${m['sender_id']}: ${m['content']}');
      }
    }

    stdout.writeln('\n--- all chat_members per chat ---');
    final allMembers = await client
        .from('chat_members')
        .select('chat_id, user_id')
        .inFilter('chat_id', chatIds);
    for (final m in allMembers) {
      stdout.writeln(jsonEncode(m));
    }
  }

  stdout.writeln('\n--- contacts (owner -> contact) for these users ---');
  final contacts = await client
      .from('contacts')
      .select('owner_id, user_id, name')
      .inFilter('owner_id', ids);
  for (final c in contacts) {
    stdout.writeln(jsonEncode(c));
  }

  stdout.writeln('\n--- call_history for these users ---');
  try {
    final calls = await client
        .from('call_history')
        .select()
        .inFilter('caller_id', ids);
    for (final c in calls) {
      stdout.writeln(jsonEncode(c));
    }
  } catch (e) {
    stdout.writeln('call_history probe error: $e');
  }
}
