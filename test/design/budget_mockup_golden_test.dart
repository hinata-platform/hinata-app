// The budget shapes of HIN-151 as somebody meets them: the project settings,
// the entry form, a project head, the dashboard tile and the timer bar, at
// phone, tablet and desktop width, light and dark, at text scale 1.0 and 2.0.
//
// Unlike the other goldens in this folder this one loads the real fonts and
// the German translations: it is the design preview Rebar signs off on before
// the surfaces are wired (HIN-152, step 0), and a preview in placeholder boxes
// cannot be judged for type or wording.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i18next/i18next.dart';
import 'package:hinata/core/i18n/i18n.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/core/theme/app_type.dart';
import 'package:hinata/core/widgets/budget/budget.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'golden_platform.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, Iterable<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(
        File(file).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    }
    await loader.load();
  }

  final fonts = Directory('assets/fonts').listSync().whereType<File>();
  await load(
    AppTheme.fontUi,
    fonts.where((f) => f.path.contains('IBMPlexSans')).map((f) => f.path),
  );
  await load(
    AppTheme.fontMono,
    fonts.where((f) => f.path.contains('IBMPlexMono')).map((f) => f.path),
  );
  await load(
    AppTheme.fontBrand,
    fonts.where((f) => f.path.contains('Sora')).map((f) => f.path),
  );
  final lucide =
      Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['HOME']}/.pub-cache';
  final lucideTtf = Directory('$lucide/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .where((d) => d.path.contains('lucide_icons_flutter-'))
      .map((d) => '${d.path}/assets/lucide.ttf')
      .last;
  await load('packages/lucide_icons_flutter/Lucide', [lucideTtf]);
}

/// The German strings, read once and handed over synchronously: the asset
/// bundle answers on the real event loop, which a widget test does not run.
class _FileSource implements LocalizationDataSource {
  _FileSource(this.data);
  final Map<String, dynamic> data;

  @override
  Future<Map<Locale, Map<String, dynamic>>> load(List<Locale> locales) =>
      SynchronousFuture({
        for (final locale in locales) locale: {'common': data},
      });
}

final _german = _FileSource(
  jsonDecode(File('assets/i18n/de/common.json').readAsStringSync())
      as Map<String, dynamic>,
);

const _viewports = {'phone': 360.0, 'tablet': 768.0, 'desktop': 1200.0};

void main() {
  setUpAll(_loadFonts);

  for (final viewport in _viewports.entries) {
    for (final dark in const [false, true]) {
      for (final scale in const [1.0, 2.0]) {
        final name =
            'budget_mockup_${viewport.key}_${dark ? 'dark' : 'light'}_x${scale.toInt()}';
        testWidgets(name, (tester) async {
          AppColors.brightness = dark ? Brightness.dark : Brightness.light;
          addTearDown(() => AppColors.brightness = Brightness.light);
          final size = Size(viewport.value, 2400);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('de'),
              supportedLocales: I18n.supportedLocales,
              localizationsDelegates: [
                I18NextLocalizationDelegate(
                  locales: I18n.supportedLocales,
                  dataSource: _german,
                  options: const I18NextOptions(
                    fallbackNamespaces: ['common'],
                    escapeValue: false,
                  ),
                ),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: const _Mockup(),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(const ValueKey('mockup')),
            matchesGoldenFile('goldens/$name.png'),
          );
        }, skip: skipGoldensOffMac);
      }
    }
  }
}

class _Mockup extends StatelessWidget {
  const _Mockup();

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      const _Section(
        title: '1 · Projekt-Einstellungen → Zeiterfassung',
        child: _Settings(),
      ),
      const _Section(title: '2 · Eintrag erfassen', child: _EntryForm()),
      const _Section(title: '3 · Board-Kopf und Projektliste', child: _Heads()),
      const _Section(title: '4 · Dashboard-Kachel', child: _Dashboard()),
      const _Section(
        title: '5 · Vorgangsdetail und Timer-Leiste',
        child: _IssueAndTimer(),
      ),
      const _Section(title: '6 · Zustände', child: _States()),
    ];
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SingleChildScrollView(
        child: RepaintBoundary(
          key: const ValueKey('mockup'),
          child: ColoredBox(
            color: AppColors.canvas,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1000
                      ? 3
                      : constraints.maxWidth >= 700
                      ? 2
                      : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 16) / columns;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final s in sections)
                        SizedBox(width: width, child: s),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: AppType.caption,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: AppColors.inkFaint,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppColors.hairline),
          ),
          child: child,
        ),
      ],
    );
  }
}

/// A field drawn as the app draws one, filled; the mockup is about what sits
/// around it.
class _FakeField extends StatelessWidget {
  const _FakeField({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppType.label,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.fieldRim),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.inkSoft),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: AppType.label,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FakeField(label: 'Budget', value: '120h'),
        const SizedBox(height: 12),
        BudgetMeter(
          label: context.t('budget.timeBudget'),
          gauge: const BudgetGauge(used: 96 * 60 + 30, limit: 120 * 60),
        ),
        const SizedBox(height: 18),
        const BudgetMeter(
          label: 'Summe der Schätzungen',
          gauge: BudgetGauge(used: 96 * 60 + 30, limit: 140 * 60),
        ),
      ],
    );
  }
}

class _EntryForm extends StatelessWidget {
  const _EntryForm();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FakeField(
          label: 'Vorgang',
          value: 'HIN-142 · Startseite neu',
          icon: LucideIcons.circleCheck,
        ),
        const SizedBox(height: 12),
        const _FakeField(
          label: 'Dauer',
          value: '2 h 30 min',
          icon: LucideIcons.timer,
        ),
        const SizedBox(height: 12),
        const BudgetNotice(
          kind: BudgetNoticeKind.issueEstimate,
          subject: 'HIN-142',
          gauge: BudgetGauge(used: 7 * 60, limit: 8 * 60),
        ),
        const SizedBox(height: 8),
        const BudgetNotice(
          kind: BudgetNoticeKind.projectBudget,
          subject: 'Website-Relaunch',
          gauge: BudgetGauge(used: 125 * 60, limit: 120 * 60),
        ),
        const SizedBox(height: 14),
        // The real save capsule is glass and draws through a shader the
        // test renderer does not run; a stand-in of the same size.
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              'Speichern',
              style: TextStyle(
                fontSize: AppType.label,
                fontWeight: FontWeight.w600,
                color: AppColors.onAccent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Heads extends StatelessWidget {
  const _Heads();

  // Name and capsule share a line, the capsule aligned at the end. From a
  // large text size on the capsule moves under the name instead of squeezing
  // a long name until it breaks inside a word.
  Widget _row(BuildContext context, String name, BudgetGauge gauge) {
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final title = Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            LucideIcons.hexagon,
            size: 15,
            color: AppColors.accentText,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              fontSize: AppType.body,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ),
        if (!stacked) _capsule(context, gauge),
      ],
    );
    if (!stacked) return title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [title, _capsule(context, gauge)],
    );
  }

  Widget _capsule(BuildContext context, BudgetGauge gauge) => BudgetCapsule(
    label: context.t('budget.timeBudget'),
    gauge: gauge,
    onTap: () {},
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          context,
          'Interne Tools',
          const BudgetGauge(used: 31 * 60, limit: 80 * 60),
        ),
        _row(
          context,
          'Website-Relaunch',
          const BudgetGauge(used: 101 * 60, limit: 120 * 60),
        ),
        _row(
          context,
          'Mitgliederportal',
          const BudgetGauge(used: 64 * 60, limit: 50 * 60),
        ),
      ],
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.t('budget.dashboard.title'),
          style: TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: AppType.title,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.spaceAround,
          spacing: 8,
          runSpacing: 16,
          children: [
            for (final (name, gauge) in const [
              ('Mitgliederportal', BudgetGauge(used: 64 * 60, limit: 50 * 60)),
              (
                'Website-Relaunch',
                BudgetGauge(used: 101 * 60, limit: 120 * 60),
              ),
              ('Interne Tools', BudgetGauge(used: 31 * 60, limit: 80 * 60)),
            ])
              BudgetRing(label: name, gauge: gauge, onTap: () {}),
          ],
        ),
      ],
    );
  }
}

class _IssueAndTimer extends StatelessWidget {
  const _IssueAndTimer();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BudgetMeter(
          label: context.t('budget.estimate'),
          gauge: const BudgetGauge(used: 7 * 60, limit: 8 * 60),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              const Icon(LucideIcons.square, size: 16, color: AppColors.danger),
              Text(
                'HIN-142 · Startseite neu',
                style: TextStyle(fontSize: AppType.label, color: AppColors.ink),
              ),
              TimerBudgetDot(
                label: context.t('budget.estimate'),
                gauge: const BudgetGauge(used: 7 * 60 + 40, limit: 8 * 60),
              ),
              Text(
                '1:12:08',
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: AppType.label,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _States extends StatelessWidget {
  const _States();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BudgetMeter(label: 'Zeitbudget (lädt)', gauge: null),
        const SizedBox(height: 18),
        BudgetMeter(
          label: '${context.t('budget.timeBudget')} (genau 100 %)',
          gauge: const BudgetGauge(used: 120 * 60, limit: 120 * 60),
        ),
        const SizedBox(height: 18),
        BudgetMeter(
          label: '${context.t('budget.timeBudget')} (125 %)',
          gauge: const BudgetGauge(used: 150 * 60, limit: 120 * 60),
        ),
        const SizedBox(height: 18),
        const BudgetNotice(
          kind: BudgetNoticeKind.projectBudget,
          subject: 'Website-Relaunch',
          gauge: BudgetGauge(used: 101 * 60, limit: 120 * 60),
          compact: true,
        ),
        const SizedBox(height: 18),
        Text(
          '${context.t('budget.dashboard.empty')}. ${context.t('budget.dashboard.emptyHint')}',
          style: TextStyle(fontSize: AppType.label, color: AppColors.inkSoft),
        ),
      ],
    );
  }
}
