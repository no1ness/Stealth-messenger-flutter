import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_motion.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../effects/scanline_overlay.dart';

enum MessageType {
  sent,
  received,
}

/// Chat bubble with the design-system v2 polish:
///
/// - Signature `ScanlineOverlay` on outgoing (`sent`) bubbles —
///   the visual ownership marker that travels with messages you've
///   sent. Auto-disables in `Brightness.light`.
/// - Monospace timestamps (`AppTypography.captionMono`) — every
///   delivery time reads like a value out of `date`.
/// - Soft scale-pulse on the delivered/read tick icon when the
///   status advances, on `AppMotion.fast`.
/// - Wrapped in `RepaintBoundary` so the bubble's own animations
///   don't invalidate the surrounding conversation list.
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

    Widget bubble = ClipRRect(
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
                if (message.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textOnGlass,
                    ),
                  ),
                ],
              ],
              if (attachmentWidget == null)
                Text(
                  message,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textOnGlass,
                  ),
                ),
            ],
          ),
        ),
    );

    // Signature scan-line on outgoing bubbles only. The overlay
    // auto-disables in light mode (see ScanlineOverlay docs).
    if (isSent) {
      bubble = ScanlineOverlay(intensity: 0.5, child: bubble);
    }

    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.only(
          left: isSent ? AppSpacing.huge : AppSpacing.md,
          right: isSent ? AppSpacing.md : AppSpacing.huge,
          bottom: AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment:
              isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            bubble,
            if (timestamp != null || isRead != null || isDelivered != null) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (timestamp != null)
                    Text(
                      timestamp!,
                      style: AppTypography.captionMono.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  if (isSent && (isRead != null || isDelivered != null)) ...[
                    const SizedBox(width: 4),
                    _DeliveryTick(
                      isRead: isRead == true,
                      isDelivered: isDelivered == true,
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Delivery/read tick with a soft scale-pulse on status advance.
class _DeliveryTick extends StatelessWidget {
  const _DeliveryTick({required this.isRead, required this.isDelivered});

  final bool isRead;
  final bool isDelivered;

  @override
  Widget build(BuildContext context) {
    final icon = isRead
        ? Icons.done_all
        : (isDelivered ? Icons.done : Icons.access_time);
    final color = isRead ? AppColors.systemBlue : AppColors.textTertiary;
    // Different ValueKeys per state cause AnimatedSwitcher to fade +
    // scale the icon as it advances pending → delivered → read.
    return AnimatedSwitcher(
      duration: AppMotion.fast,
      transitionBuilder: (child, animation) {
        return ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: Icon(
        icon,
        key: ValueKey<int>(isRead ? 2 : (isDelivered ? 1 : 0)),
        size: 12,
        color: color,
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
                      child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.glassMedium,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusLg),
                            border: Border.all(
                              color: AppColors.glassMedium.withValues(alpha: 0.3),
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
    );
  }
}
