import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';

/// The `{{user:<id>}}` tokens a comment draft mentions people with.
final RegExp _mentionToken = RegExp(r'\{\{user:([^}\s]+)\}\}');

/// The ids [text] mentions, in order, each once.
List<String> mentionedUserIds(String text) => [
  ...{for (final match in _mentionToken.allMatches(text)) match.group(1)!},
];

/// A note under the comment field when the draft mentions somebody who cannot
/// open the issue and would never hear of it (HIN-136), with a button that
/// shares the issue with them instead.
///
/// What is known comes from the detail ([known]: id to "can see"); anybody
/// else is asked once through [blockedAmong] and remembered. The note follows
/// the draft: it appears once the mention is in and goes when the mention is
/// deleted or the person has been added.
class MentionAccessHint extends StatefulWidget {
  const MentionAccessHint({
    super.key,
    required this.controller,
    required this.known,
    required this.blockedAmong,
    required this.nameOf,
    required this.onShare,
  });

  final TextEditingController controller;

  /// Whether each person the detail names can see the issue.
  final Map<String, bool> known;

  /// Which of the given ids cannot open the issue.
  final Future<Set<String>> Function(List<String> ids) blockedAmong;

  /// A display name for an id; empty when unknown.
  final String Function(String id) nameOf;

  /// Opens the share dialog for the person named.
  final Future<void> Function(String id, String name) onShare;

  @override
  State<MentionAccessHint> createState() => _MentionAccessHintState();
}

class _MentionAccessHintState extends State<MentionAccessHint> {
  static const _askDelay = Duration(milliseconds: 300);

  /// Answers learnt by asking, on top of [MentionAccessHint.known].
  final Map<String, bool> _asked = {};
  final Set<String> _pending = {};
  Timer? _ask;
  String? _blocked;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onDraftChanged);
    _onDraftChanged();
  }

  @override
  void didUpdateWidget(MentionAccessHint old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onDraftChanged);
      widget.controller.addListener(_onDraftChanged);
    }
    if (old.known != widget.known) _onDraftChanged();
  }

  @override
  void dispose() {
    _ask?.cancel();
    widget.controller.removeListener(_onDraftChanged);
    super.dispose();
  }

  bool? _canSee(String id) => widget.known[id] ?? _asked[id];

  void _onDraftChanged() {
    final ids = mentionedUserIds(widget.controller.text);
    String? blocked;
    final unknown = <String>[];
    for (final id in ids) {
      final canSee = _canSee(id);
      if (canSee == false) {
        blocked ??= id;
      } else if (canSee == null && !_pending.contains(id)) {
        unknown.add(id);
      }
    }
    if (blocked != _blocked) setState(() => _blocked = blocked);
    if (unknown.isNotEmpty) {
      _ask?.cancel();
      _ask = Timer(_askDelay, () => _resolve(unknown));
    }
  }

  Future<void> _resolve(List<String> ids) async {
    _pending.addAll(ids);
    try {
      final blocked = await widget.blockedAmong(ids);
      for (final id in ids) {
        _asked[id] = !blocked.contains(id);
      }
    } catch (_) {
      // Unanswered stays unknown: no note is better than a wrong one.
    } finally {
      _pending.removeAll(ids);
    }
    if (mounted) _onDraftChanged();
  }

  Future<void> _share(String id, String name) async {
    await widget.onShare(id, name);
    // Whatever the dialog did, ask again: shared means the note goes.
    _asked.remove(id);
    if (mounted) await _resolve([id]);
  }

  @override
  Widget build(BuildContext context) {
    final id = _blocked;
    final name = id == null ? '' : widget.nameOf(id);
    return Semantics(
      liveRegion: true,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.bottomCenter,
        child: id == null || name.isEmpty
            ? const SizedBox(width: double.infinity)
            : Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  border: Border.all(color: AppColors.hairline2),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.eyeOff,
                      size: 16,
                      color: AppColors.accentInk,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.t(
                          'issues.participants.mentionHint',
                          variables: {'name': name},
                        ),
                        style: TextStyle(
                          fontSize: AppType.label,
                          height: 1.3,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _share(id, name),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(context.t('issues.participants.share')),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
