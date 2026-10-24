import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/account_repository.dart';
import 'package:hinata/core/repositories/moderation_repository.dart';

import '../../support/fixed_app_config.dart';

export '../../support/fixed_app_config.dart';

/// A phone at 390 points; the text size is [moderationApp]'s.
void onPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// [child] in an app with the blocs and the repositories the moderation
/// screens read, at text scale [textScale].
Widget moderationApp({
  required Widget child,
  required AccountRepository account,
  ModerationRepository? moderationRepository,
  AuthBloc? auth,
  ModerationMeta moderation = const ModerationMeta(version: 1),
  String? organizationName = 'Werkhaus',
  double textScale = 2.0,
}) => MultiRepositoryProvider(
  providers: [
    RepositoryProvider<AccountRepository>.value(value: account),
    if (moderationRepository != null)
      RepositoryProvider<ModerationRepository>.value(
        value: moderationRepository,
      ),
  ],
  child: MultiBlocProvider(
    providers: [
      BlocProvider<AppConfigBloc>.value(
        value: FixedAppConfig(
          moderation: moderation,
          organizationName: organizationName,
        ),
      ),
      BlocProvider<AuthBloc>.value(value: auth ?? RecordingAuth()),
    ],
    child: MaterialApp(
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: child,
    ),
  ),
);
