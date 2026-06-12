import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/webrtc/ice_config.dart';

/// `buildIceServers()` is the single source of truth for the WebRTC
/// ICE-server configuration (task #8). The helper accepts an
/// `envOverride` map for tests — production callers use `dotenv.env`.
void main() {
  group('buildIceServers', () {
    test('STUN only when no TURN/TURNS env is configured', () {
      final servers = buildIceServers(envOverride: const {});
      expect(servers, hasLength(1));
      expect(servers.first['urls'], contains('stun:stun.l.google.com:19302'));
      expect(servers.first.containsKey('username'), isFalse);
    });

    test('appends TURN when TURN_URL set (with credentials)', () {
      final servers = buildIceServers(envOverride: const {
        'TURN_URL': 'turn:turn.example.com:3478',
        'TURN_USERNAME': 'alice',
        'TURN_PASSWORD': 'hunter2',
      });
      expect(servers, hasLength(2));
      final turn = servers.last;
      expect(turn['urls'], ['turn:turn.example.com:3478']);
      expect(turn['username'], 'alice');
      expect(turn['credential'], 'hunter2');
    });

    test('appends TURNS only when TURNS_URL set', () {
      final servers = buildIceServers(envOverride: const {
        'TURNS_URL': 'turns:turns.example.com:443',
        'TURNS_USERNAME': 'bob',
        'TURNS_PASSWORD': 'secret',
      });
      expect(servers, hasLength(2));
      final turns = servers.last;
      expect(turns['urls'], ['turns:turns.example.com:443']);
      expect(turns['username'], 'bob');
      expect(turns['credential'], 'secret');
    });

    test('includes BOTH TURN and TURNS when both are configured', () {
      final servers = buildIceServers(envOverride: const {
        'TURN_URL': 'turn:turn.example.com:3478',
        'TURN_USERNAME': 'u1',
        'TURN_PASSWORD': 'p1',
        'TURNS_URL': 'turns:turns.example.com:443',
        'TURNS_USERNAME': 'u2',
        'TURNS_PASSWORD': 'p2',
      });
      // STUN + TURN + TURNS → 3 entries
      expect(servers, hasLength(3));
      expect(servers[1]['urls'], ['turn:turn.example.com:3478']);
      expect(servers[2]['urls'], ['turns:turns.example.com:443']);
    });

    test('comma-separated TURN_URL is split into a list', () {
      final servers = buildIceServers(envOverride: const {
        'TURN_URL':
            'turn:a.example.com:3478, turn:b.example.com:3478,turn:c.example.com:3478',
        'TURN_USERNAME': 'u',
        'TURN_PASSWORD': 'p',
      });
      expect(servers, hasLength(2));
      expect(
        servers.last['urls'],
        [
          'turn:a.example.com:3478',
          'turn:b.example.com:3478',
          'turn:c.example.com:3478',
        ],
      );
    });

    test('empty URL env values are treated as absent', () {
      final servers = buildIceServers(envOverride: const {
        'TURN_URL': '',
        'TURN_USERNAME': 'ignored',
        'TURN_PASSWORD': 'ignored',
      });
      expect(servers, hasLength(1),
          reason: 'empty TURN_URL must NOT produce a TURN entry');
    });

    test('TURN entry omits username/credential keys when those are blank', () {
      final servers = buildIceServers(envOverride: const {
        'TURN_URL': 'turn:turn.example.com:3478',
      });
      expect(servers, hasLength(2));
      final turn = servers.last;
      expect(turn.containsKey('username'), isFalse);
      expect(turn.containsKey('credential'), isFalse);
    });
  });
}
