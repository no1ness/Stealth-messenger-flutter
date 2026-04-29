import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/local_database_service.dart';

class P2PService {
  P2PService._();
  static final P2PService instance = P2PService._();

  final SupabaseService _supabase = SupabaseService();
  final LocalDatabaseService _localDb = LocalDatabaseService();

  final Map<String, RTCPeerConnection> _connections = {};
  final Map<String, RTCDataChannel> _dataChannels = {};

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

    pc.onIceCandidate = (candidate) {
      _supabase.sendP2PIceCandidate(
        chatId: chatId,
        candidate: candidate.toMap(),
      );
    };

    pc.onDataChannel = (dc) {
      _setupDataChannel(chatId, dc);
    };

    return pc;
  }

  Future<void> connectToPeer(String chatId) async {
    if (_connections.containsKey(chatId)) return;

    final pc = await _createConnection(chatId);
    final dc = await pc.createDataChannel('messaging', RTCDataChannelInit());
    _setupDataChannel(chatId, dc);

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await _supabase.sendP2POffer(chatId: chatId, offer: offer.toMap());
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
        // We mark it as synced: true because P2P delivery is "live"
        // but history sync will still happen via SupabaseService if needed.
        await _localDb.saveMessage(message, synced: true);
      } catch (e) {
        // ignore: avoid_print
        print('[p2p] Error receiving message: $e');
      }
    };

    dc.onDataChannelState = (state) {
      // ignore: avoid_print
      print('[p2p] DataChannel state for $chatId: $state');
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

  Future<void> handleOffer(String chatId, Map<String, dynamic> offerMap) async {
    final pc = await _createConnection(chatId);
    final offer = RTCSessionDescription(offerMap['sdp'], offerMap['type']);
    await pc.setRemoteDescription(offer);

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await _supabase.sendP2PAnswer(chatId: chatId, answer: answer.toMap());
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
    _dataChannels[chatId]?.close();
    _dataChannels.remove(chatId);
    _connections[chatId]?.dispose();
    _connections.remove(chatId);
  }
}
