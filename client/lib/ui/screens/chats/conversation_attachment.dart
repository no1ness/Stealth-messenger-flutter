import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/apple_liquid/theme_exports.dart';

Widget? buildConversationAttachment({
  required Map<String, dynamic> message,
  required LocalAppService appService,
  required String chatId,
}) {
  final type = message['type'] as String?;
  final content = message['message'] as String?;
  if (content == null || content.isEmpty) return null;
  if (type != 'image' && type != 'file' && type != 'audio') return null;

  final isEncrypted = (message['metadata'] as Map?)?['file_encrypted'] == true;

  if (type == 'image') {
    if (isEncrypted) {
      return FutureBuilder<Uint8List?>(
        future: appService.downloadAttachment(content, chatId, encrypted: true),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              width: 200,
              height: 200,
              child: Center(child: StealthLoadingIndicator()),
            );
          }
          if (snapshot.hasData && snapshot.data != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                snapshot.data!,
                width: 200,
                height: 200,
                fit: BoxFit.cover,
              ),
            );
          }
          return const Icon(Icons.broken_image, size: 48);
        },
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        content,
        width: 200,
        height: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48),
      ),
    );
  }

  if (type == 'audio') {
    return _AudioAttachment(
      url: content,
      isEncrypted: isEncrypted,
      appService: appService,
      chatId: chatId,
    );
  }

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.insert_drive_file, color: AppColors.systemBlue),
      const SizedBox(width: 8),
      Text(isEncrypted ? 'Encrypted File' : 'File Attachment'),
    ],
  );
}

class _AudioAttachment extends StatelessWidget {
  const _AudioAttachment({
    required this.url,
    required this.isEncrypted,
    required this.appService,
    required this.chatId,
  });

  final String url;
  final bool isEncrypted;
  final LocalAppService appService;
  final String chatId;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.play_circle_fill,
              color: AppColors.systemBlue, size: 32),
          onPressed: () async {
            final bytes = await appService.downloadAttachment(
              url,
              chatId,
              encrypted: isEncrypted,
            );
            if (bytes != null) {
              final source = BytesSource(bytes);
              final player = AudioPlayer();
              await player.play(source);
            }
          },
        ),
        const SizedBox(width: 4),
        Text(
          isEncrypted ? 'Encrypted Voice' : 'Voice Note',
          style: AppTypography.caption1,
        ),
      ],
    );
  }
}
