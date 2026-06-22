import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:stealth/logging/logger.dart';
import '../constants/app_colors.dart';
import '../constants/app_motion.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../effects/chromatic_aberration.dart';

class GlassTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final int? maxLines;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final FocusNode? focusNode;

  const GlassTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    this.onChanged,
    this.validator,
    this.enabled = true,
    this.focusNode,
  });

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

BoxDecoration _glassFieldDecoration({
  required bool focused,
  required Color fillColor,
}) {
  return BoxDecoration(
    color: fillColor,
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    border: Border.all(
      color: focused
          ? AppColors.systemBlue
          : AppColors.glassMedium.withValues(alpha: 0.3),
      width: focused ? 2 : 1,
    ),
  );
}

class _GlassFieldGhost extends StatelessWidget {
  const _GlassFieldGhost({required this.focused});

  final bool focused;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _glassFieldDecoration(
        focused: focused,
        fillColor: Colors.transparent,
      ),
    );
  }
}

class _GlassTextFieldState extends State<GlassTextField>
    with SingleTickerProviderStateMixin {
  late FocusNode _focusNode;
  bool _isFocused = false;

  /// Drives the brief chromatic-aberration pulse on focus gain.
  /// Tweens 1 → 0 over `AppMotion.normal` whenever focus is gained;
  /// idle value is 0 (no overlay rendered — short-circuit in the
  /// `ChromaticAberration` widget). Auto-disables in light mode.
  late final AnimationController _aberrationCtrl;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
    _aberrationCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.normal,
      value: 0,
    );
    if (kIsWeb) {
      Logger.debug('[ds:glass-text-field] perf-budget cheap-ghost path active');
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    _aberrationCtrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final gained = _focusNode.hasFocus && !_isFocused;
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
    if (gained) {
      _aberrationCtrl
        ..value = 1
        ..animateTo(0, curve: AppMotion.emphasized);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.labelText != null) ...[
          Text(
            widget.labelText!,
            style: AppTypography.footnote.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        AnimatedBuilder(
          animation: _aberrationCtrl,
          builder: (context, _) {
            final input = Container(
              decoration: _glassFieldDecoration(
                focused: _isFocused,
                fillColor: _isFocused
                    ? AppColors.glassMedium
                    : AppColors.glassUltraDark,
              ),
              child: TextFormField(
                controller: widget.controller,
                focusNode: _focusNode,
                obscureText: widget.obscureText,
                keyboardType: widget.keyboardType,
                maxLines: widget.maxLines,
                enabled: widget.enabled,
                onChanged: widget.onChanged,
                validator: widget.validator,
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: AppTypography.body.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  prefixIcon: widget.prefixIcon,
                  suffixIcon: widget.suffixIcon,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  filled: false,
                ),
              ),
            );

            if (kIsWeb) return input;

            if (_aberrationCtrl.value > 0) {
              return ChromaticAberration(
                intensity: _aberrationCtrl.value,
                ghostBuilder: (_) => _GlassFieldGhost(focused: _isFocused),
                child: input,
              );
            }

            return input;
          },
        ),
      ],
    );
  }
}

class GlassSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  const GlassSearchField({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isWeb = kIsWeb;

    final input = Container(
      decoration: BoxDecoration(
        color: AppColors.glassMedium,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: AppColors.glassMedium.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: AppTypography.body.copyWith(
          color: AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hintText ?? 'Поиск',
          hintStyle: AppTypography.body.copyWith(
            color: AppColors.textTertiary,
          ),
          prefixIcon: const Icon(
            Icons.search,
            color: AppColors.textSecondary,
            size: AppSpacing.iconMd,
          ),
          suffixIcon: controller?.text.isNotEmpty ?? false
              ? IconButton(
                  icon: const Icon(
                    Icons.clear,
                    color: AppColors.textSecondary,
                    size: AppSpacing.iconSm,
                  ),
                  onPressed: () {
                    controller?.clear();
                    onClear?.call();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          filled: false,
        ),
      ),
    );

    if (isWeb) return input;

    return input;
  }
}
