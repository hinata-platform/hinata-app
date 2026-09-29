import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/sprint/modals/glass_modal.dart';
import '../theme/app_colors.dart';

/// A small round "i" next to a title that keeps a long explanation one tap
/// away instead of printing it under the title.
///
/// The ring is 26 across, the hit area the full 48. A tap opens [message]
/// under [title]: anchored beside the button on a wide window, as a glass
/// bottom sheet on a phone. [tooltip] names the button for the pointer and
/// the screen reader.
class InfoCircleButton extends StatelessWidget {
  const InfoCircleButton({
    super.key,
    required this.title,
    required this.message,
    required this.tooltip,
  });

  final String title;
  final String message;
  final String tooltip;

  void _open(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    Widget body(BuildContext _) => _InfoBody(title: title, message: message);
    if (MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint) {
      showGlassAnchoredPopover<void>(
        context,
        anchorRect: anchor,
        width: 340,
        minHeight: 120,
        maxHeight: 420,
        builder: body,
      );
    } else {
      showGlassBottomSheet<void>(context, builder: body);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: () => _open(context),
    tooltip: tooltip,
    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    padding: EdgeInsets.zero,
    icon: Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceMuted,
        border: Border.all(color: AppColors.hairline),
      ),
      child: Icon(LucideIcons.info, size: 14, color: AppColors.inkSoft),
    ),
  );
}

class _InfoBody extends StatelessWidget {
  const _InfoBody({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppColors.inkSoft,
          ),
        ),
      ],
    ),
  );
}
