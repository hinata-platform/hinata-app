import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/sprint/modals/glass_modal.dart';
import '../theme/app_colors.dart';

/// Opens [message] (under [title], when there is one) beside [anchorContext]:
/// anchored to it on a wide window, as a glass bottom sheet on a phone.
void showInfoText(
  BuildContext anchorContext, {
  required String message,
  String? title,
}) {
  final box = anchorContext.findRenderObject()! as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  Widget body(BuildContext _) => _InfoBody(title: title, message: message);
  if (MediaQuery.sizeOf(anchorContext).width >= kGlassPopoverBreakpoint) {
    showGlassAnchoredPopover<void>(
      anchorContext,
      anchorRect: anchor,
      width: 340,
      minHeight: 120,
      maxHeight: 420,
      builder: body,
    );
  } else {
    showGlassBottomSheet<void>(anchorContext, builder: body);
  }
}

/// A small round "i" next to a title that keeps a long explanation one tap
/// away instead of printing it under the title.
///
/// The ring is 26 across, the hit area the full 48. [compact] trims the hit
/// area to 40 × 32 so the ring can sit in a title line without making it
/// taller. A tap opens [message] under [title] (see [showInfoText]).
/// [tooltip] names the button for the pointer and the screen reader.
class InfoCircleButton extends StatelessWidget {
  const InfoCircleButton({
    super.key,
    required this.message,
    required this.tooltip,
    this.title,
    this.compact = false,
  });

  final String? title;
  final String message;
  final String tooltip;
  final bool compact;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: () => showInfoText(context, title: title, message: message),
    tooltip: tooltip,
    constraints: compact
        ? const BoxConstraints.tightFor(width: 40, height: 32)
        : const BoxConstraints.tightFor(width: 48, height: 48),
    padding: EdgeInsets.zero,
    icon: const InfoRing(),
  );
}

/// The ring of an [InfoCircleButton], on its own for rows that are tappable
/// as a whole.
class InfoRing extends StatelessWidget {
  const InfoRing({super.key, this.size = 26});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.surfaceMuted,
      border: Border.all(color: AppColors.hairline),
    ),
    child: Icon(LucideIcons.info, size: size * 0.54, color: AppColors.inkSoft),
  );
}

class _InfoBody extends StatelessWidget {
  const _InfoBody({required this.title, required this.message});

  final String? title;
  final String message;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
        ],
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
