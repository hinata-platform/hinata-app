import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/docs/docs_links.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../admin_form_helpers.dart';

enum TextTestStatus { idle, testing, done, failure }

/// "Test a text" in the text check card (HIN-176).
class TextTestState extends Equatable {
  const TextTestState({
    this.status = TextTestStatus.idle,
    this.result,
    this.errorKey,
  });

  final TextTestStatus status;
  final TextCheckResult? result;
  final String? errorKey;

  @override
  List<Object?> get props => [status, result, errorKey];
}

/// Asks the server what it would say about a text; nothing is stored.
class TextTestCubit extends Cubit<TextTestState> {
  TextTestCubit(this._admin) : super(const TextTestState());

  final AdminRepository _admin;

  Future<void> test(String text) async {
    if (text.trim().isEmpty) return;
    emit(const TextTestState(status: TextTestStatus.testing));
    try {
      emit(
        TextTestState(
          status: TextTestStatus.done,
          result: await _admin.testText(text),
        ),
      );
    } on ApiFailure catch (failure) {
      emit(
        TextTestState(
          status: TextTestStatus.failure,
          errorKey: failure.message,
        ),
      );
    } catch (_) {
      emit(
        const TextTestState(
          status: TextTestStatus.failure,
          errorKey: 'errors.unexpected',
        ),
      );
    }
  }
}

/// The text check card: what it refuses, whether it puts the unclear before
/// moderation, the own terms and exceptions, and a field to try a text. All
/// in the settings draft under `moderation.filter`, saved with the section.
class TextCheckCard extends StatefulWidget {
  const TextCheckCard({super.key, required this.moderation});

  /// The `moderation` block of the settings draft.
  final Map<String, dynamic> moderation;

  @override
  State<TextCheckCard> createState() => _TextCheckCardState();
}

class _TextCheckCardState extends State<TextCheckCard> {
  /// What the server takes at most, per list and per term.
  static const _termsMax = 500;
  static const _termLengthMax = 60;

  final _test = TextEditingController();

  /// The filter block as the server sent it; looking writes nothing.
  Map<String, dynamic> get _filter =>
      widget.moderation['filter'] as Map<String, dynamic>? ?? const {};

  void _put(String key, Object value) => setState(
    () =>
        ((widget.moderation['filter'] ??= <String, dynamic>{})
                as Map<String, dynamic>)[key] =
            value,
  );

  List<String> _terms(String key) {
    final terms = _filter[key];
    return [if (terms is List) ...terms.whereType<String>()];
  }

  void _add(String key, String term) {
    final value = term.trim();
    final terms = _terms(key);
    if (value.isEmpty ||
        value.length > _termLengthMax ||
        terms.length >= _termsMax ||
        terms.any((t) => t.toLowerCase() == value.toLowerCase())) {
      return;
    }
    _put(key, [...terms, value]);
  }

  void _remove(String key, String term) =>
      _put(key, [..._terms(key)]..remove(term));

  @override
  void dispose() {
    _test.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flags = _filter['flagEnabled'] == true;
    return AdminSectionCard(
      icon: LucideIcons.scanText,
      title: context.t('admin.textCheck.title'),
      subtitle: context.t('admin.textCheck.hint'),
      children: [
        AdminToggle(
          label: context.t('admin.textCheck.block'),
          subtitle: context.t('admin.textCheck.blockHint'),
          value: _filter['blockEnabled'] != false,
          onChanged: (value) => _put('blockEnabled', value),
        ),
        AdminToggle(
          label: context.t('admin.textCheck.flag'),
          subtitle: context.t('admin.textCheck.flagHint'),
          value: flags,
          onChanged: (value) => _put('flagEnabled', value),
        ),
        if (flags) ...[
          const SizedBox(height: 4),
          AdminNote(
            text: context.t('admin.textCheck.flagNote'),
            icon: LucideIcons.scale,
            tone: AdminNoteTone.warning,
          ),
          const DocsLink(slug: DocsPage.adminArea),
        ],
        const SizedBox(height: 12),
        _TermList(
          label: context.t('admin.textCheck.ownTerms'),
          hint: context.t('admin.textCheck.ownTermsHint'),
          terms: _terms('blockTerms'),
          onAdd: (term) => _add('blockTerms', term),
          onRemove: (term) => _remove('blockTerms', term),
        ),
        const SizedBox(height: 12),
        _TermList(
          label: context.t('admin.textCheck.exceptions'),
          hint: context.t('admin.textCheck.exceptionsHint'),
          terms: _terms('allowTerms'),
          onAdd: (term) => _add('allowTerms', term),
          onRemove: (term) => _remove('allowTerms', term),
        ),
        const SizedBox(height: 8),
        _Line(
          icon: LucideIcons.languages,
          text: context.t('admin.textCheck.languages'),
        ),
        const SizedBox(height: 14),
        _TextTest(controller: _test),
        const SizedBox(height: 12),
        Divider(color: AppColors.hairline, height: 1),
        const SizedBox(height: 12),
        _Line(
          icon: LucideIcons.imageOff,
          text: context.t('admin.textCheck.images'),
        ),
      ],
    );
  }
}

/// A list of terms as chips that remove themselves, and a field to add one.
class _TermList extends StatefulWidget {
  const _TermList({
    required this.label,
    required this.hint,
    required this.terms,
    required this.onAdd,
    required this.onRemove,
  });

  final String label;
  final String hint;
  final List<String> terms;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<_TermList> createState() => _TermListState();
}

class _TermListState extends State<_TermList> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onAdd(_field.text);
    _field.clear();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        widget.label,
        style: TextStyle(
          fontSize: AppType.label,
          fontWeight: FontWeight.w600,
          color: AppColors.inkSoft,
        ),
      ),
      const SizedBox(height: 8),
      if (widget.terms.isNotEmpty) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final term in widget.terms)
              _TermChip(term: term, onRemove: () => widget.onRemove(term)),
          ],
        ),
        const SizedBox(height: 8),
      ],
      TextField(
        controller: _field,
        maxLength: 60,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        style: TextStyle(fontSize: AppType.body, color: AppColors.ink),
        decoration:
            adminInputDecoration(
              context,
              label: context.t('admin.textCheck.addTerm'),
              helper: widget.hint,
            ).copyWith(
              counterText: '',
              suffixIcon: IconButton(
                tooltip: context.t('admin.textCheck.addTerm'),
                icon: const Icon(LucideIcons.plus, size: 18),
                onPressed: _submit,
              ),
            ),
      ),
    ],
  );
}

class _TermChip extends StatelessWidget {
  const _TermChip({required this.term, required this.onRemove});

  final String term;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.t('admin.textCheck.removeTerm', variables: {'term': term}),
    excludeSemantics: true,
    child: InkWell(
      onTap: onRemove,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.x, size: 14, color: AppColors.inkSoft),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                term,
                style: TextStyle(
                  fontSize: AppType.label,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The field to try a text, and what the server says about it.
class _TextTest extends StatelessWidget {
  const _TextTest({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<TextTestCubit, TextTestState>(
        builder: (context, state) {
          final testing = state.status == TextTestStatus.testing;
          void run() =>
              unawaited(context.read<TextTestCubit>().test(controller.text));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                maxLength: 10000,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => run(),
                style: TextStyle(fontSize: AppType.body, color: AppColors.ink),
                decoration: adminInputDecoration(
                  context,
                  label: context.t('admin.textCheck.test'),
                  helper: context.t('admin.textCheck.testHint'),
                ).copyWith(counterText: ''),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: testing ? null : run,
                  icon: const Icon(LucideIcons.scanText, size: 16),
                  label: Text(context.t('admin.textCheck.testButton')),
                ),
              ),
              if (state.result case final result?) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: _Line(
                    icon: switch (result.verdict) {
                      TextVerdict.allow => LucideIcons.circleCheck,
                      TextVerdict.flag => LucideIcons.flag,
                      TextVerdict.block => LucideIcons.shieldAlert,
                    },
                    text: _explain(context, result),
                  ),
                ),
              ],
              if (state.status == TextTestStatus.failure &&
                  state.errorKey != null) ...[
                const SizedBox(height: 8),
                _Line(
                  icon: LucideIcons.triangleAlert,
                  text: context.t(state.errorKey!),
                ),
              ],
            ],
          );
        },
      );

  /// The verdict in words, with the reason a found word did not count.
  static String _explain(BuildContext context, TextCheckResult result) {
    String quoted(Iterable<String> words) => words.join(', ');
    final parts = <String>[
      switch (result.verdict) {
        TextVerdict.allow => context.t('admin.textCheck.resultAllow'),
        TextVerdict.flag => context.t(
          'admin.textCheck.resultFlag',
          variables: {'terms': quoted(result.terms)},
        ),
        TextVerdict.block => context.t(
          'admin.textCheck.resultBlock',
          variables: {'terms': quoted(result.terms)},
        ),
      },
    ];
    if (result.verdict == TextVerdict.allow) {
      final found = result.found.map((find) => find.term).toSet();
      if (found.isNotEmpty) {
        parts.add(
          context.t(
            'admin.textCheck.resultFound',
            variables: {'terms': quoted(found)},
          ),
        );
      }
      if (result.exceptions.isNotEmpty) {
        parts.add(
          context.t(
            'admin.textCheck.resultException',
            variables: {'words': quoted(result.exceptions)},
          ),
        );
      }
    }
    return parts.join(' ');
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 16, color: AppColors.inkSoft),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontSize: AppType.label,
            height: 1.4,
            color: AppColors.inkSoft,
          ),
        ),
      ),
    ],
  );
}
