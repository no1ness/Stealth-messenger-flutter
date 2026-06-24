import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:stealth/themes/tg/tg_colors.dart';
import 'package:stealth/themes/tg/tg_spacing.dart';

class TgMessageInput extends StatefulWidget {
  final Function(String) onSendMessage;
  final Future<void> Function()? onAttachment;
  final Future<void> Function(String filePath)? onVoiceRecorded;
  final void Function(bool isTyping)? onTyping;

  const TgMessageInput({
    super.key,
    required this.onSendMessage,
    this.onAttachment,
    this.onVoiceRecorded,
    this.onTyping,
  });

  @override
  State<TgMessageInput> createState() => _TgMessageInputState();
}

class _TgMessageInputState extends State<TgMessageInput> {
  final TextEditingController _controller = TextEditingController();
  bool _isRecording = false;
  final AudioRecorder _recorder = AudioRecorder();
  bool _hasText = false;

  static const double _controlSize = 44;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (_hasText != hasText) {
      setState(() => _hasText = hasText);
      widget.onTyping?.call(hasText);
    }
  }

  void _handleSendMessage() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onSendMessage(_controller.text.trim());
      _controller.clear();
    }
  }

  Future<void> _handleAttachment() async {
    await widget.onAttachment?.call();
  }

  Future<void> _toggleRecording() async {
    if (widget.onVoiceRecorded == null) return;
    if (!_isRecording) {
      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        status = await Permission.microphone.request();
        if (!status.isGranted) return;
      }
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return;

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100), path: path);
      if (!mounted) return;
      setState(() => _isRecording = true);
    } else {
      final recordedPath = await _recorder.stop();
      if (!mounted) return;
      setState(() => _isRecording = false);
      if (recordedPath != null) {
        await widget.onVoiceRecorded!.call(recordedPath);
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.backgroundSecondary,
        border: Border(top: BorderSide(color: c.dividers, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: TgSpacing.md, vertical: TgSpacing.sm),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildIconButton(icon: Icons.add, color: c.primary, onPressed: _handleAttachment),
            const SizedBox(width: TgSpacing.sm),
            Expanded(child: _isRecording ? _buildRecordingIndicator(c) : _buildTextField(c)),
            const SizedBox(width: TgSpacing.sm),
            if (_hasText)
              _buildSendButton(c)
            else
              _buildIconButton(
                icon: _isRecording ? Icons.stop : Icons.mic,
                color: _isRecording ? Colors.red : c.primary,
                onPressed: _toggleRecording,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TgThemeColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(TgSpacing.radiusXl),
        border: Border.all(color: c.bordersInput, width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: TgSpacing.md),
      child: TextField(
        controller: _controller,
        maxLines: 5,
        minLines: 1,
        style: TextStyle(fontSize: 16, color: c.text, height: 1.4),
        decoration: InputDecoration(
          hintText: 'Текстовое сообщение',
          hintStyle: TextStyle(fontSize: 16, color: c.textSecondary, height: 1.4),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          filled: false,
        ),
        textCapitalization: TextCapitalization.sentences,
        cursorColor: c.text,
      ),
    );
  }

  Widget _buildRecordingIndicator(TgThemeColors c) {
    return Container(
      height: _controlSize,
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(TgSpacing.radiusXl),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
          const SizedBox(width: TgSpacing.xs),
          const Text('Запись...', style: TextStyle(fontSize: 16, color: Colors.red)),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: _controlSize,
        height: _controlSize,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: Icon(icon, color: color, size: TgSpacing.iconMd),
      ),
    );
  }

  Widget _buildSendButton(TgThemeColors c) {
    return GestureDetector(
      onTap: _handleSendMessage,
      child: Container(
        width: _controlSize,
        height: _controlSize,
        decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
        child: Icon(Icons.arrow_upward, color: Colors.white, size: TgSpacing.iconSm),
      ),
    );
  }
}
