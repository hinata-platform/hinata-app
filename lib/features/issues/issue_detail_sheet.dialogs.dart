part of 'issue_detail_sheet.dart';

// ─────────────────────── Delete confirmation ───────────────────────────────

/// Destructive confirm presented on the app's Liquid-Glass modal material
/// (matches the Teams `ModalShell`/`ModalFooter` language: danger icon chip,
/// brand-font title, hairline-divided footer with a red primary action).
class _DeleteIssueConfirm extends StatelessWidget {
  const _DeleteIssueConfirm({required this.issue});

  final Issue issue;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  LucideIcons.trash2,
                  size: 20,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.t('issues.deleteTitle'),
                      style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.t(
                        'issues.deleteBody',
                        variables: {'id': issue.readableId},
                      ),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                visualDensity: VisualDensity.compact,
                icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    context.t('common.cancel'),
                    style: TextStyle(
                      color: AppColors.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                    ),
                  ),
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  label: Text(context.t('common.delete')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Destructive confirm for deleting one's own comment. Mirrors the issue
/// delete confirm's Liquid-Glass language (danger chip, hairline footer).
class _DeleteCommentConfirm extends StatelessWidget {
  const _DeleteCommentConfirm({this.count = 1});

  /// How many comments will be deleted (batch selection shows a plural body).
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  LucideIcons.trash2,
                  size: 20,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      count > 1
                          ? context.t(
                              'comments.deleteSelectedTitle',
                              count: count,
                            )
                          : context.t('issues.deleteCommentTitle'),
                      style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count > 1
                          ? context.t(
                              'comments.deleteSelectedBody',
                              count: count,
                            )
                          : context.t('issues.deleteCommentBody'),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                visualDensity: VisualDensity.compact,
                icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.hairline2),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    context.t('common.cancel'),
                    style: TextStyle(
                      color: AppColors.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                    ),
                  ),
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  label: Text(context.t('common.delete')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── Detail row ────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.child,
    this.onTap,
    this.last = false,
  });

  final String label;
  final Widget child;

  /// Tapped to edit the field. Receives the row's global rect so the picker can
  /// anchor a dropdown popover beside it on wide screens.
  final void Function(Rect anchorRect)? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    return InkWell(
      onTap: tap == null
          ? null
          : () {
              final box = context.findRenderObject() as RenderBox?;
              final rect = (box != null && box.hasSize)
                  ? box.localToGlobal(Offset.zero) & box.size
                  : Rect.zero;
              tap(rect);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: AppColors.hairline2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(
                label,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: child),
            ),
            if (onTap != null)
              Icon(
                LucideIcons.chevronsUpDown,
                size: 16,
                color: AppColors.inkFaint,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Sub-task quick-add ────────────────────────────

/// "Add a sub-task" affordance — collapsed to a single "+" row by default so it
/// takes no vertical space, then expands into an inline title field on tap. The
/// field submits on Enter or via the "+" button and stays open for rapid entry;
/// it collapses again on Escape or when left empty.
class _SubtaskQuickAdd extends StatefulWidget {
  const _SubtaskQuickAdd({required this.onSubmit});

  final Future<void> Function(String title) onSubmit;

  @override
  State<_SubtaskQuickAdd> createState() => _SubtaskQuickAddState();
}

class _SubtaskQuickAddState extends State<_SubtaskQuickAdd> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _open = false;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _expand() {
    setState(() => _open = true);
    _focus.requestFocus();
  }

  void _collapse() {
    _ctrl.clear();
    setState(() => _open = false);
  }

  Future<void> _submit() async {
    final value = _ctrl.text.trim();
    if (value.isEmpty || _busy) return;
    setState(() => _busy = true);
    await widget.onSubmit(value);
    if (!mounted) return;
    _ctrl.clear();
    setState(() => _busy = false);
    // Keep the field open + focused so several sub-tasks can be added quickly.
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return InkWell(
        onTap: _expand,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              const Icon(LucideIcons.plus, size: 16, color: AppColors.stTodo),
              const SizedBox(width: 8),
              Text(
                context.t('issues.addSubtask'),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.stTodo,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Row(
      children: [
        // The "+" is the submit button while the field is open.
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: HiveLoader(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            onPressed: _submit,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(LucideIcons.plus, size: 18, color: AppColors.stTodo),
          ),
        const SizedBox(width: 4),
        Expanded(
          child: Focus(
            onKeyEvent: (_, event) {
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                _collapse();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              onTapOutside: (_) {
                if (_ctrl.text.trim().isEmpty) _collapse();
              },
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: context.t('issues.subtaskHint'),
                hintStyle: TextStyle(fontSize: 13.5, color: AppColors.inkFaint),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _collapse,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(LucideIcons.x, size: 16, color: AppColors.inkFaint),
        ),
      ],
    );
  }
}

// ─────────────────────────── Option picker ─────────────────────────────────

/// Single-choice picker shared by the create body. Delegates to the responsive
/// [showGlassOptions]: an anchored dropdown beside the field on wide screens, a
/// bottom sheet on phones.
Future<T?> _pickOption<T>(
  BuildContext context, {
  required String title,
  required List<({T value, Widget child})> options,
  Rect? anchorRect,
}) {
  return showGlassOptions<T>(
    context,
    title: title,
    options: options,
    anchorRect: anchorRect,
  );
}

