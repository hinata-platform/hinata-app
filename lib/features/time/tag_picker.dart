import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/time_policy_models.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hue_colors.dart';
import '../../core/widgets/hive_loader.dart';
import '../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet;

/// Picks the tags on an entry: an anchored glass popover on a wide window, a
/// glass sheet on a phone.
///
/// The catalogue is searched on the server as the reader types, never drained
/// into the client — an instance that has been running for two years has a
/// vocabulary, and a picker that loads all of it is a picker that stops working
/// on exactly the instances that grew one.
///
/// Whether a word that does not exist yet can be coined here is the operator's
/// decision (`limitTagAccess`), and the row that offers it is simply absent when
/// it is not theirs to make. Offering it and then answering 403 would teach
/// people to distrust the button rather than teach them the rule.
///
/// Resolves to the chosen tags, or null if dismissed. An empty list is a real
/// answer: clearing the field is something the reader can mean.
Future<List<String>?> showTimeTagPicker(
  BuildContext context, {
  Rect? anchorRect,
  required List<String> selected,
  required bool canCreate,
}) {
  final body = _TagPickerBody(selected: selected, canCreate: canCreate);
  final wide =
      anchorRect != null &&
      MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
  return wide
      ? showGlassAnchoredPopover<List<String>>(
          context,
          anchorRect: anchorRect,
          width: 340,
          minHeight: 300,
          maxHeight: 440,
          builder: (_) => body,
        )
      : showGlassBottomSheet<List<String>>(
          context,
          // A cap, not a height. The body is a min-size Column around a
          // shrink-wrapping list, so a fixed box left dead glass under the
          // buttons whenever the catalogue was shorter than the box -- which,
          // with a handful of words, is the normal case.
          builder: (_) => ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 440),
            child: body,
          ),
        );
}

class _TagPickerBody extends StatefulWidget {
  const _TagPickerBody({required this.selected, required this.canCreate});

  final List<String> selected;

  /// Whether this reader may add a word to the catalogue.
  final bool canCreate;

  @override
  State<_TagPickerBody> createState() => _TagPickerBodyState();
}

class _TagPickerBodyState extends State<_TagPickerBody> {
  final _controller = TextEditingController();
  Timer? _debounce;

  late final List<String> _picked = List.of(widget.selected);
  List<TimeTag> _tags = const [];
  bool _loading = true;
  bool _creating = false;

  /// Monotonic token: a slow search that resolves after a later one must not
  /// overwrite what the reader is already looking at.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // the "create" row depends on what is typed
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_search(value)),
    );
  }

  Future<void> _search(String query) async {
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final page = await context.read<TimeRepository>().tags(
        query: query.trim().isEmpty ? null : query.trim(),
        size: 30,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _tags = page.items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      // An empty list and no spinner: the picker stays usable, and confirming
      // what is already selected is the one action that never needs the server.
      setState(() {
        _tags = const [];
        _loading = false;
      });
    }
  }

  /// The typed word, when it is one and is not already in the list.
  String? get _newWord {
    if (!widget.canCreate) return null;
    final typed = _controller.text.trim();
    if (typed.isEmpty || typed.length > 40) return null;
    final exists = _tags.any(
      (tag) => tag.name.toLowerCase() == typed.toLowerCase(),
    );
    return exists ? null : typed;
  }

  Future<void> _create(String name) async {
    setState(() => _creating = true);
    try {
      final tag = await context.read<TimeRepository>().createTag(name);
      if (!mounted) return;
      setState(() {
        _creating = false;
        _tags = [tag, ..._tags];
        _picked.add(tag.name);
        _controller.clear();
      });
    } catch (_) {
      if (!mounted) return;
      // Somebody else coined the same word a moment ago, or the policy changed
      // under the sheet. Either way the list is what to trust, so it is re-read
      // rather than the failure narrated.
      setState(() => _creating = false);
      unawaited(_search(_controller.text));
    }
  }

  void _toggle(String name) {
    setState(() {
      // Case-insensitively, because the catalogue treats two spellings as one
      // word and the chip has to come off however it was typed.
      final existing = _picked.indexWhere(
        (tag) => tag.toLowerCase() == name.toLowerCase(),
      );
      if (existing >= 0) {
        _picked.removeAt(existing);
      } else {
        _picked.add(name);
      }
    });
  }

  bool _isPicked(String name) =>
      _picked.any((tag) => tag.toLowerCase() == name.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final newWord = _newWord;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 40,
            onChanged: _onChanged,
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: context.t('time.tags.search'),
              prefixIcon: const Icon(LucideIcons.tag, size: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
            ),
          ),
        ),
        Flexible(
          child: _loading && _tags.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: HiveLoader(size: 34),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 10),
                  children: [
                    if (newWord != null)
                      _TagRow(
                        name: context.t(
                          'time.tags.create',
                          variables: {'name': newWord},
                        ),
                        hue: 250,
                        selected: false,
                        busy: _creating,
                        icon: LucideIcons.plus,
                        onTap: _creating ? null : () => _create(newWord),
                      ),
                    for (final tag in _tags)
                      _TagRow(
                        name: tag.name,
                        hue: tag.hue,
                        selected: _isPicked(tag.name),
                        onTap: () => _toggle(tag.name),
                      ),
                    // Words already on the entry that the catalogue does not
                    // list — an entry written before the catalogue existed, or
                    // one narrowed away by the search. They stay visible so
                    // confirming cannot silently drop them.
                    for (final tag in _picked)
                      if (!_tags.any(
                        (known) =>
                            known.name.toLowerCase() == tag.toLowerCase(),
                      ))
                        _TagRow(
                          name: tag,
                          hue: 250,
                          selected: true,
                          onTap: () => _toggle(tag),
                        ),
                    if (!_loading && _tags.isEmpty && newWord == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 24,
                        ),
                        child: Text(
                          context.t(
                            widget.canCreate
                                ? 'search.noMatch'
                                : 'time.tags.noneCurated',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(const <String>[]),
                child: Text(context.t('common.clear')),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_picked),
                child: Text(context.t('common.apply')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.name,
    required this.hue,
    required this.selected,
    this.onTap,
    this.busy = false,
    this.icon,
  });

  final String name;
  final int hue;
  final bool selected;
  final VoidCallback? onTap;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (busy)
              const SizedBox(width: 16, height: 16, child: HiveLoader(size: 16))
            else
              Icon(icon ?? LucideIcons.tag, size: 16, color: hueColor(hue)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: AppColors.ink,
                ),
              ),
            ),
            if (selected)
              const Icon(LucideIcons.check, size: 16, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
