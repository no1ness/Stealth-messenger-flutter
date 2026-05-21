import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/attachments/attachment_service.dart';

/// `parseLocalAttachmentId` is the pure helper at the heart of pinned-
/// message exemption + LRU eviction (task #12). These tests lock down
/// both wire shapes (v1 `attachmentId`, v2 `blobId`) plus rejection
/// cases — the full eviction loop needs a real `LocalDatabaseService`
/// and `MessageService` bootstrap (heavy platform-channel state) and
/// is covered manually per the plan.
String _wireForV1(String attachmentId) {
  final json = jsonEncode({
    'v': 1,
    'attachmentId': attachmentId,
    'fileName': 'photo.jpg',
    'payload': 'some-base64-bytes',
  });
  return 'local-attachment:${base64UrlEncode(utf8.encode(json))}';
}

String _wireForV2(String blobId) {
  final json = jsonEncode({
    'v': 2,
    'blobId': blobId,
    'hash': 'sha256-base64-truncated',
    'size': 1024,
    'mime': 'image/jpeg',
    'fileName': 'photo.jpg',
  });
  return 'local-attachment:${base64UrlEncode(utf8.encode(json))}';
}

void main() {
  group('parseLocalAttachmentId', () {
    test('extracts attachmentId from v1 wire shape', () {
      expect(
        parseLocalAttachmentId(_wireForV1('att-uuid-1')),
        'att-uuid-1',
      );
    });

    test('extracts blobId from v2 wire shape', () {
      expect(
        parseLocalAttachmentId(_wireForV2('blob-uuid-2')),
        'blob-uuid-2',
      );
    });

    test('returns null for non-attachment content', () {
      expect(parseLocalAttachmentId('hello world'), isNull);
      expect(parseLocalAttachmentId(''), isNull);
      expect(parseLocalAttachmentId('image data here'), isNull);
    });

    test('returns null for malformed envelope', () {
      expect(
          parseLocalAttachmentId('local-attachment:not-base64!!!'), isNull);
      // Valid base64, but body isn't JSON.
      expect(
        parseLocalAttachmentId(
            'local-attachment:${base64UrlEncode(utf8.encode("not-json"))}'),
        isNull,
      );
    });

    test('returns null when both blobId and attachmentId are absent', () {
      final bundle = jsonEncode({'v': 2, 'fileName': 'x.bin'});
      expect(
        parseLocalAttachmentId(
            'local-attachment:${base64UrlEncode(utf8.encode(bundle))}'),
        isNull,
      );
    });

    test('blobId takes precedence over attachmentId when both present', () {
      // Shouldn't happen in practice, but the helper's contract is
      // "v2 first, fall back to v1" — pin this so future edits don't
      // accidentally flip the priority.
      final bundle = jsonEncode({
        'v': 2,
        'blobId': 'new-blob',
        'attachmentId': 'old-att',
      });
      expect(
        parseLocalAttachmentId(
            'local-attachment:${base64UrlEncode(utf8.encode(bundle))}'),
        'new-blob',
      );
    });
  });
}
