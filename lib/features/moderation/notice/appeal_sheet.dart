import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../account/account_widgets.dart' show AccountNote, AccountNoteTone;
import '../../sprint/modals/glass_modal.dart';
import 'notice_cubit.dart';

/// The longest appeal the server takes.
const int appealMax = 2000;

/// Appeals the decision behind [cubit]'s notice (HIN-173): a field and send.
/// A refusal stays in the sheet with the text kept; the page shows the
/// appeal once it is in.
Future<void> showAppealSheet(BuildContext context, NoticeCubit cubit) async {
  final done = context.t('moderation.appeal.sent');
  final sent = await showGlassModal<bool>(
    context,
    width: 520,
    builder: (_) =>
        BlocProvider.value(value: cubit, child: const AppealSheet()),
  );
  if (sent == true && context.mounted) {
    showGlassToast(context, done, kind: GlassToastKind.success);
  }
}

class AppealSheet extends StatefulWidget {
  const AppealSheet({super.key});

  @override
  State<AppealSheet> createState() => _AppealSheetState();
}

class _AppealSheetState extends State<AppealSheet> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final sent = await context.read<NoticeCubit>().appeal(_text.text);
    if (sent && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NoticeCubit>().state;
    final error = state.appealErrorKey;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassModalHeader(
          icon: LucideIcons.rotateCcw,
          title: context.t('moderation.appeal.title'),
          subtitle: context.t('moderation.appeal.subtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassField(
                  wrapCaption: true,
                  label: context.t('moderation.appeal.label'),
                  child: TextField(
                    controller: _text,
                    enabled: !state.appealing,
                    autofocus: true,
                    minLines: 4,
                    maxLines: 10,
                    maxLength: appealMax,
                    buildCounter:
                        (
                          context, {
                          required currentLength,
                          required isFocused,
                          required maxLength,
                        }) => Text(
                          context.t(
                            'moderation.report.counter',
                            variables: {
                              'count': '$currentLength',
                              'max': '$maxLength',
                            },
                          ),
                          style: TextStyle(
                            fontSize: AppType.caption,
                            color: AppColors.inkSoft,
                          ),
                        ),
                    decoration: glassInputDecoration(
                      hint: context.t('moderation.appeal.hint'),
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: AccountNote(
                      text: context.t(error),
                      icon: LucideIcons.triangleAlert,
                      tone: AccountNoteTone.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('moderation.appeal.send'),
          confirmIcon: LucideIcons.send,
          busy: state.appealing,
          onConfirm: _text.text.trim().isEmpty
              ? null
              : () => unawaited(_send()),
        ),
      ],
    );
  }
}
