import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/local_database_service.dart';

class P2PService {
  final SupabaseService _supabase = SupabaseService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  
  final Map<String, RTCPeerConnection> _connections = {};
  final Map<String, RTCDataChannel> _dataChannels = {};
  
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
      
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  Future<void> connectToPeer(String chatId) async {
    if (_connections.containsKey(chatId)) return;

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    final pc = await createPeerConnection(config);
    _connections[chatId] = pc;

    final dc = await pc.createDataChannel('messaging', RTCDataChannelInit());
    _setupDataChannel(chatId, dc);

    pc.onIceCandidate = (candidate) {
      _supabase.sendIceCandidate(chatId: chatId, candidate: candidate.toMap());
    };

    pc.onDataChannel = (dc) {
      _setupDataChannel(chatId, dc);
    };

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await _supabase.sendOffer(chatId: chatId, offer: offer.toMap());
  }

  void _setupDataChannel(String chatId, RTCDataChannel dc) {
    _dataChannels[chatId] = dc;
    dc.onMessage = (data) {
      final message = jsonDecode(data.text);
      _messageController.add({
        'chat_id': chatId,
        'message': message,
      });
      _localDb.saveMessage(message);
    };
    
    dc.onDataChannelState = (state) {
      // ignore: avoid_print
      print('[p2p] DataChannel state for $chatId: $state');
    };
  }

  Future<void> sendMessage(String chatId, Map<String, dynamic> message) async {
    final dc = _dataChannels[chatId];
    if (dc != null && dc.state == RTCDataChannelState.RTCDataChannelOpen) {
      dc.send(RTCDataChannelMessage(jsonEncode(message)));
      _localDb.saveMessage(message);
    } else {
      // Fallback to Supabase
      await _supabase.sendMessage(
        chatId: chatId,
        content: message['content'],
        type: message['type'],
      );
      _localDb.saveMessage(message);
    }
  }

  // Implementation of Answer side...
  Future<void> handleOffer(String chatId, Map<String, dynamic> offer) async {
    // Similar to WebRTCCallScreen logic but for DataChannel
  }
}
