import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/services/signaling/rtc_message.dart';

void main() {
  group('RtcMessageType.fromString', () {
    test('parses all known wire values', () {
      expect(RtcMessageType.fromString('offer'), RtcMessageType.offer);
      expect(RtcMessageType.fromString('answer'), RtcMessageType.answer);
      expect(RtcMessageType.fromString('candidate'), RtcMessageType.candidate);
      expect(RtcMessageType.fromString('hangup'), RtcMessageType.hangup);
    });

    test('throws ArgumentError on unknown value', () {
      expect(
        () => RtcMessageType.fromString('foobar'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => RtcMessageType.fromString(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('wireValue round-trips through fromString', () {
      for (final type in RtcMessageType.values) {
        expect(RtcMessageType.fromString(type.wireValue), type);
      }
    });
  });

  group('RtcMessage.fromRecord', () {
    test('parses all required fields from a RecordModel', () {
      final record = RecordModel({
        'id': 'rec_123',
        'created': '2026-04-29 12:00:00.000Z',
        'updated': '2026-04-29 12:00:00.000Z',
        'collectionId': 'col_rtc',
        'collectionName': 'rtc_signaling',
        'roomId': 'chat-uuid-001',
        'creator': 'user-A',
        'target': 'user-B',
        'type': 'offer',
        'payload': {
          'sdp': 'v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\n',
          'type': 'offer',
        },
      });

      final msg = RtcMessage.fromRecord(record);

      expect(msg.id, 'rec_123');
      expect(msg.roomId, 'chat-uuid-001');
      expect(msg.creator, 'user-A');
      expect(msg.target, 'user-B');
      expect(msg.type, RtcMessageType.offer);
      expect(msg.payload, isA<Map<String, dynamic>>());
      expect(msg.payload['sdp'], startsWith('v=0'));
      expect(msg.payload['type'], 'offer');
    });

    test('parses created timestamp into DateTime', () {
      final record = RecordModel({
        'id': 'r1',
        'created': '2026-01-15 10:30:00.000Z',
        'collectionName': 'rtc_signaling',
        'roomId': 'r',
        'creator': 'a',
        'target': 'b',
        'type': 'answer',
        'payload': <String, dynamic>{},
      });

      final msg = RtcMessage.fromRecord(record);

      expect(msg.created.year, 2026);
      expect(msg.created.month, 1);
      expect(msg.created.day, 15);
    });

    test('falls back to DateTime.now() when created is unparseable', () {
      final before = DateTime.now().toUtc();
      final record = RecordModel({
        'id': 'r2',
        'created': 'not-a-date',
        'collectionName': 'rtc_signaling',
        'roomId': 'r',
        'creator': 'a',
        'target': 'b',
        'type': 'hangup',
        'payload': <String, dynamic>{},
      });

      final msg = RtcMessage.fromRecord(record);
      final after = DateTime.now().toUtc();

      expect(
        msg.created.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        msg.created.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('treats missing payload as empty map', () {
      final record = RecordModel({
        'id': 'r3',
        'created': '2026-04-29 12:00:00.000Z',
        'collectionName': 'rtc_signaling',
        'roomId': 'r',
        'creator': 'a',
        'target': 'b',
        'type': 'hangup',
      });

      final msg = RtcMessage.fromRecord(record);

      expect(msg.payload, isEmpty);
      expect(msg.type, RtcMessageType.hangup);
    });

    test('throws ArgumentError on unknown type field', () {
      final record = RecordModel({
        'id': 'r4',
        'created': '2026-04-29 12:00:00.000Z',
        'collectionName': 'rtc_signaling',
        'roomId': 'r',
        'creator': 'a',
        'target': 'b',
        'type': 'wat',
        'payload': <String, dynamic>{},
      });

      expect(
        () => RtcMessage.fromRecord(record),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('RtcMessage.toCreateBody', () {
    test('returns Map with correct keys for create()', () {
      final msg = RtcMessage(
        id: '',
        roomId: 'chat-1',
        creator: 'user-A',
        target: 'user-B',
        type: RtcMessageType.candidate,
        payload: {
          'candidate': 'candidate:foo bar 1 udp 12345',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
        created: DateTime.utc(2026, 4, 29),
      );

      final body = msg.toCreateBody();

      expect(body.keys, containsAll(['roomId', 'creator', 'target', 'type', 'payload']));
      expect(body['roomId'], 'chat-1');
      expect(body['creator'], 'user-A');
      expect(body['target'], 'user-B');
      expect(body['type'], 'candidate');
      expect(body['payload'], isA<Map<String, dynamic>>());
      expect(body['payload']['candidate'], startsWith('candidate:'));
    });

    test('does not include id, created, or updated fields', () {
      final msg = RtcMessage(
        id: 'should-not-appear',
        roomId: 'r',
        creator: 'a',
        target: 'b',
        type: RtcMessageType.hangup,
        payload: const <String, dynamic>{},
        created: DateTime.utc(2026, 4, 29),
      );

      final body = msg.toCreateBody();

      expect(body.containsKey('id'), isFalse);
      expect(body.containsKey('created'), isFalse);
      expect(body.containsKey('updated'), isFalse);
    });

    test('encodes each RtcMessageType as its wire value', () {
      for (final type in RtcMessageType.values) {
        final msg = RtcMessage(
          id: '',
          roomId: 'r',
          creator: 'a',
          target: 'b',
          type: type,
          payload: const <String, dynamic>{},
          created: DateTime.utc(2026, 4, 29),
        );

        expect(msg.toCreateBody()['type'], type.wireValue);
      }
    });
  });

  test('round-trip: fromRecord(record).toCreateBody() preserves wire fields',
      () {
      final record = RecordModel({
        'id': 'rt',
        'created': '2026-04-29 12:00:00.000Z',
        'collectionName': 'rtc_signaling',
        'roomId': 'room-X',
        'creator': 'sender',
        'target': 'receiver',
        'type': 'answer',
        'payload': {'sdp': 'v=0\r\n', 'type': 'answer'},
      });

    final body = RtcMessage.fromRecord(record).toCreateBody();

    expect(body['roomId'], 'room-X');
    expect(body['creator'], 'sender');
    expect(body['target'], 'receiver');
    expect(body['type'], 'answer');
    expect(body['payload']['sdp'], 'v=0\r\n');
  });

  group('PocketBase id translation', () {
    const localUuid = '550e8400-e29b-41d4-a716-446655440000';
    const pbId = '550e8400e29b41d4a716446655440000';

    test('fromRecord rehydrates pb-id back into canonical UUID form', () {
      final record = RecordModel({
        'id': 'rec_uuid',
        'created': '2026-05-14 00:00:00.000Z',
        'collectionName': 'rtc_signaling',
        'roomId': 'room-1',
        // Wire-level ids do NOT contain dashes (PocketBase record ids).
        'creator': pbId,
        'target': pbId,
        'type': 'offer',
        'payload': const <String, dynamic>{},
      });

      final msg = RtcMessage.fromRecord(record);

      expect(msg.creator, localUuid);
      expect(msg.target, localUuid);
    });

    test('toCreateBody strips dashes when emitting wire payload', () {
      final msg = RtcMessage(
        id: '',
        roomId: 'room-1',
        creator: localUuid,
        target: localUuid,
        type: RtcMessageType.offer,
        payload: const <String, dynamic>{},
        created: DateTime.utc(2026, 5, 14),
      );

      final body = msg.toCreateBody();

      expect(body['creator'], pbId);
      expect(body['target'], pbId);
    });
  });
}
