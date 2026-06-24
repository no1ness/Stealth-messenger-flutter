import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_colors.dart';
import 'package:stealth/themes/tg/tg_spacing.dart';

class TgTextField extends StatefulWidget {
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

  const TgTextField({
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
  State<TgTextField> createState() => _TgTextFieldState();
}

class _TgTextFieldState extends State<TgTextField> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.labelText != null) ...[
          Text(widget.labelText!, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.3)),
          const SizedBox(height: TgSpacing.xs),
        ],
        Container(
          decoration: BoxDecoration(
            color: _isFocused ? c.surface : c.backgroundSecondary,
            borderRadius: BorderRadius.circular(TgSpacing.radiusMd),
            border: Border.all(
              color: _isFocused ? c.primary : c.bordersInput,
              width: _isFocused ? 2 : 1,
            ),
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
            style: TextStyle(fontSize: 16, color: c.text, height: 1.4),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: TextStyle(fontSize: 16, color: c.textSecondary, height: 1.4),
              prefixIcon: widget.prefixIcon,
              suffixIcon: widget.suffixIcon,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: TgSpacing.md, vertical: TgSpacing.sm),
              filled: false,
            ),
          ),
        ),
      ],
    );
  }
}

class TgSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  const TgSearchField({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.backgroundSecondary,
        borderRadius: BorderRadius.circular(TgSpacing.radiusMd),
        border: Border.all(color: c.bordersInput, width: 1),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 16, color: c.text, height: 1.4),
        decoration: InputDecoration(
          hintText: hintText ?? 'Поиск',
          hintStyle: TextStyle(fontSize: 16, color: c.textSecondary, height: 1.4),
          prefixIcon: Icon(Icons.search, color: c.textSecondary, size: TgSpacing.iconMd),
          suffixIcon: (controller?.text.isNotEmpty ?? false)
              ? IconButton(
                  icon: Icon(Icons.clear, color: c.textSecondary, size: TgSpacing.iconSm),
                  onPressed: () {
                    controller?.clear();
                    onClear?.call();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: TgSpacing.md, vertical: TgSpacing.sm),
          filled: false,
        ),
      ),
    );
  }
}
