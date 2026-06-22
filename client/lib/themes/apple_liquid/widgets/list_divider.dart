import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';

/// Hair-thin divider for list rows.
///
/// Replaces inline `Divider(height: 1, color: ...)` and ad-hoc
/// `SizedBox` separators sprinkled across screens. Uses
/// [AppColors.dividerSubtle] (translucent) so it sits softly over
/// glass surfaces.
///
/// [indent] / [endIndent] follow Material `Divider` semantics —
/// useful for "list with leading avatar" patterns where the divider
/// should start aligned with the row text, not the avatar.
class ListDivider extends StatelessWidget {
  const ListDivider({
    super.key,
    this.indent = 0,
    this.endIndent = 0,
  });

  /// Convenience for divider that aligns past a leading avatar
  /// (`AppSpacing.iconLg + AppSpacing.md` = 32 + 16 = 48 px inset).
  const ListDivider.insetForAvatar({super.key})
      : indent = AppSpacing.iconLg + AppSpacing.md,
        endIndent = 0;

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return Divider(
      color: AppColors.dividerSubtle,
      height: 1,
      thickness: 1,
      indent: indent,
      endIndent: endIndent,
    );
  }
}
