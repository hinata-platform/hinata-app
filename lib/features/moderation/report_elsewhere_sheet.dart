import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/moderation_models.dart';
import '../../core/repositories/account_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../sprint/modals/glass_modal.dart';
import 'report/report_reasons.dart';
import 'report_elsewhere_cubit.dart';

/// "Report something else …" from Settings › Help and contact (HIN-175): for
/// what has no menu of its own, a project's name, a board, a team. First the
/// reason, then where it is and what moderation should know.
Future<void> showReportElsewhereSheet(BuildContext context) async {
  final account = context.read<AccountRepository>();
  final sent = await showGlassModal<bool>(
    context,
    width: 520,
    builder: (_) => BlocProvider(
      create: (_) => ReportElsewhereCubit(account),
      child: const _ReportElsewhereBody(),
    ),
  );
  if (sent == true && context.mounted) {
    showGlassToast(
      context,
      context.t('moderation.report.thanks'),
      kind: GlassToastKind.success,
    );
  }
}

class _ReportElsewhereBody extends StatefulWidget {
  const _ReportElsewhereBody();

  @override
  State<_ReportElsewhereBody> createState() => _ReportElsewhereBodyState();
}

class _ReportElsewhereBodyState extends State<_ReportElsewhereBody> {
  static const _locationMax = 300;

  final _form = GlobalKey<FormState>();
  final _location = TextEditingController();
  final _explanation = TextEditingController();

  @override
  void dispose() {
    _location.dispose();
    _explanation.dispose();
    super.dispose();
  }

  void _send() {
    if (!(_form.currentState?.validate() ?? false)) return;
    unawaited(
      context.read<ReportElsewhereCubit>().send(
        location: _location.text,
        explanation: _explanation.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ReportElsewhereCubit, ReportElsewhereState>(
        listener: (context, state) {
          if (state.sent) {
            Navigator.of(context).pop(true);
          } else if (state.errorKey != null) {
            showGlassErrorToast(context, context.t(state.errorKey!));
          }
        },
        builder: (context, state) {
          final category = state.category;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassModalHeader(
                icon: LucideIcons.flag,
                title: context.t('moderation.report.elsewhereTitle'),
                subtitle: context.t(
                  category == null
                      ? 'moderation.report.whyTitle'
                      : 'moderation.report.elsewhereSubtitle',
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: category == null
                      ? ReportReasons(
                          onChoose: context.read<ReportElsewhereCubit>().choose,
                        )
                      : _Details(
                          form: _form,
                          category: category,
                          location: _location,
                          explanation: _explanation,
                          locationMax: _locationMax,
                          enabled: !state.sending,
                          onChange: context.read<ReportElsewhereCubit>().back,
                        ),
                ),
              ),
              if (category != null)
                GlassModalFooter(
                  confirmLabel: context.t('moderation.report.send'),
                  confirmIcon: LucideIcons.flag,
                  busy: state.sending,
                  onConfirm: state.sending ? null : _send,
                )
              else
                const SizedBox(height: 12),
            ],
          );
        },
      );
}

/// The second step: where it is, what moderation should know, and what
/// sending it means.
class _Details extends StatelessWidget {
  const _Details({
    required this.form,
    required this.category,
    required this.location,
    required this.explanation,
    required this.locationMax,
    required this.enabled,
    required this.onChange,
  });

  final GlobalKey<FormState> form;
  final ReportCategory category;
  final TextEditingController location;
  final TextEditingController explanation;
  final int locationMax;
  final bool enabled;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final required = category.needsExplanation;
    return Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReportReasonRow(
            title: reportCategoryTitle(context, category),
            hint: context.t('moderation.report.change'),
            chosen: true,
            onTap: onChange,
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassField(
                  wrapCaption: true,
                  label: context.t('moderation.report.location'),
                  child: TextFormField(
                    controller: location,
                    enabled: enabled,
                    maxLength: locationMax,
                    textInputAction: TextInputAction.next,
                    decoration: glassInputDecoration(
                      hint: context.t('moderation.report.locationHint'),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? context.t('moderation.report.locationRequired')
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                GlassField(
                  wrapCaption: true,
                  label: context.t(
                    required
                        ? 'moderation.report.explanationRequired'
                        : 'moderation.report.explanationOptional',
                  ),
                  child: TextFormField(
                    controller: explanation,
                    enabled: enabled,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: ReportCategory.explanationMax,
                    decoration: glassInputDecoration(),
                    validator: (value) =>
                        required &&
                            (value ?? '').trim().length <
                                ReportCategory.explanationMin
                        ? context.t(
                            'moderation.report.explanationTooShort',
                            variables: {
                              'min': '${ReportCategory.explanationMin}',
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                GlassInfoLine(
                  icon: LucideIcons.lockKeyhole,
                  child: Text(
                    context.t('moderation.report.whoSees'),
                    style: _infoStyle,
                  ),
                ),
                const SizedBox(height: 8),
                GlassInfoLine(
                  icon: LucideIcons.scale,
                  child: Text(
                    context.t('moderation.report.goodFaith'),
                    style: _infoStyle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle get _infoStyle =>
      TextStyle(fontSize: AppType.label, height: 1.4, color: AppColors.inkSoft);
}
