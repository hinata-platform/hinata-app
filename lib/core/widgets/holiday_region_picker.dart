import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../blocs/fetch_cubit.dart';
import '../i18n/i18n.dart';
import '../models/availability_models.dart';
import '../repositories/availability_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_type.dart';
import 'hive_loader.dart';
import '../../features/sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet;

/// A choice that is not a region, offered above the countries: "automatic",
/// "none".
typedef HolidayRegionOption = ({String value, String label});

/// The field for the region a holiday calendar follows: shows the chosen
/// country or Bundesland and opens a searchable list of all of them.
///
/// [value] is a code (`DE`, `DE-BY`), the value of one of [options], or null
/// for nothing chosen yet.
class HolidayRegionField extends StatelessWidget {
  const HolidayRegionField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.options = const [],
    this.helper,
    this.decoration,
  });

  final String label;
  final String? value;
  final ValueChanged<String> onChanged;
  final List<HolidayRegionOption> options;
  final String? helper;

  /// The surrounding form's field look; [label] and [helper] are set on it.
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    // Read here: a provider's create may not depend on an inherited widget.
    final language = Localizations.localeOf(context).languageCode;
    return BlocProvider(
      create: (context) {
        final repository = context.read<AvailabilityRepository>();
        return FetchCubit<List<HolidayRegion>>(
          () => repository.regions(language),
        )..load();
      },
      child: _RegionField(
        label: label,
        value: value,
        onChanged: onChanged,
        options: options,
        helper: helper,
        decoration: decoration,
      ),
    );
  }
}

class _RegionField extends StatelessWidget {
  const _RegionField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.options,
    required this.helper,
    required this.decoration,
  });

  final String label;
  final String? value;
  final ValueChanged<String> onChanged;
  final List<HolidayRegionOption> options;
  final String? helper;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FetchCubit<List<HolidayRegion>>>().state;
    final regions = state.data ?? const <HolidayRegion>[];
    final shown = _labelOf(value, regions, options);
    return Semantics(
      button: true,
      label: label,
      value: shown,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        onTap: state.hasData
            ? () async {
                final box = context.findRenderObject() as RenderBox?;
                final rect = (box != null && box.hasSize)
                    ? box.localToGlobal(Offset.zero) & box.size
                    : Rect.zero;
                final picked = await _showRegionPicker(
                  context,
                  anchorRect: rect,
                  regions: regions,
                  options: options,
                  selected: value,
                  title: label,
                );
                if (picked != null) onChanged(picked);
              }
            : state.errorKey != null
            ? () => context.read<FetchCubit<List<HolidayRegion>>>().load()
            : null,
        child: InputDecorator(
          decoration: (decoration ?? const InputDecoration()).copyWith(
            labelText: label,
            helperText: helper,
            helperMaxLines: 3,
          ),
          child: Row(
            children: [
              Expanded(
                child: state.isLoading && !state.hasData
                    ? const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: HiveLoader(size: 16),
                        ),
                      )
                    : Text(
                        state.errorKey != null && !state.hasData
                            ? context.t(state.errorKey!)
                            : shown ??
                                  context.t(
                                    'availability.admin.rulesPlaceholder',
                                  ),
                        style: TextStyle(
                          fontSize: AppType.body,
                          color: shown == null
                              ? AppColors.textSecondary
                              : AppColors.ink,
                        ),
                      ),
              ),
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

/// "Bayern, Deutschland" for `DE-BY`, an option's label, or null.
String? _labelOf(
  String? value,
  List<HolidayRegion> regions,
  List<HolidayRegionOption> options,
) {
  if (value == null) return null;
  for (final option in options) {
    if (option.value == value) return option.label;
  }
  for (final country in regions) {
    if (country.code == value) return country.name;
    for (final region in country.subdivisions) {
      if (region.code == value) return '${region.name}, ${country.name}';
    }
  }
  return value;
}

Future<String?> _showRegionPicker(
  BuildContext context, {
  required Rect anchorRect,
  required List<HolidayRegion> regions,
  required List<HolidayRegionOption> options,
  required String? selected,
  required String title,
}) {
  Widget panel(bool sheet) => _RegionPanel(
    regions: regions,
    options: options,
    selected: selected,
    title: sheet ? title : null,
  );
  if (MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint) {
    return showGlassAnchoredPopover<String>(
      context,
      anchorRect: anchorRect,
      width: 380,
      minHeight: 240,
      maxHeight: 460,
      builder: (_) => panel(false),
    );
  }
  return showGlassBottomSheet<String>(
    context,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
      ),
      child: panel(true),
    ),
  );
}

/// One row of the list: an option, a country, or a region indented under it.
typedef _Row = ({String value, String label, bool nested, bool strong});

class _RegionPanel extends StatefulWidget {
  const _RegionPanel({
    required this.regions,
    required this.options,
    required this.selected,
    required this.title,
  });

  final List<HolidayRegion> regions;
  final List<HolidayRegionOption> options;
  final String? selected;
  final String? title;

  @override
  State<_RegionPanel> createState() => _RegionPanelState();
}

/// A country with its names in lower case, read once per picker.
typedef _Entry = ({
  HolidayRegion country,
  String name,
  List<({HolidayRegion region, String name})> regions,
});

class _RegionPanelState extends State<_RegionPanel> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  String _query = '';

  /// Every name in lower case, once, rather than on every keystroke.
  late final List<_Entry> _entries = [
    for (final country in widget.regions)
      (
        country: country,
        name: country.name.toLowerCase(),
        regions: [
          for (final region in country.subdivisions)
            (region: region, name: region.name.toLowerCase()),
        ],
      ),
  ];

  /// The rows of the last search, kept until the search changes.
  late List<_Row> _rows = _rowsFor('');

  @override
  void dispose() {
    _focus.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String value) {
    if (value == _query) return;
    setState(() {
      _query = value;
      _rows = _rowsFor(value);
    });
  }

  /// Options first, then the countries with their regions. Without a search
  /// the chosen country leads; a search keeps a country whose name or code
  /// matches with all its regions, and a matching region under its country,
  /// those whose names start with the search first.
  List<_Row> _rowsFor(String raw) {
    final query = raw.trim().toLowerCase();
    final selected = widget.selected;
    final ranked = <List<_Entry>>[[], [], []];
    final kept = <_Entry>[];
    for (final entry in _entries) {
      final code = entry.country.code.toLowerCase();
      if (query.isEmpty) {
        final chosen =
            selected != null &&
            (entry.country.code == selected ||
                selected.startsWith('${entry.country.code}-'));
        ranked[chosen ? 0 : 1].add(entry);
        continue;
      }
      final whole = entry.name.contains(query) || code == query;
      final regions = whole
          ? entry.regions
          : entry.regions.where((r) => r.name.contains(query)).toList();
      if (!whole && regions.isEmpty) continue;
      final rank = entry.name.startsWith(query) || code == query
          ? 0
          : regions.any((r) => r.name.startsWith(query))
          ? 1
          : 2;
      ranked[rank].add((
        country: entry.country,
        name: entry.name,
        regions: regions,
      ));
    }
    for (final group in ranked) {
      kept.addAll(group);
    }
    return [
      if (query.isEmpty)
        for (final option in widget.options)
          (
            value: option.value,
            label: option.label,
            nested: false,
            strong: false,
          ),
      for (final entry in kept) ...[
        (
          value: entry.country.code,
          label: entry.country.name,
          nested: false,
          strong: true,
        ),
        for (final region in entry.regions)
          (
            value: region.region.code,
            label: region.region.name,
            nested: true,
            strong: false,
          ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
            child: Text(
              widget.title!,
              style: const TextStyle(
                fontSize: AppType.body,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        _searchField(context),
        Flexible(
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    context.t('availability.admin.rulesNoMatch'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppType.label,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : ListView.builder(
                  // A short result sizes the panel; the whole list fills it.
                  shrinkWrap: rows.length < 12,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return _RegionRow(
                      row: row,
                      selected: row.value == widget.selected,
                      onTap: () => Navigator.of(context).pop(row.value),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _searchField(BuildContext context) {
    final hint = context.t('availability.admin.rulesSearch');
    // Only the pill's ring follows the focus; the list does not rebuild.
    return ListenableBuilder(
      listenable: _focus,
      builder: (context, field) => _searchPill(_focus.hasFocus, field!),
      child: Semantics(
        label: hint,
        textField: true,
        child: TextField(
          controller: _search,
          focusNode: _focus,
          // A phone's keyboard would cover half the list before anybody
          // typed.
          autofocus: widget.title == null,
          onChanged: _onQuery,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: AppType.label),
          cursorColor: AppColors.accentStrong,
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
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: AppType.label,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchPill(bool focused, Widget field) {
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
            Expanded(child: field),
          ],
        ),
      ),
    );
  }
}

class _RegionRow extends StatelessWidget {
  const _RegionRow({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final _Row row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              row.nested ? 38 : 14,
              9,
              14,
              9,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.label,
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: selected || row.strong
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: row.nested
                          ? AppColors.inkSoft
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (selected)
                  Icon(LucideIcons.check, size: 16, color: AppColors.accentInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
