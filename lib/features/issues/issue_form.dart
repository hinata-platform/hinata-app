import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/hivora_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'issue_detail_sheet.dart';

/// Centered create-issue dialog for wider screens — mirrors the issue detail
/// sheet's modal chrome and width so the two-column create layout has room.
class _CreateDialogType extends WoltDialogType {
  const _CreateDialogType();

  @override
  BoxConstraints layoutModal(Size availableSize) {
    const pad = 48.0;
    final width =
        math.min(940.0, math.max(360.0, availableSize.width - pad * 2));
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      minHeight: 0,
      maxHeight: math.max(360, availableSize.height * 0.88),
    );
  }
}

/// Opens the *create* issue form with the same modern Wolt modal chrome as the
/// issue detail sheet: a bottom sheet on phones, a wide centered dialog on
/// desktop, a persistent top bar (title + close), and the same two-column
/// layout — title + Markdown description on the left, an editable details card
/// on the right — with a full-width save button at the bottom.
Future<Issue?> showIssueForm(BuildContext context,
    {String? projectId, String? initialState}) {
  final repository = context.read<HivoraRepository>();
  return WoltModalSheet.show<Issue?>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    modalTypeBuilder: (ctx) => MediaQuery.sizeOf(ctx).width >= 760
        ? const _CreateDialogType()
        : WoltModalType.bottomSheet(),
    pageListBuilder: (modalContext) => [
      WoltModalSheetPage(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        hasTopBarLayer: true,
        isTopBarLayerAlwaysVisible: true,
        topBarTitle: Text(
          context.t('issues.new'),
          style: const TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
        trailingNavBarWidget: IconButton(
          onPressed: () => Navigator.of(modalContext).maybePop(),
          icon: Icon(Icons.close_rounded, color: AppColors.inkSoft),
        ),
        child: RepositoryProvider.value(
          value: repository,
          child: IssueCreateBody(
            projectId: projectId,
            initialState: initialState,
            onCreated: (issue) => Navigator.of(modalContext).pop(issue),
          ),
        ),
      ),
    ],
  );
}
