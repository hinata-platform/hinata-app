import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/api_client.dart';
import '../i18n/i18n.dart';
import '../models/core_models.dart';
import '../repositories/user_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'hive_loader.dart';
import 'hive_widgets.dart' show HiveAvatar, hiveEase;
import '../../features/sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet;

/// Opens the people picker anchored to [anchorRect] — the searchable,
/// server-paged counterpart to a dropdown that has to hold the whole directory
/// open at once.
///
/// The twin of [showProjectPicker], down to the search pill and the responsive
/// shell: an anchored panel on wide screens, a glass bottom sheet on phones
/// where an anchored one would be buried under the keyboard. Single choice, so
/// a tap picks and closes; there is no confirm step.
///
/// [selectedId] marks the current pick. [meId] gets the "(You)" suffix and is
/// nothing more than a label — the row is picked like any other. Resolves to
/// the chosen person, or null when dismissed.
Future<DirectoryUser?> showPersonPicker(
  BuildContext context, {
  required Rect anchorRect,
  String? selectedId,
  String? meId,
}) {
  // The popover is a root-navigator route and so inherits none of the caller's
  // providers — hand the repository across explicitly.
  final repo = context.read<UserRepository>();
  Widget panel(bool sheet) => RepositoryProvider<UserRepository>.value(
    value: repo,
    child: _PersonPickerPanel(selectedId: selectedId, meId: meId),
  );

  if (MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint) {
    return showGlassAnchoredPopover<DirectoryUser>(
      context,
      anchorRect: anchorRect,
      width: 340,
      minHeight: 200,
      maxHeight: 420,
      builder: (_) => panel(false),
    );
  }
  return showGlassBottomSheet<DirectoryUser>(
    context,
    builder: (_) => AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: hiveEase,
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 440),
        child: panel(true),
      ),
    ),
  );
}

/// One-line field that opens [showPersonPicker] — the app's rule against inline
/// selection lists, applied to picking a person: face, name, chevron.
class PersonPickerField extends StatelessWidget {
  const PersonPickerField({
    super.key,
    required this.person,
    required this.onTap,
    required this.placeholderKey,
    this.isMe = false,
  });

  /// The current pick, or null while nothing is chosen.
  final DirectoryUser? person;

  /// Receives the field's global rect so the picker anchors to it.
  final void Function(Rect anchorRect) onTap;

  /// i18n key for the empty state ("choose a lead…").
  final String placeholderKey;

  /// Whether [person] is the signed-in user, which earns a "(You)" suffix.
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final picked = person;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      onTap: () {
        final box = context.findRenderObject() as RenderBox?;
        final rect = (box != null && box.hasSize)
            ? box.localToGlobal(Offset.zero) & box.size
            : Rect.zero;
        onTap(rect);
      },
      child: Container(
        // Nine points of vertical padding around a 26-point face is the same
        // 44-point row the text fields beside it stand in, so a row of fields
        // stays a row.
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            if (picked != null) ...[
              HiveAvatar(
                name: picked.displayName.isEmpty
                    ? picked.username
                    : picked.displayName,
                imageUrl: picked.avatarUrl,
                pronouns: picked.pronouns,
                size: 26,
              ),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: Text(
                picked == null
                    ? context.t(placeholderKey)
                    : _nameOf(context, picked, isMe),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: picked == null
                      ? FontWeight.w400
                      : FontWeight.w600,
                  color: picked == null
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              LucideIcons.chevronsUpDown,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

String _nameOf(BuildContext context, DirectoryUser user, bool isMe) {
  final name = user.displayName.isEmpty ? user.username : user.displayName;
  return isMe ? '$name (${context.t('projects.you')})' : name;
}

/// Picker body: search field over a paged directory, one row per person.
///
/// Pages [UserRepository.searchUsers] rather than draining `/users`: a picker
/// that downloads every account in the org to fill a list is a list that stops
/// working exactly when the org is big enough to need a search.
class _PersonPickerPanel extends StatefulWidget {
  const _PersonPickerPanel({required this.selectedId, required this.meId});

  final String? selectedId;
  final String? meId;

  @override
  State<_PersonPickerPanel> createState() => _PersonPickerPanelState();
}

class _PersonPickerPanelState extends State<_PersonPickerPanel> {
  static const _debounceDelay = Duration(milliseconds: 180);
  static const _pageSize = 25;

  final _searchCtrl = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<DirectoryUser> _results = [];

  /// Ids already in [_results] — somebody can shift across a page boundary
  /// while paging, and the same face twice reads as a bug.
  final Set<String> _seen = {};

  String _query = '';
  int _page = 0;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;

  /// Set once the server hands back a short page, so a total that never quite
  /// matches what is on screen cannot keep asking for a page that is not there.
  bool _exhausted = false;
  String? _error;

  /// Monotonic request token: a debounced search that lands after a newer one
  /// started is dropped, so a slow response can never overwrite fresh results.
  int _reqSeq = 0;

  bool get _hasMore => !_exhausted && _results.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // The search pill draws its own focus ring, so it has to repaint on focus.
    _focus.addListener(_onFocusChanged);
    _focus.requestFocus();
    _runSearch(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => _runSearch(reset: true));
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 100) {
      _runSearch(reset: false);
    }
  }

  Future<void> _runSearch({required bool reset}) async {
    if (reset) {
      _debounce?.cancel();
    } else if (_loadingMore || _loading || !_hasMore) {
      return;
    }

    final seq = ++_reqSeq;
    final page = reset ? 0 : _page + 1;
    final query = _query.trim();

    setState(() {
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });

    try {
      final result = await context.read<UserRepository>().searchUsers(
        query,
        page: page,
        size: _pageSize,
      );
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        if (reset) {
          _results.clear();
          _seen.clear();
        }
        for (final user in result.items) {
          if (_seen.add(user.id)) _results.add(user);
        }
        _page = page;
        _total = result.total;
        _exhausted = result.items.length < _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _searchField(),
      Flexible(child: _list()),
    ],
  );

  /// Search row drawn as an inset glass pill rather than a `TextField` with the
  /// app's input decoration: that theme fills opaquely, which on the glass panel
  /// reads as a separate bar stuck on top instead of part of the surface.
  Widget _searchField() {
    final focused = _focus.hasFocus;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: focused ? 0.4 : 0.26),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(
            color: focused ? AppColors.accent : AppColors.hairline2,
            width: focused ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.search,
              size: 16,
              color: focused ? AppColors.accentStrong : AppColors.textSecondary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                focusNode: _focus,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 13.5),
                cursorColor: AppColors.accentStrong,
                // Every border state is cleared by hand: the app's input theme
                // supplies `enabledBorder`/`focusedBorder`, and those survive
                // `isCollapsed` — that is what drew a second box in the pill.
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  hintText: context.t('issues.searchPeople'),
                  hintStyle: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (_query.isNotEmpty)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  _searchCtrl.clear();
                  _onQueryChanged('');
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    LucideIcons.x,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    if (_loading && _results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Center(child: HiveLoader(size: 18)),
      );
    }
    if (_error != null && _results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Text(
          context.t(_error!),
          style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
        ),
      );
    }

    final rows = <Widget>[
      for (final user in _results)
        _PersonRow(
          user: user,
          selected: user.id == widget.selectedId,
          isMe: user.id == widget.meId,
          onTap: () => Navigator.of(context).pop(user),
        ),
      if (_results.isEmpty && !_loadingMore)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Text(
            context.t('issues.noPeopleFound'),
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
      if (_loadingMore)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Center(child: HiveLoader(size: 15)),
        ),
    ];

    return ListView.builder(
      controller: _scroll,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      itemBuilder: (_, index) => rows[index],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.user,
    required this.selected,
    required this.isMe,
    required this.onTap,
  });

  final DirectoryUser user;
  final bool selected;
  final bool isMe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.isEmpty ? user.username : user.displayName;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.circleCheck : LucideIcons.circle,
              size: 18,
              color: selected
                  ? AppColors.accentStrong
                  : AppColors.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 10),
            HiveAvatar(
              name: name,
              imageUrl: user.avatarUrl,
              pronouns: user.pronouns,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _nameOf(context, user, isMe),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if ((user.title ?? '').isNotEmpty)
                    Text(
                      user.title!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
