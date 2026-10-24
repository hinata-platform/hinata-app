import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_type.dart';

/// The counter under a field with a limit, for its `buildCounter`: 118 von
/// 2000.
Widget charCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) => Text(
  context.t(
    'common.charCount',
    variables: {'count': '$currentLength', 'max': '${maxLength ?? ''}'},
  ),
  style: TextStyle(fontSize: AppType.caption, color: AppColors.inkSoft),
);
