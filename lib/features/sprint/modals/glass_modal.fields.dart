part of 'glass_modal.dart';

/// A labelled form field on the glass material.
class GlassField extends StatelessWidget {
  const GlassField({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Flexible and ellipsized: a caption over a narrow field — a
            // two-digit number box, a short code — is wider than the field in
            // several languages, and a Text in a bare Row overflows rather
            // than shrinking.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GlassFieldStyle.caption,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ],
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

/// Input decoration for a text field under a [GlassField] caption: the caption
/// stands above it, so the field itself is a single dense line.
///
/// It carries the glass field look itself rather than leaning on
/// [GlassFormTheme], because a few of these stand on a page and not in a
/// modal, and there the page theme would fill them white.
InputDecoration glassInputDecoration({String? hint}) {
  final look = GlassFieldStyle.inputTheme(const InputDecorationThemeData());
  return InputDecoration(
    hintText: hint,
    hintStyle: look.hintStyle,
    isDense: true,
    filled: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    border: look.border,
    enabledBorder: look.enabledBorder,
    disabledBorder: look.disabledBorder,
    focusedBorder: look.focusedBorder,
    errorBorder: look.errorBorder,
    focusedErrorBorder: look.focusedErrorBorder,
  );
}

/// The quiet action in a popover footer: Cancel, Clear, Back. A label and
/// nothing else, so the one button that commits is the only thing with weight.
///
/// A getter rather than a constant because [AppColors] resolves against the
/// current brightness; a `final` here would freeze the light-mode ink into
/// every dark-mode footer for the life of the isolate.
ButtonStyle get glassQuietActionStyle => TextButton.styleFrom(
  foregroundColor: AppColors.inkSoft,
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  minimumSize: const Size(0, 34),
  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
  ),
);

/// The committing action in a popover footer. Deliberately smaller than
/// [GlassModalFooter]'s: a sheet fills the screen and can carry a button that
/// size, a 330-point popover cannot — there it reads as a slab.
ButtonStyle get glassCompactPrimaryStyle => FilledButton.styleFrom(
  backgroundColor: AppColors.navy,
  foregroundColor: Colors.white,
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
  minimumSize: const Size(0, 34),
  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
  ),
);

/// A segmented selector (e.g. sprint duration 1–4 weeks) sized to fill width.
class GlassSegmented extends StatelessWidget {
  const GlassSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == selected ? AppColors.navy : null,
                  borderRadius: GlassFieldStyle.radius,
                  border: Border.all(
                    color: i == selected ? AppColors.navy : GlassFieldStyle.rim,
                  ),
                ),
                child: Text(
                  labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: i == selected ? Colors.white : AppColors.inkSoft,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A read-only "commitment" / info line used in the start & complete modals.
class GlassInfoLine extends StatelessWidget {
  const GlassInfoLine({super.key, required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.inkSoft),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// One "include this too" row: a title, a sentence saying what leaving it off
/// means, and the app's single toggle.
///
/// A switch rather than a checkbox on purpose. [HiveSwitch] is the one toggle
/// the app has, so a checkbox here would be a second visual language for the
/// same yes/no — and every one of these rows sits next to other switches.
class GlassOptionRow extends StatelessWidget {
  const GlassOptionRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;

  /// Null disables the row — the option exists but cannot be changed right now.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          HiveSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Header row shared by every sprint modal: an amber icon tile, title + sub,
/// and a close button.
class GlassModalHeader extends StatelessWidget {
  const GlassModalHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.subtitleMaxLines = 2,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// How many lines the subtitle may take before it is cut off.
  ///
  /// Two is right for a 420–540 wide modal. A header reused inside an anchored
  /// dropdown has a third of that width, where the same sentence ran out
  /// mid-word — a description that stops at "ein/aus u…" is worse than no
  /// description at all.
  final int subtitleMaxLines;

  /// Extra trailing action buttons rendered to the left of the close (X)
  /// button — e.g. a maximize/minimize toggle on the email composer.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: AppColors.accentStrong),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  // Two lines, not one: on a phone the room beside the icon and
                  // the close button is about 210 points, and "Welche Tage
                  // brauchst du?" was cut after "brauchst".
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: subtitleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ...actions,
          IconButton(
            tooltip: context.t('common.cancel'),
            icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// Footer with an optional leading hint and the Cancel / confirm buttons.
class GlassModalFooter extends StatelessWidget {
  const GlassModalFooter({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    this.confirmIcon = LucideIcons.check,
    this.hint,
    this.busy = false,
    this.confirmColor,
  });

  final String confirmLabel;
  final VoidCallback? onConfirm;
  final IconData confirmIcon;
  final Widget? hint;
  final bool busy;

  /// Background colour of the confirm button. Defaults to the app's navy;
  /// pass [AppColors.danger] for destructive confirmations.
  final Color? confirmColor;

  /// The narrowest footer that still holds a hint beside both buttons.
  static const double _hintBesideButtons = 400;

  @override
  Widget build(BuildContext context) {
    final hint = this.hint;
    final cancel = TextButton(
      onPressed: busy ? null : () => Navigator.of(context).maybePop(),
      child: Text(
        context.t('common.cancel'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final confirm = FilledButton.icon(
      onPressed: busy ? null : onConfirm,
      style: FilledButton.styleFrom(
        backgroundColor: confirmColor ?? AppColors.navy,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        ),
      ),
      icon: busy
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(confirmIcon, size: 15),
      label: Text(confirmLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    return Container(
      // The bottom inset is the footer's own: as a dialog it never touched the
      // screen edge, but as the last row of a bottom sheet it sits exactly where
      // the home indicator is. `top: false` because the sheet's top is the
      // header's problem, not this one's.
      padding:
          const EdgeInsets.fromLTRB(22, 14, 22, 18) +
          EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6)),
        ),
      ),
      // Neither button is shortened. The confirm button names what is about to
      // happen and half of that name is worse than useless — "Lösc…" is not a
      // thing anyone should press — and a clipped "Abbrechen" is no better.
      // Given room they sit side by side; given less, the pair takes a second
      // line, which is the one outcome that keeps both labels readable.
      //
      // A hint takes at most half of what is left over — `Expanded`, so a short
      // one simply sits in more space than it needs, which costs nothing. A
      // footer too narrow for that gives the hint a row of its own: squeezed
      // beside both buttons in the date picker, "Ältere Tage anfragen" broke
      // over three lines.
      //
      // Both buttons used to be flexible, the leading `Spacer` included, which
      // reads like "shrink if you must" and is not what a Flex does: the row
      // was divided in three and each button capped at a third of it. On a
      // phone that third is about 110 points and the confirm button wants 135,
      // so the label was cut on every sheet in the app, in every language.
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A Wrap rather than a Row: two buttons carrying translated labels do
          // not fit a phone-width footer in every language, and one that
          // overflows shows a striped bar where the confirm button should be.
          // Given room they sit side by side exactly as before.
          final buttons = Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 6,
            children: [cancel, confirm],
          );
          if (hint != null && constraints.maxWidth < _hintBesideButtons) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [hint, const SizedBox(height: 6), buttons],
            );
          }
          if (hint != null) {
            // The buttons keep their natural width here and the hint takes what
            // is left: a Flex lays its inflexible children out first, so this is
            // the one arrangement where a long hint cannot push a button into a
            // second line beside it.
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // The gap rides inside the hint's own space rather than being a
                // fixed box beside it: a footer sized to exactly the two buttons
                // has no eight points to spare, and a SizedBox there overflows
                // by exactly that much.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: hint,
                  ),
                ),
                buttons,
              ],
            );
          }
          // Flexible so the buttons are handed a bounded width: a Wrap measured
          // unbounded lays out in one line and overflows rather than wrapping.
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [Flexible(child: buttons)],
          );
        },
      ),
    );
  }
}
