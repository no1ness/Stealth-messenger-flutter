import 'dart:convert';

sealed class TestEvent {
  String get type;
  Map<String, dynamic> toJson();

  String serialize() => jsonEncode(toJson());
}

class MessageSent extends TestEvent {
  MessageSent({
    required this.chatId,
    required this.text,
  });

  @override
  String get type => 'MessageSent';
  final String chatId;
  final String text;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'chatId': chatId,
        'text': text,
      };
}

class MessageReceived extends TestEvent {
  MessageReceived({
    required this.chatId,
    required this.fromUserId,
    required this.text,
  });

  @override
  String get type => 'MessageReceived';
  final String chatId;
  final String fromUserId;
  final String text;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'chatId': chatId,
        'fromUserId': fromUserId,
        'text': text,
      };
}

class ContactAdded extends TestEvent {
  ContactAdded({required this.userId});

  @override
  String get type => 'ContactAdded';
  final String userId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'userId': userId,
      };
}

class CallOfferCreated extends TestEvent {
  CallOfferCreated({
    required this.roomId,
    required this.targetUserId,
  });

  @override
  String get type => 'CallOfferCreated';
  final String roomId;
  final String targetUserId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'roomId': roomId,
        'targetUserId': targetUserId,
      };
}

class CallAnswered extends TestEvent {
  CallAnswered({
    required this.roomId,
    required this.fromUserId,
  });

  @override
  String get type => 'CallAnswered';
  final String roomId;
  final String fromUserId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'roomId': roomId,
        'fromUserId': fromUserId,
      };
}

class IceConnected extends TestEvent {
  IceConnected({required this.roomId});

  @override
  String get type => 'IceConnected';
  final String roomId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'roomId': roomId,
      };
}

class CallEnded extends TestEvent {
  CallEnded({required this.chatId});

  @override
  String get type => 'CallEnded';
  final String chatId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'chatId': chatId,
      };
}

class TestErrorEvent extends TestEvent {
  TestErrorEvent({required this.message});

  @override
  String get type => 'Error';
  final String message;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'message': message,
      };
}
