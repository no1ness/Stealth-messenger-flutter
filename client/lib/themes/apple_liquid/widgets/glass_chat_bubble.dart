import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';

enum MessageType {
  sent,
  received,
}

class GlassChatBubble extends StatelessWidget {
  final String message;
  final MessageType type;
  final String? timestamp;
  final bool? isRead;
  final bool? isDelivered;
  final Widget? attachmentWidget;
  final Widget? replyPreview;

  const GlassChatBubble({
    super.key,
    required this.message,
    required this.type,
    this.timestamp,
    this.isRead,
    this.isDelivered,
    this.attachmentWidget,
    this.replyPreview,
  });

  @override
  Widget build(BuildContext context) {
    final isSent = type == MessageType.sent;

    return Padding(
      padding: EdgeInsets.only(
        left: isSent ? AppSpacing.huge : AppSpacing.md,
        right: isSent ? AppSpacing.md : AppSpacing.huge,
        bottom: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment:
            isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(AppSpacing.radiusLg),
              topRight: const Radius.circular(AppSpacing.radiusLg),
              bottomLeft: Radius.circular(
                isSent ? AppSpacing.radiusLg : AppSpacing.radiusXs,
              ),
              bottomRight: Radius.circular(
                isSent ? AppSpacing.radiusXs : AppSpacing.radiusLg,
              ),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  gradient: isSent
                      ? LinearGradient(
                          colors: AppColors.liquidGradient1,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isSent ? null : AppColors.glassMedium,
                  border: Border.all(
                    color: isSent
                        ? AppColors.glassLight.withValues(alpha: 0.3)
                        : AppColors.glassMedium.withValues(alpha: 0.5),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSent
                          ? AppColors.systemBlue.withValues(alpha: 0.2)
                          : AppColors.shadow,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (replyPreview != null) ...[
                      replyPreview!,
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    if (attachmentWidget != null) ...[
                      attachmentWidget!,
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    Text(
                      message,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (timestamp != null || isRead != null || isDelivered != null) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (timestamp != null)
                  Text(
                    timestamp!,
                    style: AppTypography.caption2.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                if (isSent && (isRead != null || isDelivered != null)) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isRead == true
                        ? Icons.done_all
                        : (isDelivered == true
                            ? Icons.done
                            : Icons.access_time),
                    size: 12,
                    color: isRead == true
                        ? AppColors.systemBlue
                        : AppColors.textTertiary,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class GlassChatInput extends StatefulWidget {
  final TextEditingController? controller;
  final VoidCallback? onSend;
  final VoidCallback? onAttachment;
  final VoidCallback? onVoice;
  final String? hintText;

  const GlassChatInput({
    super.key,
    this.controller,
    this.onSend,
    this.onAttachment,
    this.onVoice,
    this.hintText,
  });

  @override
  State<GlassChatInput> createState() => _GlassChatInputState();
}

class _GlassChatInputState extends State<GlassChatInput> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller?.text.isNotEmpty ?? false;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.darkGray2.withValues(alpha: 0.8),
            border: const Border(
              top: BorderSide(
                color: AppColors.separator,
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  if (widget.onAttachment != null)
                    IconButton(
                      icon: const Icon(
                        Icons.add_circle,
                        color: AppColors.systemBlue,
                      ),
                      onPressed: widget.onAttachment,
                    ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.glassMedium,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusLg),
                            border: Border.all(
                              color:
                                  AppColors.glassMedium.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: TextField(
                            controller: widget.controller,
                            maxLines: null,
                            style: AppTypography.body.copyWith(
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: widget.hintText ?? 'Message',
                              hintStyle: AppTypography.body.copyWith(
                                color: AppColors.textTertiary,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  GestureDetector(
                    onTap: _hasText ? widget.onSend : widget.onVoice,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: _hasText
                            ? LinearGradient(
                                colors: AppColors.liquidGradient1,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: _hasText ? null : AppColors.glassMedium,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.glassLight.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        _hasText ? Icons.arrow_upward : Icons.mic,
                        color: AppColors.textPrimary,
                        size: AppSpacing.iconSm,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
