import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:stealth/local_database_service.dart';
import 'package:stealth/services/signaling/peer_resolver.dart';
import 'package:stealth/services/signaling/rtc_message.dart';
import 'package:stealth/services/signaling/webrtc_signaling_service.dart';
import 'package:stealth/storage_service.dart';

class P2PService {
  P2PService._();
  static final P2PService instance = P2PService._();

  final LocalDatabaseService _localDb = LocalDatabaseService();
  final StorageService _storage = StorageService();
  final PeerResolver _peerResolver = PeerResolver();

  final Map<String, RTCPeerConnection> _connections = {};
  final Map<String, RTCDataChannel> _dataChannels = {};
  final Map<String, WebRtcSignalingService> _signaling = {};
  final Map<String, StreamSubscription<RtcMessage>> _signalingSubs = {};

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  Future<RTCPeerConnection> _createConnection(String chatId) async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        // TODO: Add TURN servers for better reliability
      ],
      'sdpSemantics': 'unified-plan',
    };

    final pc = await createPeerConnection(config);
    _connections[chatId] = pc;

    pc.onIceCandidate = (candidate) async {
      final target = await _resolveTarget(chatId);
      if (target == null) return;
      await _ensureSignaling(chatId);
      await _signaling[chatId]?.sendCandidate(
        roomId: chatId,
        targetUserId: target,
        candidate: {
          ...candidate.toMap(),
          'purpose': 'datachannel',
        },
      );
    };

    pc.onDataChannel = (dc) {
      _setupDataChannel(chatId, dc);
    };

    return pc;
  }

  Future<void> connectToPeer(String chatId) async {
    if (_connections.containsKey(chatId)) return;

    final target = await _resolveTarget(chatId);
    if (target == null) {
      debugPrint('[FIX:local-only] P2P target unresolved for chatId=$chatId');
      return;
    }
    await _ensureSignaling(chatId);
    final pc = await _createConnection(chatId);
    final dc = await pc.createDataChannel('messaging', RTCDataChannelInit());
    _setupDataChannel(chatId, dc);

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await _signaling[chatId]?.sendOffer(
      roomId: chatId,
      targetUserId: target,
      sdp: {
        ...offer.toMap(),
        'purpose': 'datachannel',
      },
    );
  }

  Future<void> subscribeSignaling(String chatId) async {
    await _ensureSignaling(chatId);
  }

  Future<void> _ensureSignaling(String chatId) async {
    if (_signaling.containsKey(chatId)) return;
    final selfUserId = await _storage.read('userId');
    if (selfUserId == null || selfUserId.isEmpty) return;
    final service = WebRtcSignalingService();
    await service.connect(roomId: chatId, selfUserId: selfUserId);
    _signaling[chatId] = service;
    _signalingSubs[chatId] = service.incoming.listen((message) async {
      if (message.payload['purpose'] != 'datachannel') return;
      switch (message.type) {
        case RtcMessageType.offer:
          await handleOffer(chatId, message.payload, fromUserId: message.creator);
          break;
        case RtcMessageType.answer:
          await handleAnswer(chatId, message.payload);
          break;
        case RtcMessageType.candidate:
          await handleIceCandidate(chatId, message.payload);
          break;
        case RtcMessageType.hangup:
          disposeConnection(chatId);
          break;
      }
    });
    debugPrint('[FIX:local-only] P2P signaling subscribed chatId=$chatId');
  }

  Future<String?> _resolveTarget(String chatId) async {
    final selfUserId = await _storage.read('userId');
    if (selfUserId == null || selfUserId.isEmpty) return null;
    try {
      return await _peerResolver.resolveTarget(
        chatId: chatId,
        selfUserId: selfUserId,
      );
    } catch (error) {
      debugPrint('[FIX:local-only] P2P resolve target failed: $error');
      return null;
    }
  }

  void _setupDataChannel(String chatId, RTCDataChannel dc) {
    _dataChannels[chatId] = dc;
    dc.onMessage = (data) async {
      try {
        final message = jsonDecode(data.text) as Map<String, dynamic>;
        _messageController.add({
          'chat_id': chatId,
          'message': message,
        });
        // P2P delivery is live, so the local delivery marker is true.
        await _localDb.saveMessage(message, synced: true);
        final chat = await _localDb.getChatById(chatId);
        if (chat != null) {
          chat['updated_at'] = message['created_at']?.toString() ??
              DateTime.now().toIso8601String();
          await _localDb.saveChat(chat);
        }
      } catch (e) {
        debugPrint('[p2p] Error receiving message: $e');
      }
    };

    dc.onDataChannelState = (state) {
      debugPrint('[p2p] DataChannel state for $chatId: $state');
      if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _dataChannels.remove(chatId);
      }
    };
  }

  /// Returns true if a P2P data channel is open and ready to send.
  bool isP2PReady(String chatId) {
    final dc = _dataChannels[chatId];
    return dc != null && dc.state == RTCDataChannelState.RTCDataChannelOpen;
  }

  Future<bool> sendP2PMessage(String chatId, Map<String, dynamic> message) async {
    final dc = _dataChannels[chatId];
    if (dc != null && dc.state == RTCDataChannelState.RTCDataChannelOpen) {
      dc.send(RTCDataChannelMessage(jsonEncode(message)));
      return true;
    }
    return false;
  }

  Future<void> handleOffer(
    String chatId,
    Map<String, dynamic> offerMap, {
    String? fromUserId,
  }) async {
    await _ensureSignaling(chatId);
    final pc = await _createConnection(chatId);
    final offer = RTCSessionDescription(offerMap['sdp'], offerMap['type']);
    await pc.setRemoteDescription(offer);

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    final target = fromUserId ?? await _resolveTarget(chatId);
    if (target == null) return;
    await _signaling[chatId]?.sendAnswer(
      roomId: chatId,
      targetUserId: target,
      sdp: {
        ...answer.toMap(),
        'purpose': 'datachannel',
      },
    );
  }

  Future<void> handleAnswer(String chatId, Map<String, dynamic> answerMap) async {
    final pc = _connections[chatId];
    if (pc == null) return;
    final answer = RTCSessionDescription(answerMap['sdp'], answerMap['type']);
    await pc.setRemoteDescription(answer);
  }

  Future<void> handleIceCandidate(
      String chatId, Map<String, dynamic> candidateMap) async {
    final pc = _connections[chatId];
    if (pc == null) return;
    final candidate = RTCIceCandidate(
      candidateMap['candidate'],
      candidateMap['sdpMid'],
      candidateMap['sdpMLineIndex'],
    );
    await pc.addCandidate(candidate);
  }

  void disposeConnection(String chatId) {
    final sub = _signalingSubs.remove(chatId);
    if (sub != null) {
      unawaited(sub.cancel());
    }
    final signaling = _signaling.remove(chatId);
    if (signaling != null) {
      unawaited(signaling.disconnect());
    }
    _dataChannels[chatId]?.close();
    _dataChannels.remove(chatId);
    _connections[chatId]?.dispose();
    _connections.remove(chatId);
  }
}
