import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import 'package:stealth/constants/accessibility_ids.dart';

class GlassMessageInput extends StatefulWidget {
  final Function(String) onSendMessage;
  final Future<void> Function()? onAttachment;
  final Future<void> Function(String filePath)? onVoiceRecorded;
  final void Function(bool isTyping)? onTyping;

  const GlassMessageInput({
    super.key,
    required this.onSendMessage,
    this.onAttachment,
    this.onVoiceRecorded,
    this.onTyping,
  });

  @override
  State<GlassMessageInput> createState() => _GlassMessageInputState();
}

class _GlassMessageInputState extends State<GlassMessageInput> {
  final TextEditingController _controller = TextEditingController();
  bool _isRecording = false;
  final AudioRecorder _recorder = AudioRecorder();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (_hasText != hasText) {
      setState(() {
        _hasText = hasText;
      });
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
    if (widget.onAttachment != null) {
      await widget.onAttachment!();
    }
  }

  Future<void> _toggleRecording() async {
    if (widget.onVoiceRecorded == null) return;

    if (!_isRecording) {
      // Check permission
      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        status = await Permission.microphone.request();
        if (!status.isGranted) return;
      }

      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return;

      // Prepare path
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Start recording
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
      // Stop recording
      final recordedPath = await _recorder.stop();
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
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.glassUltraDark,
            border: Border(
              top: BorderSide(
                color: AppColors.glassLight.withValues(alpha: 0.1),
                width: 0.5,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attachment Button
                _buildIconButton(
                  icon: Icons.add,
                  onPressed: _handleAttachment,
                  semanticsLabel: AccessibilityIds.attachFile,
                ),
                const SizedBox(width: AppSpacing.sm),

                // Input Field or Recording Indicator
                Expanded(
                  child: _isRecording
                      ? _buildRecordingIndicator()
                      : _buildTextField(),
                ),

                const SizedBox(width: AppSpacing.sm),

                // Send or Mic Button
                if (_hasText)
                  _buildSendButton()
                else
                  _buildIconButton(
                    icon: _isRecording ? Icons.stop : Icons.mic,
                    onPressed: _toggleRecording,
                    color: _isRecording ? AppColors.systemRed : null,
                    active: _isRecording,
                    semanticsLabel:
                        _isRecording ? 'Stop recording' : 'Record voice',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.glassLight.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Semantics(
        label: AccessibilityIds.messageInput,
        textField: true,
        child: TextField(
          controller: _controller,
          maxLines: 5,
          minLines: 1,
          style: AppTypography.body.copyWith(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Message',
            hintStyle: AppTypography.body.copyWith(
              color: Colors.white.withValues(alpha: 0.5),
            ),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            filled: false, // Don't use global theme fill color
          ),
          textCapitalization: TextCapitalization.sentences,
          cursorColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildRecordingIndicator() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.systemRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.systemRed.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.fiber_manual_record,
              color: AppColors.systemRed, size: 12),
          const SizedBox(width: 8),
          Text(
            'Recording...',
            style: AppTypography.body.copyWith(color: AppColors.systemRed),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
    bool active = false,
    String? semanticsLabel,
  }) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active
                ? (color ?? AppColors.systemBlue).withValues(alpha: 0.2)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: color ?? AppColors.systemBlue,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildSendButton() {
    return Semantics(
      label: AccessibilityIds.sendMessage,
      button: true,
      child: GestureDetector(
        onTap: _handleSendMessage,
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: AppColors.systemBlue,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.arrow_upward,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
