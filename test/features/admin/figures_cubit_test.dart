import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/features/admin/sections/admin_moderation_figures.dart';

import '../../support/recording_fake.dart';

/// The yearly figures in the admin area (HIN-178): the years there are, this
/// one always, and the file of the year chosen.
void main() {
  late FakeAdminRepository admin;

  setUp(() => admin = FakeAdminRepository());

  FiguresCubit build() => FiguresCubit(admin, now: () => DateTime(2027, 2, 1));

  test('offers the years with figures and this one, newest first', () async {
    admin.answer<List<int>>(#moderationFigureYears, const [2026]);
    final cubit = build();
    addTearDown(cubit.close);
    await cubit.load();

    expect(cubit.state.years, [2027, 2026]);
    expect(cubit.state.year, 2027);
  });

  test('without an answer this year is still there to ask for', () async {
    admin.fail(#moderationFigureYears, ApiFailure('Offline', statusCode: 0));
    final cubit = build();
    addTearDown(cubit.close);
    await cubit.load();

    expect(cubit.state.years, [2027]);
  });

  test('downloads the year chosen, once at a time', () async {
    admin
      ..answer<List<int>>(#moderationFigureYears, const [2027, 2026])
      ..answer<Uint8List>(#moderationFigures, Uint8List.fromList([80, 75]));
    final cubit = build();
    addTearDown(cubit.close);
    await cubit.load();
    cubit.choose(2026);

    final bytes = await cubit.download();
    expect(bytes, [80, 75]);
    expect(
      admin.callTo(#moderationFigures),
      invoked(#moderationFigures, positional: [2026]),
    );
    expect(cubit.state.busy, isFalse);
  });
}
