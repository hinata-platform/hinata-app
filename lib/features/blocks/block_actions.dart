import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassErrorToast, showGlassToast;
import 'block_confirm_dialog.dart';
import 'hidden_content_cubit.dart';

/// Asks first, then blocks [personId] and says so (HIN-168).
///
/// Pass a [context] that outlives the thing blocked from: a comment folds the
/// moment the block lands, and the toast needs somewhere to appear.
Future<void> confirmBlock(
  BuildContext context, {
  required String personId,
  required String name,
}) async {
  final hidden = context.read<HiddenContentCubit>();
  final done = context.t('blocks.blockedToast', variables: {'name': name});
  final blocked = await showBlockConfirm(
    context,
    name: name,
    onConfirm: () => hidden.block(personId),
  );
  if (blocked == true && context.mounted) {
    showGlassToast(context, done, kind: GlassToastKind.success);
  }
}

/// Lifts the block on [personId] without asking: nothing is lost by it, and
/// blocking again is one tap away. Answers whether it was lifted.
Future<bool> liftBlock(
  BuildContext context, {
  required String personId,
  required String name,
}) async {
  final hidden = context.read<HiddenContentCubit>();
  final done = context.t('blocks.unblockedToast', variables: {'name': name});
  try {
    await hidden.unblock(personId);
    if (context.mounted) {
      showGlassToast(context, done, kind: GlassToastKind.success);
    }
    return true;
  } on ApiFailure catch (failure) {
    if (context.mounted) {
      showGlassErrorToast(context, context.t(failure.message));
    }
    return false;
  }
}
