part of 'issues_screen.dart';

/// Asks for the one deadline a bulk edit sets on [count] issues.
///
/// Three shapes, depending on what the answer could mean:
///
/// * Without the project-templates module the question is the plain date
///   picker the detail sheet uses there too, with "clear" added, because
///   removing everyone's deadline is a fair thing to want.
/// * With it, and every issue in one [project], the full editor: a date or a
///   rule counted from that project's event date, preset to [defaultBasis],
///   the way the project counts days.
/// * With it, but a selection spanning projects ([project] null), the editor
///   in date-only form. Several projects have several event dates, and one
///   rule would land on as many different days, so it is not offered at all.
Future<DeadlineChoice?> _askBulkDeadline(
  BuildContext context, {
  required int count,
  required bool offsetsOffered,
  required Project? project,
  required RelativeDateBasis defaultBasis,
  required Future<DateTime?> Function(RelativeDate offset) resolve,
}) async {
  final title = context.t('issues.bulkDeadline.title', count: count);
  if (!offsetsOffered) {
    var cleared = false;
    final picked = await showGlassDatePicker(
      context,
      title: title,
      initialDate: DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
      onClear: () => cleared = true,
    );
    if (cleared) return const DeadlineChoice.cleared();
    return picked == null ? null : DeadlineChoice.date(picked);
  }
  return showDeadlineEditor(
    context,
    title: title,
    // Several issues have no one current deadline to start from.
    date: null,
    offset: null,
    eventDate: project?.eventDate,
    allowOffset: project != null,
    allowClear: true,
    defaultBasis: defaultBasis,
    resolve: resolve,
  );
}

/// The head's switch into and out of selection mode, on every layout.
///
/// A round glass button like the rest of the page's chrome, icon only: the
/// glyph turns from a checked list into a crossed one while selecting, so the
/// state is never carried by colour alone, and a screen reader hears it as a
/// toggle that is on or off.
class _SelectionToggle extends StatelessWidget {
  const _SelectionToggle({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Merged, so the toggled state lands on the button's own node instead of
    // on a separate one next to it that cannot be activated.
    return MergeSemantics(
      child: Semantics(
        toggled: active,
        child: GlassCircleButton(
          icon: active ? LucideIcons.listX : LucideIcons.listChecks,
          // 48, the smallest target a thumb or a tremor hits reliably.
          size: 48,
          iconSize: 20,
          tooltip: context.t(
            active ? 'issues.selection.exit' : 'issues.selection.enter',
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// The one-time tip on a phone: holding a row selects several.
///
/// Modelled on an anchored one-line tooltip with a single action (Rodrigo
/// Mafra's onboarding hints) rather than a coach-mark tour: a quiet amber-washed
/// strip right above the rows it talks about, one sentence and "got it". It
/// sits in the list, so it scrolls away with it and never covers a row, and a
/// glance is enough to take it in. Nothing about it blocks the page.
class _SelectHint extends StatelessWidget {
  const _SelectHint({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    // A live region, so a screen reader announces the tip as it appears rather
    // than leaving it to be found by swiping; a container, so it is read as
    // one sentence with its button after it.
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 4),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      LucideIcons.listChecks,
                      size: 16,
                      color: AppColors.accentInk,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Wraps instead of clipping: the sentence is long in German
                  // and longer still at twice the text size.
                  Expanded(
                    child: Text(
                      context.t('issues.multiSelectHint.text'),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accentInk,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(context.t('issues.multiSelectHint.gotIt')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
