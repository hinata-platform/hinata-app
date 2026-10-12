import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/time_privacy_cubit.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/time/time_privacy_sheet.dart';

import 'fake_time_privacy_cubit.dart';

/// On a phone the notice is a bottom sheet whose last row is where the home
/// indicator sits: the close button keeps clear of it.
void main() {
  setUp(() => AppColors.brightness = Brightness.dark);

  testWidgets('the close button stays above the home indicator', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 912);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    final privacy = FakeTimePrivacyCubit(_UnusedTime());
    addTearDown(privacy.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BlocProvider<TimePrivacyCubit>.value(
              value: privacy,
              child: const SingleChildScrollView(child: TimePrivacyBody()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final close = tester.getRect(find.text('common.close'));
    expect(close.bottom, lessThanOrEqualTo(912 - 34));
  });
}

class _UnusedTime implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
