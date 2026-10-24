import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/blocs/app_config_bloc.dart';
import '../../../core/blocs/auth_bloc.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/repositories/moderation_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/char_counter.dart';
import '../../../core/widgets/quiet_info_line.dart';
import '../../account/account_widgets.dart' show AccountNote, AccountNoteTone;
import '../../blocks/hidden_content_cubit.dart';
import '../../sprint/modals/glass_modal.dart';
import 'report_cubit.dart';
import 'report_reasons.dart';

/// What is reported, as the sheet names it (HIN-173).
class ReportSubject {
  const ReportSubject({
    required this.target,
    required this.title,
    required this.subtitle,
    this.authorId,
    this.authorName,
  });

  final TargetRef target;

  /// "Kommentar melden", "Seite melden", and so on.
  final String title;

  /// Who wrote it and where it is, such as "Von Jonas Becker in MESSE-14".
  final String subtitle;

  /// The person behind it, for blocking them with the report and for the
  /// sentence that they do not learn who reported.
  final String? authorId;
  final String? authorName;

  /// Blocking goes with a report of a comment or of a person, nothing else.
  bool get canAlsoBlock =>
      authorId != null &&
      (target.kind == ContentKind.comment || target.kind == ContentKind.person);

  /// Something without a menu of its own: the reader says where it is.
  bool get asksWhere => target.kind == ContentKind.other;
}

/// Whether the server knows reporting and blocking (HIN-26) and somebody is
/// signed in to do either.
bool moderationReachable(BuildContext context) =>
    context.read<AuthBloc?>()?.state.user != null &&
    (context.read<AppConfigBloc?>()?.state.meta?.supportsModeration ?? false);

/// Whether the reader may report what [authorId] made (HIN-173): somebody
/// else's, still there ([removed] is whether moderation took it), on a server
/// that knows reporting.
bool canReport(
  BuildContext context, {
  required String? authorId,
  bool removed = false,
}) =>
    moderationReachable(context) &&
    !removed &&
    authorId != context.read<AuthBloc?>()?.state.user?.id;

/// "Report something else …" from Settings › Help and contact (HIN-175): for
/// what has no menu of its own, a project's name, a board, a team. First the
/// reason, then where it is and what moderation should know.
Future<bool> showReportElsewhereSheet(BuildContext context) => showReportSheet(
  context,
  subject: ReportSubject(
    target: TargetRef.elsewhere,
    title: context.t('moderation.report.elsewhereTitle'),
    subtitle: context.t('moderation.report.elsewhereSubtitle'),
  ),
);

/// The width of the popover beside a menu.
const double _popoverWidth = 400;

/// The longest place the reader can name, as the server takes it.
const int _locationMax = 300;

/// Reports [subject] (HIN-173): beside the menu item it came from on a wide
/// window ([anchorRect]), as a sheet on a phone, never a sheet on a sheet.
/// Thanks the reader when it went out, folds a reported comment for them and,
/// with the report, the posts of a person they blocked. True once sent.
Future<bool> showReportSheet(
  BuildContext context, {
  required ReportSubject subject,
  Rect? anchorRect,
}) async {
  final moderation = context.read<ModerationRepository>();
  final hidden = context.read<HiddenContentCubit?>();
  final thanks = context.t('moderation.report.thanks');
  Widget body(BuildContext _) => BlocProvider(
    create: (_) => ReportCubit(moderation, subject.target),
    child: ReportSheet(subject: subject),
  );
  // View.of, not MediaQuery: this runs from a tap, not from a build.
  final view = View.of(context);
  final wide =
      view.physicalSize.width / view.devicePixelRatio >=
      kGlassPopoverBreakpoint;
  final anchor = anchorRect;
  // Never a sheet on a sheet: from inside one, such as an issue on a phone,
  // the report is a card over it.
  final inSheet = insideGlassSheet(context);
  final outcome = wide && anchor != null
      ? await showGlassAnchoredPopover<ReportOutcome>(
          context,
          anchorRect: anchor,
          width: _popoverWidth,
          maxHeight: 680,
          builder: body,
        )
      : await showGlassModal<ReportOutcome>(
          context,
          width: 460,
          adaptive: !inSheet,
          builder: body,
        );
  if (outcome == null) return false;
  if (subject.target.kind == ContentKind.comment) {
    hidden?.noteReported(subject.target.id);
  }
  final author = subject.authorId;
  if (outcome.alsoBlocked && author != null) hidden?.noteBlocked(author);
  if (context.mounted) {
    showGlassToast(context, thanks, kind: GlassToastKind.success);
  }
  return true;
}

/// What came of a sent report.
class ReportOutcome {
  const ReportOutcome({required this.alsoBlocked});

  final bool alsoBlocked;
}

/// The two steps of a report; dumb, it renders [ReportCubit].
class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key, required this.subject});

  final ReportSubject subject;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  final _location = TextEditingController();
  final _explanation = TextEditingController();

  @override
  void dispose() {
    _location.dispose();
    _explanation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<ReportCubit, ReportState>(
    listenWhen: (before, now) => !before.sent && now.sent,
    listener: (context, state) =>
        Navigator.of(context).pop(ReportOutcome(alsoBlocked: state.alsoBlock)),
    builder: (context, state) {
      final cubit = context.read<ReportCubit>();
      final category = state.category;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            subject: widget.subject,
            onBack: category == null || state.sending ? null : cubit.back,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: category == null
                  ? _Reasons(previous: state.previous, onChoose: cubit.choose)
                  : _Details(
                      subject: widget.subject,
                      category: category,
                      state: state,
                      location: _location,
                      explanation: _explanation,
                      onChange: cubit.back,
                      onAlsoBlock: cubit.setAlsoBlock,
                    ),
            ),
          ),
          _Footer(
            details: category != null,
            busy: state.sending,
            onBack: cubit.back,
            onSend: () => unawaited(
              cubit.send(_explanation.text, location: _location.text),
            ),
          ),
        ],
      );
    },
  );
}

/// The icon and, on the second step, the way back in its place.
class _Header extends StatelessWidget {
  const _Header({required this.subject, required this.onBack});

  final ReportSubject subject;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (back == null)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                LucideIcons.flag,
                size: 20,
                color: AppColors.accentInk,
              ),
            )
          else
            IconButton(
              tooltip: context.t('common.back'),
              onPressed: back,
              icon: Icon(LucideIcons.arrowLeft, size: 20, color: AppColors.ink),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject.title,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontSize: AppType.heading,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subject.subtitle,
                  style: TextStyle(
                    fontSize: AppType.label,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The first step: why. A step change is announced, and coming back puts the
/// focus on the reason chosen before.
class _Reasons extends StatelessWidget {
  const _Reasons({required this.previous, required this.onChoose});

  final ReportCategory? previous;
  final ValueChanged<ReportCategory> onChoose;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
        child: Semantics(
          liveRegion: true,
          header: true,
          child: Text(
            context.t('moderation.report.whyTitle'),
            style: TextStyle(
              fontSize: AppType.body,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
      ),
      ReportReasons(onChoose: onChoose, focused: previous),
    ],
  );
}

/// The second step: the reason, where it is for something without a menu of
/// its own, what moderation should know, blocking with it, and what sending it
/// means.
class _Details extends StatelessWidget {
  const _Details({
    required this.subject,
    required this.category,
    required this.state,
    required this.location,
    required this.explanation,
    required this.onChange,
    required this.onAlsoBlock,
  });

  final ReportSubject subject;
  final ReportCategory category;
  final ReportState state;
  final TextEditingController location;
  final TextEditingController explanation;
  final VoidCallback onChange;
  final ValueChanged<bool> onAlsoBlock;

  @override
  Widget build(BuildContext context) {
    final required = category.needsExplanation;
    final name = subject.authorName;
    final retryAt = state.retryAt;
    final error = state.errorKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          container: true,
          child: ReportReasonRow(
            title: reportCategoryTitle(context, category),
            hint: context.t('moderation.report.change'),
            chosen: true,
            onTap: state.sending ? () {} : onChange,
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (subject.asksWhere) ...[
                GlassField(
                  wrapCaption: true,
                  label: context.t('moderation.report.location'),
                  child: TextField(
                    controller: location,
                    enabled: !state.sending,
                    maxLength: _locationMax,
                    buildCounter: charCounter,
                    textInputAction: TextInputAction.next,
                    decoration:
                        glassInputDecoration(
                          hint: context.t('moderation.report.locationHint'),
                        ).copyWith(
                          errorText: state.locationMissing
                              ? context.t('moderation.report.locationRequired')
                              : null,
                        ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              GlassField(
                wrapCaption: true,
                label: context.t(
                  required
                      ? 'moderation.report.explanationRequired'
                      : 'moderation.report.explanationOptional',
                ),
                child: TextField(
                  controller: explanation,
                  enabled: !state.sending,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: ReportCategory.explanationMax,
                  buildCounter: charCounter,
                  decoration: glassInputDecoration().copyWith(
                    errorText: state.explanationMissing
                        ? context.t(
                            'moderation.report.explanationTooShort',
                            variables: {
                              'min': '${ReportCategory.explanationMin}',
                            },
                          )
                        : null,
                  ),
                ),
              ),
              if (subject.canAlsoBlock && name != null) ...[
                const SizedBox(height: 10),
                GlassOptionRow(
                  title: context.t(
                    'moderation.report.alsoBlock',
                    variables: {'name': name},
                  ),
                  subtitle: context.t(
                    'moderation.report.alsoBlockHint',
                    variables: {'name': name},
                  ),
                  value: state.alsoBlock,
                  onChanged: state.sending ? null : onAlsoBlock,
                ),
              ],
              const SizedBox(height: 8),
              QuietInfoLine(
                icon: LucideIcons.lockKeyhole,
                text: name == null
                    ? context.t('moderation.report.whoSees')
                    : context.t(
                        'moderation.report.whoSeesNamed',
                        variables: {'name': name},
                      ),
              ),
              QuietInfoLine(
                icon: LucideIcons.scale,
                text: context.t('moderation.report.goodFaith'),
              ),
              if (retryAt != null || error != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: AccountNote(
                    text: retryAt != null
                        ? _retryText(context, retryAt)
                        : context.t(error!),
                    icon: LucideIcons.triangleAlert,
                    tone: AccountNoteTone.danger,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// When reporting works again, today or tomorrow.
  static String _retryText(BuildContext context, DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final time = TimeOfDay.fromDateTime(local).format(context);
    final today =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return context.t(
      today ? 'moderation.report.tooMany' : 'moderation.report.tooManyTomorrow',
      variables: {'time': time},
    );
  }
}

/// Cancel on the first step; back and send on the second.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.details,
    required this.busy,
    required this.onBack,
    required this.onSend,
  });

  final bool details;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Padding(
    padding:
        const EdgeInsets.fromLTRB(22, 8, 22, 18) +
        EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
    child: Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: details
          ? [
              TextButton(
                onPressed: busy ? null : onBack,
                child: Text(context.t('common.back')),
              ),
              FilledButton.icon(
                onPressed: busy ? null : onSend,
                icon: busy
                    ? SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.navy,
                        ),
                      )
                    : const Icon(LucideIcons.flag, size: 15),
                label: Text(context.t('moderation.report.send')),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(context.t('common.cancel')),
              ),
            ],
    ),
  );
}
