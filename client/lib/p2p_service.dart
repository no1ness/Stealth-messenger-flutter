import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:stealth/local_database_service.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/attachments/attachment_service.dart';
import 'package:stealth/services/messaging/message_service.dart';
import 'package:stealth/services/signaling/peer_resolver.dart';
import 'package:stealth/services/signaling/rtc_message.dart';
import 'package:stealth/services/signaling/webrtc_signaling_service.dart';
import 'package:stealth/services/webrtc/ice_config.dart';
import 'package:stealth/storage_service.dart';
import 'package:stealth/test_controller/test_event.dart';

/// Per-message in-memory retry state. Resets on app restart — that is
/// intentional: a fresh tab/launch should re-try cleanly, and the
/// multi-tab anti-double-retry guard (`lastRetryAttemptedAt` written to
/// LocalDatabaseService) handles cross-tab coordination separately.
class _RetryState {
  int attempts = 0;
  Duration nextDelay = const Duration(seconds: 1);
}

/// In-memory assembly buffer for an incoming chunked blob transfer.
/// Sparse — chunks may arrive out of order over a single DataChannel
/// stream (in practice they don't, but the protocol allows it).
class _BlobAssembly {
  final int total;
  final String expectedHash;
  final String chatId;
  final String fileName;
  final String? mime;
  final bool? isGroupChat;
  final DateTime createdAt;
  final Map<int, Uint8List> chunks = <int, Uint8List>{};
  int receivedBytes = 0;

  _BlobAssembly({
    required this.total,
    required this.expectedHash,
    required this.chatId,
    required this.fileName,
    this.mime,
    this.isGroupChat,
  }) : createdAt = DateTime.now();

  bool get isComplete => chunks.length == total;
}

class P2PService {
  P2PService._();
  static final P2PService instance = P2PService._();

  /// Max retry attempts before flipping the row to `failed`. Matches the
  /// hardening plan refinement (1/2/4/8/16s, then `failed`).
  static const int _maxRetries = 5;

  /// Multi-tab anti-double-retry window. Tabs other than the leader will
  /// skip rows whose `lastRetryAttemptedAt` is younger than this.
  static const Duration _multiTabGuardWindow = Duration(seconds: 30);

  final LocalDatabaseService _localDb = LocalDatabaseService();
  final StorageService _storage = StorageService();
  final PeerResolver _peerResolver = PeerResolver();

  final Map<String, RTCPeerConnection> _connections = {};
  final Map<String, RTCDataChannel> _dataChannels = {};
  final Map<String, WebRtcSignalingService> _signaling = {};
  final Map<String, StreamSubscription<RtcMessage>> _signalingSubs = {};
  final Map<String, _RetryState> _retryState = {};

  int _reconnectCount = 0;
  DateTime? _lastConnectedAt;

  /// blobId → assembly buffer for incoming chunked blobs (task #11).
  final Map<String, _BlobAssembly> _blobAssemblies = {};

  /// Chunk size for outgoing blob transfers (~64 KB). RTCDataChannel
  /// has a per-message size limit (varies by implementation, but 64 KB
  /// is safe across all WebRTC backends).
  static const int _blobChunkBytes = 64 * 1024;
  static const int _maxBlobAssemblyBytes = 500 * 1024 * 1024;
  static const int _maxBlobChunkCount = 8192;
  static const Duration _blobAssemblyTtl = Duration(minutes: 10);

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  void Function(TestEvent)? _onTestEvent;

  void attachTestEventEmitter(void Function(TestEvent) cb) =>
      _onTestEvent = cb;

  Future<RTCPeerConnection> _createConnection(String chatId) async {
    final config = {
      'iceServers': buildIceServers(),
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 4,
      'iceTransportPolicy': 'all',
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
    if (_connections.containsKey(chatId)) {
      final dc = _dataChannels[chatId];
      if (dc != null && dc.state != RTCDataChannelState.RTCDataChannelClosed) {
        return;
      }
      _disposePeerConnectionOnly(chatId);
    }

    final target = await _resolveTarget(chatId);
    if (target == null) {
      Logger.warn('[p2p] target unresolved', extras: {'chatId': chatId});
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
          await handleOffer(chatId, message.payload,
              fromUserId: message.creator);
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
    Logger.info('[p2p] signaling subscribed', extras: {'chatId': chatId});
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
      Logger.warn('[p2p] resolve target failed', extras: {'error': error});
      return null;
    }
  }

  void _setupDataChannel(String chatId, RTCDataChannel dc) {
    _dataChannels[chatId] = dc;
    dc.onMessage = (data) async {
      try {
        final message = jsonDecode(data.text) as Map<String, dynamic>;

        // ACK frame (task #9): inbound delivery confirmation from the
        // peer. Flip the local row to `delivered` and stop here — ACKs
        // are not user-visible messages. No-op on missing row.
        if (message['type'] == 'ack') {
          final messageId = message['messageId']?.toString();
          if (messageId == null || messageId.isEmpty) {
            Logger.debug('[p2p] ack with missing messageId, ignoring');
            return;
          }
          Logger.debug('[p2p] ack received', extras: {'messageId': messageId});
          await MessageService().markDelivered(messageId);
          return;
        }

        // Chunked blob transfer (task #11): receiver-side assembly.
        if (message['type'] == 'blob-chunk') {
          await _handleBlobChunk(chatId, message);
          return;
        }

        _messageController.add({
          'chat_id': chatId,
          'message': message,
        });
        // P2P delivery is live, so the local delivery marker is true.
        // No `deliveryStatus` field for incoming rows — outgoing-only.
        await _localDb.saveMessage(message, synced: true);
        final chat = await _localDb.getChatById(chatId);
        if (chat != null) {
          chat['updated_at'] = message['created_at']?.toString() ??
              DateTime.now().toIso8601String();
          await _localDb.saveChat(chat);
        }

        _onTestEvent?.call(MessageReceived(
          chatId: chatId,
          fromUserId: message['sender_id']?.toString() ?? '',
          text: message['content']?.toString() ?? '',
        ));

        // Send ACK back so the sender can flip their local row to
        // `delivered`. Best-effort: if the DC is open we just got a
        // message on it, so .send is safe.
        final incomingMessageId = message['id']?.toString();
        if (incomingMessageId != null && incomingMessageId.isNotEmpty) {
          dc.send(RTCDataChannelMessage(jsonEncode({
            'type': 'ack',
            'messageId': incomingMessageId,
          })));
          Logger.debug('[p2p] ack sent',
              extras: {'messageId': incomingMessageId});
        }
      } catch (e) {
        Logger.warn('[p2p] error receiving message', extras: {'error': e});
      }
    };

    dc.onDataChannelState = (state) {
      Logger.debug(
        '[p2p] data channel state',
        extras: {'chatId': chatId, 'state': state},
      );
      if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _dataChannels.remove(chatId);
        _disposePeerConnectionOnly(chatId);
      } else if (state == RTCDataChannelState.RTCDataChannelOpen) {
        if (_lastConnectedAt != null) _reconnectCount++;
        _lastConnectedAt = DateTime.now();
        // Pump any pending outgoing rows for this chat as soon as the
        // channel comes up (task #9 retry worker).
        unawaited(pumpPendingForChat(chatId));
      }
    };
  }

  bool _retryWorkerStarted = false;

  int get activeChannelCount => _signalingSubs.length;

  bool get retryWorkerRunning => _retryWorkerStarted;

  /// Returns aggregated connection stats for the monitoring dashboard.
  Map<String, dynamic> getConnectionStats() {
    final openChannels = _dataChannels.values
        .where((dc) => dc.state == RTCDataChannelState.RTCDataChannelOpen)
        .length;
    return {
      'totalConnections': _connections.length,
      'openDataChannels': openChannels,
      'reconnectCount': _reconnectCount,
      'lastConnectedAt': _lastConnectedAt?.toIso8601String(),
      'connectionSummary': _connections.isEmpty
          ? 'disconnected'
          : openChannels > 0
              ? 'connected'
              : 'connecting',
    };
  }

  /// Returns true if a P2P data channel is open and ready to send.
  bool isP2PReady(String chatId) {
    final dc = _dataChannels[chatId];
    return dc != null && dc.state == RTCDataChannelState.RTCDataChannelOpen;
  }

  Future<bool> sendP2PMessage(
      String chatId, Map<String, dynamic> message) async {
    final dc = _dataChannels[chatId];
    if (dc != null && dc.state == RTCDataChannelState.RTCDataChannelOpen) {
      dc.send(RTCDataChannelMessage(jsonEncode(message)));
      return true;
    }
    return false;
  }

  /// One-shot sweep of all pending outgoing messages — call once from
  /// app bootstrap (`LocalAppService` constructor). Messages whose data
  /// channels are not yet open stay pending; their per-chat
  /// [_setupDataChannel] `onOpen` handler will retry as the DC comes up.
  Future<void> startRetryWorker() async {
    Logger.info('[p2p-retry] startRetryWorker');
    final pending = await _localDb.getPendingMessages();
    Logger.debug('[p2p-retry] startup sweep',
        extras: {'pendingCount': pending.length});
    for (final message in pending) {
      final chatId = message['chat_id']?.toString();
      if (chatId == null || chatId.isEmpty) continue;
      await _tryDeliverPending(chatId: chatId, row: message);
    }
    _retryWorkerStarted = true;
  }

  /// Pump pending outgoing rows for a single chat. Invoked from the
  /// DataChannel `open` handler.
  Future<void> pumpPendingForChat(String chatId) async {
    Logger.debug('[p2p-retry] pumpPendingForChat', extras: {'chatId': chatId});
    final pending = await _localDb.getPendingMessages();
    for (final message in pending) {
      if (message['chat_id']?.toString() != chatId) continue;
      await _tryDeliverPending(chatId: chatId, row: message);
    }
  }

  /// Resets the in-memory retry state for a message and immediately
  /// re-attempts delivery. Called by `MessageService.retryNow(messageId)`
  /// when the user taps the failed-state indicator (task #10).
  Future<void> retryNow(String messageId) async {
    final pending = await _localDb.getPendingMessages();
    Map<String, dynamic>? row;
    for (final m in pending) {
      if (m['id']?.toString() == messageId) {
        row = m;
        break;
      }
    }
    if (row == null) {
      Logger.warn(
          '[p2p-retry] retryNow: row not found in pending queue '
          '(likely user-deleted or already delivered)',
          extras: {'messageId': messageId});
      return;
    }
    final chatId = row['chat_id']?.toString();
    if (chatId == null || chatId.isEmpty) return;
    _retryState.remove(messageId);
    Logger.info('[p2p-retry] retryNow', extras: {'messageId': messageId});
    await _tryDeliverPending(chatId: chatId, row: row);
  }

  Future<void> _tryDeliverPending({
    required String chatId,
    required Map<String, dynamic> row,
  }) async {
    final messageId = row['id']?.toString();
    if (messageId == null || messageId.isEmpty) return;

    // Multi-tab anti-double-retry: skip rows whose `lastRetryAttemptedAt`
    // is younger than the guard window — another tab is leading.
    final lastIso = row['lastRetryAttemptedAt']?.toString();
    if (lastIso != null && lastIso.isNotEmpty) {
      final lastAt = DateTime.tryParse(lastIso);
      if (lastAt != null &&
          DateTime.now().difference(lastAt) < _multiTabGuardWindow) {
        Logger.debug(
            '[p2p-retry] skipped (another tab attempted within '
            '${_multiTabGuardWindow.inSeconds}s window)',
            extras: {'messageId': messageId});
        return;
      }
    }

    final state = _retryState.putIfAbsent(messageId, () => _RetryState());

    if (state.attempts >= _maxRetries) {
      Logger.warn('[p2p-retry] max attempts exhausted, marking failed',
          extras: {'messageId': messageId, 'attempts': state.attempts});
      await MessageService().markFailed(messageId);
      _retryState.remove(messageId);
      return;
    }

    state.attempts += 1;
    // Persist the attempt timestamp BEFORE sending so other tabs see it.
    await _localDb.updateMessageDeliveryStatus(messageId, 'pending',
        lastRetryAt: DateTime.now());

    final ok = await sendP2PMessage(chatId, row);
    if (ok) {
      Logger.info('[p2p-retry] resend succeeded', extras: {
        'messageId': messageId,
        'attempt': state.attempts,
      });
      final messages = MessageService();
      await messages.markSent(messageId);
      await _resendAttachmentChunksIfNeeded(
        messages: messages,
        chatId: chatId,
        row: row,
      );
      _retryState.remove(messageId);
      return;
    }

    final nextDelay = state.nextDelay;
    Logger.info('[p2p-retry] retry scheduled', extras: {
      'messageId': messageId,
      'attempt': state.attempts,
      'nextDelayMs': nextDelay.inMilliseconds,
    });
    // Exponential backoff capped at 30s.
    final doubled = state.nextDelay.inSeconds * 2;
    state.nextDelay = Duration(seconds: doubled > 30 ? 30 : doubled);

    Future.delayed(nextDelay, () {
      // Re-fetch the row in case it was deleted in the interim.
      unawaited(pumpPendingForChat(chatId));
    });
  }

  Future<void> _resendAttachmentChunksIfNeeded({
    required MessageService messages,
    required String chatId,
    required Map<String, dynamic> row,
  }) async {
    try {
      final decrypted = await messages.decryptRawMessage(row);
      final content = decrypted['content']?.toString() ?? '';
      await messages.sendAttachmentChunksIfNeeded(chatId, content);
    } catch (error) {
      Logger.warn('[p2p-retry] attachment chunk resend skipped',
          extras: {'chatId': chatId, 'error': error});
    }
  }

  Future<void> handleOffer(
    String chatId,
    Map<String, dynamic> offerMap, {
    String? fromUserId,
  }) async {
    await _ensureSignaling(chatId);
    _disposePeerConnectionOnly(chatId);
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

  Future<void> handleAnswer(
      String chatId, Map<String, dynamic> answerMap) async {
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

  // -------------- Task #11: chunked blob transfer --------------

  /// Splits an encrypted blob into ~64 KB chunks and pushes each as a
  /// `blob-chunk` DC frame to the peer. Called by `MessageService` right
  /// after sending a message whose content is a v2 attachment descriptor.
  ///
  /// The receiver assembles + sha256-verifies + saves via
  /// `AttachmentService.saveReceivedBlob` in [_handleBlobChunk]. Sender
  /// fire-and-forget: if the DC is closed mid-transfer the receiver will
  /// stay incomplete; the next message-level retry will re-send.
  Future<void> sendBlobChunks({
    required String chatId,
    required String blobId,
    required String hash,
    required String fileName,
    String? mime,
    bool? isGroupChat,
  }) async {
    final dc = _dataChannels[chatId];
    if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen) {
      Logger.debug('[p2p-blob] DC not open, deferring blob chunks',
          extras: {'chatId': chatId, 'blobId': blobId});
      return;
    }
    final bytes = await AttachmentService().readBlobBytes(blobId);
    if (bytes == null) {
      Logger.warn('[p2p-blob] blob missing locally, cannot chunk-send',
          extras: {'blobId': blobId});
      return;
    }
    final total = (bytes.length + _blobChunkBytes - 1) ~/ _blobChunkBytes;
    Logger.info('[p2p-blob] chunked transfer starting', extras: {
      'blobId': blobId,
      'size': bytes.length,
      'chunkCount': total,
    });
    for (var seq = 0; seq < total; seq++) {
      final start = seq * _blobChunkBytes;
      final end = (start + _blobChunkBytes).clamp(0, bytes.length);
      final slice = bytes.sublist(start, end);
      final frame = <String, dynamic>{
        'type': 'blob-chunk',
        'blobId': blobId,
        'seq': seq,
        'total': total,
        'hash': hash,
        'fileName': fileName,
        if (mime != null) 'mime': mime,
        if (isGroupChat != null) 'isGroupChat': isGroupChat,
        'bytes': base64Encode(slice),
      };
      dc.send(RTCDataChannelMessage(jsonEncode(frame)));
    }
    Logger.debug('[p2p-blob] all chunks sent',
        extras: {'blobId': blobId, 'chunkCount': total});
  }

  Future<void> _handleBlobChunk(
      String chatId, Map<String, dynamic> frame) async {
    _evictStaleBlobAssemblies();

    final blobId = frame['blobId']?.toString();
    final total = frame['total'] as int?;
    final seq = frame['seq'] as int?;
    final hash = frame['hash']?.toString();
    final encodedBytes = frame['bytes'];
    if (blobId == null ||
        blobId.isEmpty ||
        total == null ||
        seq == null ||
        hash == null ||
        hash.isEmpty ||
        encodedBytes is! String) {
      Logger.warn('[p2p-blob] malformed blob-chunk frame, ignoring');
      return;
    }
    if (total <= 0 || total > _maxBlobChunkCount || seq < 0 || seq >= total) {
      Logger.warn('[p2p-blob] blob-chunk bounds invalid, ignoring', extras: {
        'blobId': blobId,
        'seq': seq,
        'total': total,
      });
      return;
    }

    late final Uint8List chunkBytes;
    try {
      chunkBytes = Uint8List.fromList(base64Decode(encodedBytes));
    } catch (error) {
      Logger.warn('[p2p-blob] invalid chunk base64, ignoring',
          extras: {'blobId': blobId, 'error': error});
      return;
    }
    if (chunkBytes.length > _blobChunkBytes) {
      Logger.warn('[p2p-blob] oversized chunk, ignoring', extras: {
        'blobId': blobId,
        'seq': seq,
        'size': chunkBytes.length,
      });
      return;
    }

    final existing = _blobAssemblies[blobId];
    if (existing != null &&
        (existing.total != total ||
            existing.expectedHash != hash ||
            existing.chatId != chatId)) {
      Logger.warn('[p2p-blob] conflicting assembly metadata, discarding',
          extras: {'blobId': blobId});
      _blobAssemblies.remove(blobId);
      return;
    }

    final assembly = _blobAssemblies.putIfAbsent(
      blobId,
      () => _BlobAssembly(
        total: total,
        expectedHash: hash,
        chatId: chatId,
        fileName: frame['fileName']?.toString() ?? 'attachment',
        mime: frame['mime']?.toString(),
        isGroupChat: frame['isGroupChat'] as bool?,
      ),
    );
    final previous = assembly.chunks[seq];
    if (previous != null) {
      assembly.receivedBytes -= previous.length;
    }
    assembly.chunks[seq] = chunkBytes;
    assembly.receivedBytes += chunkBytes.length;
    if (assembly.receivedBytes > _maxBlobAssemblyBytes) {
      Logger.warn('[p2p-blob] assembly exceeded size cap, discarding', extras: {
        'blobId': blobId,
        'receivedBytes': assembly.receivedBytes,
      });
      _blobAssemblies.remove(blobId);
      return;
    }
    Logger.debug('[p2p-blob] chunk received', extras: {
      'blobId': blobId,
      'seq': seq,
      'total': total,
      'receivedChunks': assembly.chunks.length,
    });

    if (!assembly.isComplete) return;

    // Concatenate in seq order.
    final reassembled = BytesBuilder();
    for (var i = 0; i < assembly.total; i++) {
      final chunk = assembly.chunks[i];
      if (chunk == null) {
        Logger.warn('[p2p-blob] missing chunk on completion claim, aborting',
            extras: {'blobId': blobId, 'missingSeq': i});
        _blobAssemblies.remove(blobId);
        return;
      }
      reassembled.add(chunk);
    }
    final fullBytes = reassembled.toBytes();
    final actualHash = base64UrlEncode(
      (await Sha256().hash(fullBytes)).bytes,
    ).replaceAll('=', '');
    if (actualHash != assembly.expectedHash) {
      Logger.warn('[p2p-blob] sha256 mismatch, blob discarded', extras: {
        'blobId': blobId,
        'expectedHash': assembly.expectedHash,
        'actualHash': actualHash,
      });
      _blobAssemblies.remove(blobId);
      return;
    }
    await AttachmentService().saveReceivedBlob(
      blobId: blobId,
      encryptedBytes: fullBytes,
      hash: assembly.expectedHash,
      chatId: assembly.chatId,
      fileName: assembly.fileName,
      mime: assembly.mime,
      isGroupChat: assembly.isGroupChat,
    );
    _blobAssemblies.remove(blobId);
    Logger.info('[p2p-blob] blob reassembled and saved', extras: {
      'blobId': blobId,
      'size': fullBytes.length,
      'chunkCount': assembly.total,
    });
  }

  void _evictStaleBlobAssemblies() {
    final cutoff = DateTime.now().subtract(_blobAssemblyTtl);
    _blobAssemblies.removeWhere((blobId, assembly) {
      final stale = assembly.createdAt.isBefore(cutoff);
      if (stale) {
        Logger.warn('[p2p-blob] stale assembly discarded',
            extras: {'blobId': blobId});
      }
      return stale;
    });
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
    _disposePeerConnectionOnly(chatId);
  }

  void _disposePeerConnectionOnly(String chatId) {
    _dataChannels[chatId]?.close();
    _dataChannels.remove(chatId);
    final connection = _connections.remove(chatId);
    if (connection == null) return;
    connection.close();
    connection.dispose();
  }

  void dispose() {
    for (final chatId in _connections.keys.toList()) {
      disposeConnection(chatId);
    }
    _messageController.close();
  }
}
