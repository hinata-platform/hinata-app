import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/glass_field.dart';

/// A one-line form field that opens a picker: the app's rule against inline
/// selection lists, applied to every form that picks a value.
///
/// A picker that hangs off the field reads the field's rectangle from a key
/// around it (`anchorRectOf`), so the field itself stays a plain button.
class FieldButton extends StatelessWidget {
  const FieldButton({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.leading,
    this.empty = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  /// Drawn in place of [icon] — a chosen person's face, say.
  final Widget? leading;

  /// Whether [value] is the field's placeholder rather than a choice, which
  /// draws it in the quieter placeholder ink.
  final bool empty;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: GlassFieldStyle.decoration,
        child: Row(
          children: [
            leading ?? Icon(icon, size: 16, color: AppColors.inkSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GlassFieldStyle.caption),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: empty
                        ? GlassFieldStyle.placeholder
                        : GlassFieldStyle.value,
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 15, color: AppColors.inkSoft),
          ],
        ),
      ),
    ),
  );
}
