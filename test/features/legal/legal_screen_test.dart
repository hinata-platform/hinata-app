import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/repositories/legal_repository.dart';
import 'package:hinata/features/legal/legal_models.dart';
import 'package:hinata/features/legal/legal_screen.dart';

/// A repository stub standing in for "no server reachable" (native app before
/// connecting) — forces the bundled-asset fallback path.
class _OfflineLegalRepository implements LegalRepository {
  @override
  Future<LegalDocumentContent> fetch(String type, String lang) =>
      throw Exception('offline');
}

/// A repository stub serving operator-managed markdown from the "server".
class _ServerLegalRepository implements LegalRepository {
  @override
  Future<LegalDocumentContent> fetch(String type, String lang) async =>
      LegalDocumentContent(
        type: type,
        lang: lang,
        markdown: '# Vom Server\n\nAngepasster Text des Betreibers.',
      );
}

void main() {
  Widget harness(Locale locale, LegalDocType type, LegalRepository repo) =>
      RepositoryProvider<LegalRepository>.value(
        value: repo,
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('de')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: LegalScreen(type: type),
        ),
      );

  testWidgets('offline → renders the bundled German privacy policy',
      (tester) async {
    await tester.pumpWidget(
      harness(const Locale('de'), LegalDocType.privacy,
          _OfflineLegalRepository()),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Verantwortlicher', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('DSGVO', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('offline → renders the bundled English terms', (tester) async {
    await tester.pumpWidget(
      harness(const Locale('en'), LegalDocType.terms,
          _OfflineLegalRepository()),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Terms of Service', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('server copy wins over the bundled default', (tester) async {
    await tester.pumpWidget(
      harness(const Locale('de'), LegalDocType.privacy,
          _ServerLegalRepository()),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Vom Server', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('Angepasster Text', findRichText: true),
      findsWidgets,
    );
  });
}
