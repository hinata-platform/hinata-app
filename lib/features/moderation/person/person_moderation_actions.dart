import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/person_profile.dart';
import '../../people/person_profile_cubit.dart';
import '../../sprint/modals/glass_modal.dart';
import '../case/case_dialogs.dart';
import '../decision/decision_dialog.dart';
import 'own_case_dialog.dart';
import 'person_moderation_cubit.dart';

/// Suspends [profile]'s person from their profile (HIN-174): why, as a case
/// of moderation's own, then the decision on "Maßnahme · Konto sperren".
/// A decision left unsent leaves the case open in the list.
Future<void> suspendFromProfile(
  BuildContext context,
  PersonProfile profile,
) async {
  final moderation = context.read<PersonModerationCubit>();
  final person = context.read<PersonProfileCubit>();
  final own = await askOwnCase(context, profile.displayName);
  if (own == null || !context.mounted) return;
  final detail = await moderation.openCase(profile.id, own.category, own.facts);
  if (!context.mounted) return;
  if (detail == null) {
    _sayRefusal(context, moderation);
    return;
  }
  final notice = await showDecisionDialog(
    context,
    detail,
    suspendPerson: true,
    facts: own.facts,
  );
  if (!context.mounted) return;
  if (notice != null) {
    showGlassToast(context, context.t(notice), kind: GlassToastKind.success);
  }
  unawaited(person.load());
}

/// Lifts [profile]'s suspension from their profile, with a reason.
Future<void> liftFromProfile(
  BuildContext context,
  PersonProfile profile,
) async {
  final caseId = profile.suspension?.caseId;
  if (caseId == null) return;
  final moderation = context.read<PersonModerationCubit>();
  final person = context.read<PersonProfileCubit>();
  final note = await askCaseNote(
    context,
    icon: LucideIcons.userCheck,
    title: context.t('moderation.suspension.liftTitle'),
    subtitle: context.t('moderation.suspension.liftSubtitle'),
    label: context.t('moderation.case.why'),
    confirmLabel: context.t('moderation.suspension.liftConfirm'),
  );
  if (note == null || !context.mounted) return;
  final lifted = await moderation.lift(caseId, note);
  if (!context.mounted) return;
  if (!lifted) {
    _sayRefusal(context, moderation);
    return;
  }
  showGlassToast(
    context,
    context.t('moderation.suspension.lifted'),
    kind: GlassToastKind.success,
  );
  unawaited(person.load());
}

void _sayRefusal(BuildContext context, PersonModerationCubit moderation) {
  showGlassToast(
    context,
    context.t(moderation.state ?? 'errors.unexpected'),
    kind: GlassToastKind.error,
  );
  moderation.seen();
}
