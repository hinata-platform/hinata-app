import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_policy_models.dart';
import '../../../core/repositories/time_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/hue_colors.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../sprint/modals/glass_modal.dart';
import '../admin_form_helpers.dart';

/// The tag catalogue, managed.
///
/// Renaming is the reason this exists. A tag that lives only as a string on two
/// thousand entries cannot be renamed at all — it can only be searched and
/// replaced by whoever remembers to — so the catalogue is a collection, and this
/// card is where an operator tidies the reporting vocabulary their organisation
/// grew.
///
/// Both destructive actions say how many entries they touch <em>before</em> they
/// are confirmed. "Delete the tag 'meeting'" and "delete the tag 'meeting' from
/// 1,204 entries" are different decisions, and the number is the difference.
///
/// Paged, and never drained: an instance that has been running for two years has
/// a vocabulary, and a screen that loads all of it is a screen that stops
/// working on exactly the instances that need it.
class AdminTimeTagsCard extends StatefulWidget {
  const AdminTimeTagsCard({super.key});

  @override
  State<AdminTimeTagsCard> createState() => _AdminTimeTagsCardState();
}

class _AdminTimeTagsCardState extends State<AdminTimeTagsCard> {
  static const int _pageSize = 25;

  final _search = TextEditingController();
  Timer? _debounce;

  List<TimeTag> _tags = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 0;
  String? _error;

  /// Monotonic token, so a slow search resolving after a later one does not
  /// overwrite what is on screen.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  TimeRepository get _time => context.read<TimeRepository>();

  String? get _query =>
      _search.text.trim().isEmpty ? null : _search.text.trim();

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // With the counts: this screen is where a rename or a delete is decided,
      // and the number of entries behind a word is the decision.
      final page = await _time.tags(
        query: _query,
        page: 0,
        size: _pageSize,
        withUsage: true,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _tags = page.items;
        _page = 0;
        _hasMore =
            page.items.length >= _pageSize && page.total > page.items.length;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final page = await _time.tags(
        query: _query,
        page: _page + 1,
        size: _pageSize,
        withUsage: true,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _tags = [..._tags, ...page.items];
        _page += 1;
        _hasMore = page.items.length >= _pageSize && page.total > _tags.length;
        _loadingMore = false;
      });
    } on ApiFailure catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_load()),
    );
  }

  Future<void> _create() async {
    final name = await _askForName(context, title: 'admin.timeTracking.tagNew');
    if (name == null || !mounted) return;
    await _run(() => _time.createTag(name));
  }

  Future<void> _rename(TimeTag tag) async {
    final name = await _askForName(
      context,
      title: 'admin.timeTracking.tagRename',
      initial: tag.name,
      // What a rename is about to touch, said before it is confirmed.
      note: tag.entries == null
          ? null
          // count: rather than a {'count': ...} variable -- i18next picks the
          // plural form from the number, and a string never matches a rule.
          : context.t('admin.timeTracking.tagUsage', count: tag.entries),
    );
    if (name == null || name == tag.name || !mounted) return;
    await _run(() => _time.updateTag(tag.id, name: name));
  }

  Future<void> _delete(TimeTag tag) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('admin.timeTracking.tagDeleteTitle'),
      message: context.t(
        'admin.timeTracking.tagDeleteMessage',
        variables: {'name': tag.name},
        count: tag.entries ?? 0,
      ),
      confirmLabel: context.t('common.delete'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _run(() => _time.deleteTag(tag.id));
  }

  /// Runs one catalogue change and re-reads the list, whatever happened.
  ///
  /// Re-read rather than patched in place: a rename answers with how many
  /// entries moved, a delete with how many were cleared, and the counts on every
  /// other row are unaffected — but a conflict means somebody else changed the
  /// catalogue, and then the list is the only thing worth trusting.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      await _load();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      showGlassToast(
        context,
        context.t(failure.message),
        kind: GlassToastKind.error,
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      icon: LucideIcons.tags,
      title: context.t('admin.timeTracking.tagsTitle'),
      subtitle: context.t('admin.timeTracking.tagsHint'),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.t('time.tags.search'),
                  prefixIcon: const Icon(LucideIcons.search, size: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: context.t('admin.timeTracking.tagNew'),
              onPressed: _create,
              icon: const Icon(LucideIcons.plus, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: HiveLoader(size: 28)),
          )
        else if (_error != null)
          AdminNote(tone: AdminNoteTone.warning, text: context.t(_error!))
        else if (_tags.isEmpty)
          AdminNote(text: context.t('admin.timeTracking.tagsEmpty'))
        else ...[
          for (final tag in _tags)
            _TagRow(
              tag: tag,
              onRename: () => _rename(tag),
              onDelete: () => _delete(tag),
            ),
          if (_hasMore)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _loadingMore ? null : _loadMore,
                child: Text(context.t('common.loadMore')),
              ),
            ),
        ],
      ],
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tag,
    required this.onRename,
    required this.onDelete,
  });

  final TimeTag tag;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(LucideIcons.tag, size: 15, color: hueColor(tag.hue)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tag.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          if (tag.entries != null)
            Text(
              context.t('admin.timeTracking.tagUsage', count: tag.entries),
              style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
            ),
          IconButton(
            tooltip: context.t('common.rename'),
            onPressed: onRename,
            icon: const Icon(LucideIcons.pencil, size: 15),
          ),
          IconButton(
            tooltip: context.t('common.delete'),
            onPressed: onDelete,
            icon: const Icon(
              LucideIcons.trash2,
              size: 15,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}

/// A one-field glass dialog for a tag name.
Future<String?> _askForName(
  BuildContext context, {
  required String title,
  String? initial,
  String? note,
}) {
  final controller = TextEditingController(text: initial ?? '');
  return showGlassModal<String>(
    context,
    adaptive: true,
    width: 400,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.tag,
          title: context.t(title),
          subtitle: note ?? context.t('admin.timeTracking.tagNameHint'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(
              sheetContext,
            ).pop(value.trim().isEmpty ? null : value.trim()),
            decoration: InputDecoration(
              counterText: '',
              labelText: context.t('common.name'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('common.save'),
          onConfirm: () => Navigator.of(
            sheetContext,
          ).pop(controller.text.trim().isEmpty ? null : controller.text.trim()),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
