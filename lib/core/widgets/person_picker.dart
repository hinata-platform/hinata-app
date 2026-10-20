import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../blocs/person_picker_cubit.dart';
import '../i18n/i18n.dart';
import '../models/core_models.dart';
import '../repositories/user_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/glass_field.dart';
import 'hive_loader.dart';
import 'hive_widgets.dart' show HiveAvatar, hiveEase;
import 'person_search_pager.dart';
import '../../features/sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet;
import '../theme/app_type.dart';

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
/// nothing more than a label — the row is picked like any other. [search]
/// narrows the people to a list of the caller's choosing; the directory
/// otherwise. Resolves to the chosen person, or null when dismissed.
///
/// [first] puts one person at the top of the list under a label of its own —
/// "Mich eintragen" when a planner puts people on a shift — while the search
/// is empty. [disabledIds] are listed greyed out and cannot be picked, with
/// [disabledLabel] beside them (people already on that shift).
Future<DirectoryUser?> showPersonPicker(
  BuildContext context, {
  required Rect anchorRect,
  String? selectedId,
  String? meId,
  PersonSearch? search,
  ({DirectoryUser user, String label})? first,
  Set<String> disabledIds = const {},
  String? disabledLabel,
}) {
  // The popover is a root-navigator route and so inherits none of the caller's
  // providers — hand the repository across explicitly, to the picker's cubit.
  final repo = search == null ? context.read<UserRepository>() : null;
  Widget panel(bool sheet) => BlocProvider<PersonPickerCubit>(
    create: (_) => PersonPickerCubit(repo, source: search),
    child: _PersonPickerPanel(
      selectedId: selectedId,
      meId: meId,
      first: first,
      disabledIds: disabledIds,
      disabledLabel: disabledLabel,
    ),
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
    // Opens the picker; the chosen name or the placeholder merges in.
    return Semantics(
      button: true,
      child: InkWell(
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
          decoration: GlassFieldStyle.decoration,
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
                  style: picked == null
                      ? GlassFieldStyle.placeholder
                      : GlassFieldStyle.value,
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
/// Pages [PersonPickerCubit.search] rather than draining `/users`: a picker
/// that downloads every account in the org to fill a list is a list that stops
/// working exactly when the org is big enough to need a search.
class _PersonPickerPanel extends StatefulWidget {
  const _PersonPickerPanel({
    required this.selectedId,
    required this.meId,
    this.first,
    this.disabledIds = const {},
    this.disabledLabel,
  });

  final String? selectedId;
  final String? meId;
  final ({DirectoryUser user, String label})? first;
  final Set<String> disabledIds;
  final String? disabledLabel;

  @override
  State<_PersonPickerPanel> createState() => _PersonPickerPanelState();
}

class _PersonPickerPanelState extends State<_PersonPickerPanel> {
  final _searchCtrl = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  late final PersonSearchPager _pager = PersonSearchPager(
    (query, {required page, required size}) =>
        context.read<PersonPickerCubit>().search(query, page: page, size: size),
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // The search pill draws its own focus ring, so it has to repaint on focus.
    _focus.addListener(_onFocusChanged);
    _focus.requestFocus();
    _pager.addListener(_onPage);
    _pager.refresh();
  }

  @override
  void dispose() {
    _pager
      ..removeListener(_onPage)
      ..dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onPage() {
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onQueryChanged(String value) {
    setState(() {});
    _pager.setQuery(value);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 100) {
      _pager.loadMore();
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
              color: focused ? AppColors.accentInk : AppColors.textSecondary,
            ),
            const SizedBox(width: 9),
            Expanded(
              // The hint is the only name the field shows, and a hint is not a label.
              child: Semantics(
                label: context.t('issues.searchPeople'),
                textField: true,
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _focus,
                  onChanged: _onQueryChanged,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: AppType.label),
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
                      fontSize: AppType.label,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            if (_searchCtrl.text.isNotEmpty)
              // Named for screen readers; the padding gives a 32-point target around
              // the same 14-point glyph.
              Semantics(
                button: true,
                label: context.t('common.clear'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    _searchCtrl.clear();
                    _onQueryChanged('');
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: Icon(
                      LucideIcons.x,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    final results = _pager.results;
    final error = _pager.error;
    if (_pager.loading && results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Center(child: HiveLoader(size: 18)),
      );
    }
    if (error != null && results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Text(
          context.t(error),
          style: TextStyle(fontSize: AppType.label, color: AppColors.dangerInk),
        ),
      );
    }

    final first = _searchCtrl.text.isEmpty ? widget.first : null;
    Widget row(DirectoryUser user, {String? label}) {
      final disabled = widget.disabledIds.contains(user.id);
      return _PersonRow(
        user: user,
        selected: user.id == widget.selectedId,
        isMe: user.id == widget.meId,
        label: label,
        disabledLabel: disabled ? widget.disabledLabel : null,
        onTap: disabled ? null : () => Navigator.of(context).pop(user),
      );
    }

    final rows = <Widget>[
      if (first != null) row(first.user, label: first.label),
      for (final user in results)
        if (user.id != first?.user.id) row(user),
      if (results.isEmpty && !_pager.loadingMore)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Text(
            context.t('issues.noPeopleFound'),
            style: TextStyle(
              fontSize: AppType.label,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      if (_pager.loadingMore)
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
    this.label,
    this.disabledLabel,
  });

  final DirectoryUser user;
  final bool selected;
  final bool isMe;

  /// Null for a row that cannot be picked.
  final VoidCallback? onTap;

  /// Written instead of the name: the pinned first row's own words.
  final String? label;

  /// Why the row cannot be picked, beside the name.
  final String? disabledLabel;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.isEmpty ? user.username : user.displayName;
    // A choice that says whether it is picked; the name merges in.
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                  selected ? LucideIcons.circleCheck : LucideIcons.circle,
                  size: 18,
                  color: selected
                      ? AppColors.accentInk
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
                        label ?? _nameOf(context, user, isMe),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.label,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (disabledLabel != null ||
                          (user.title ?? '').isNotEmpty)
                        Text(
                          disabledLabel ?? user.title!,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.caption,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
