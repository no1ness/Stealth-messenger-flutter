import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/signaling/pb_user_id.dart';

/// Тип сигнального сообщения, передаваемого между пирами WebRTC через
/// коллекцию `rtc_signaling` в PocketBase.
enum RtcMessageType {
  offer,
  answer,
  candidate,
  hangup;

  String get wireValue => switch (this) {
        RtcMessageType.offer => 'offer',
        RtcMessageType.answer => 'answer',
        RtcMessageType.candidate => 'candidate',
        RtcMessageType.hangup => 'hangup',
      };

  static RtcMessageType fromString(String value) {
    return switch (value) {
      'offer' => RtcMessageType.offer,
      'answer' => RtcMessageType.answer,
      'candidate' => RtcMessageType.candidate,
      'hangup' => RtcMessageType.hangup,
      _ => throw ArgumentError('Unknown RtcMessageType: $value'),
    };
  }
}

/// Dart-модель записи коллекции `rtc_signaling` в PocketBase.
///
/// Каждое сообщение адресуется одному получателю (`target`) внутри одной
/// «комнаты» (`roomId` = chatId для 1:1 звонков). `payload` — сырое тело
/// SDP/ICE-кандидата, передаваемое как plain JSON.
class RtcMessage {
  final String id;
  final String roomId;
  final String creator;
  final String target;
  final RtcMessageType type;
  final Map<String, dynamic> payload;
  final DateTime created;

  const RtcMessage({
    required this.id,
    required this.roomId,
    required this.creator,
    required this.target,
    required this.type,
    required this.payload,
    required this.created,
  });

  factory RtcMessage.fromRecord(RecordModel record) {
    final typeRaw = record.getStringValue('type');
    final type = RtcMessageType.fromString(typeRaw);
    final payloadRaw = record.data['payload'];
    final payload = payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : <String, dynamic>{};
    final roomId = record.getStringValue('roomId');
    // Wire-level `creator` / `target` are PocketBase record ids and may be
    // truncated to satisfy PocketBase id limits. New clients therefore carry
    // full local ids inside payload; legacy records fall back to best-effort
    // PB-id conversion.
    final creator = payload['creatorLocalId']?.toString() ??
        payload['fromUserId']?.toString() ??
        localUuidFromPbId(record.getStringValue('creator'));
    final target = payload['targetLocalId']?.toString() ??
        localUuidFromPbId(record.getStringValue('target'));
    final created = DateTime.tryParse(record.get<String>('created')) ??
        DateTime.now().toUtc();

    Logger.debug('[signaling] RtcMessage parsed', extras: {
      'type': type.wireValue,
      'roomId': roomId,
      'fromUserId': creator,
      'targetUserId': target,
    });

    return RtcMessage(
      id: record.id,
      roomId: roomId,
      creator: creator,
      target: target,
      type: type,
      payload: payload,
      created: created,
    );
  }

  /// Тело для `pb.collection('rtc_signaling').create(body: ...)`.
  ///
  /// Wire-level `creator`/`target` are PocketBase record ids. Full local ids
  /// are duplicated into payload because PB ids may be lossy/truncated.
  Map<String, dynamic> toCreateBody() {
    return <String, dynamic>{
      'roomId': roomId,
      'creator': pbIdFromLocalUuid(creator),
      'target': pbIdFromLocalUuid(target),
      'type': type.wireValue,
      'payload': <String, dynamic>{
        ...payload,
        'creatorLocalId': creator,
        'targetLocalId': target,
      },
    };
  }
}
