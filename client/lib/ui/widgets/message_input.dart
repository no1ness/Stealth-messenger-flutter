import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';

class MessageInput extends StatefulWidget {
  final Function(String) onSendMessage;
  final Future<void> Function()? onAttachment;
  final Future<void> Function(String filePath)? onVoiceRecorded;
  final void Function(bool isTyping)? onTyping;

  const MessageInput({
    super.key,
    required this.onSendMessage,
    this.onAttachment,
    this.onVoiceRecorded,
    this.onTyping,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  bool _isRecording = false;
  final AudioRecorder _recorder = AudioRecorder();

  void _handleSendMessage() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onSendMessage(_controller.text.trim());
      _controller.clear();
    }
  }

  Future<void> _handleAttachment() async {
    if (widget.onAttachment != null) {
      await widget.onAttachment!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(
              top: BorderSide(
                  color: Theme.of(context).dividerColor, width: 0.5)),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attachment),
              onPressed: _handleAttachment,
              color: AppColors.systemBlue,
              tooltip: 'Прикрепить файл',
            ),
            if (!_isRecording)
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Введите сообщение...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  maxLines: 1,
                  textInputAction: TextInputAction.send,
                  keyboardType: TextInputType.text,
                  onSubmitted: (_) => _handleSendMessage(),
                  onChanged: (_) =>
                      widget.onTyping?.call(_controller.text.trim().isNotEmpty),
                ),
              ),
            // Кнопка записи голоса (минимальная реализация)
            IconButton(
              icon: Icon(_isRecording ? Icons.stop_circle : Icons.mic),
              tooltip:
                  _isRecording ? 'Остановить запись' : 'Записать голосовое',
              onPressed: () async {
                if (widget.onVoiceRecorded == null) return;
                if (!_isRecording) {
                  // Проверяем и запрашиваем доступ к микрофону
                  await Permission.microphone.request();
                  final hasPermission = await _recorder.hasPermission();
                  if (!hasPermission) return;
                  // Путь для файла
                  final dir = await getTemporaryDirectory();
                  final path =
                      '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
                  // Запуск записи
                  await _recorder.start(
                    const RecordConfig(
                      encoder: AudioEncoder.aacLc,
                      bitRate: 128000,
                      sampleRate: 44100,
                    ),
                    path: path,
                  );
                  setState(() => _isRecording = true);
                } else {
                  // Остановка и получение пути
                  final recordedPath = await _recorder.stop();
                  setState(() => _isRecording = false);
                  if (recordedPath != null) {
                    await widget.onVoiceRecorded!.call(recordedPath);
                  }
                }
              },
            ),
            const SizedBox(width: 4),
            if (!_isRecording)
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _handleSendMessage,
                color: AppColors.systemBlue,
                tooltip: 'Отправить',
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _recorder.dispose();
    super.dispose();
  }
}
