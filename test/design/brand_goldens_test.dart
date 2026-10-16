// The standard brand must not move a pixel when the tokens become getters on
// a tint palette (HIN-150): these goldens were recorded before the change.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/core/widgets/hex_mark.dart';

void main() {
  for (final dark in const [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('standard brand components ($mode)', (tester) async {
      AppColors.brightness = dark ? Brightness.dark : Brightness.light;
      addTearDown(() => AppColors.brightness = Brightness.light);
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: const ValueKey('brand'),
                child: Container(
                  width: 360,
                  padding: const EdgeInsets.all(16),
                  color: AppColors.canvas,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FilledButton(onPressed: () {}, child: const Text('Save')),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
                      const SizedBox(height: 8),
                      TextButton(onPressed: () {}, child: const Text('More')),
                      const SizedBox(height: 8),
                      const Chip(label: Text('Label')),
                      const SizedBox(height: 8),
                      const HexMark(size: 32),
                      const SizedBox(height: 8),
                      TextField(focusNode: focus, decoration: const InputDecoration(labelText: 'Title')),
                      const SizedBox(height: 8),
                      Container(
                        width: 120,
                        height: 24,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppColors.rail, AppColors.rail2]),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text('rail', style: TextStyle(color: AppColors.railInk, fontSize: 12)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 120,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppColors.accentSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text('active', style: TextStyle(color: AppColors.accentInk, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(
        find.byKey(const ValueKey('brand')),
        matchesGoldenFile('goldens/brand_components_$mode.png'),
      );
    });
  }
}
