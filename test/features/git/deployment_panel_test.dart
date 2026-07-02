import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/git/widgets/deployment_panel.dart';

/// Reproduces the crash reported when expanding the "Create branch" dropdown in
/// the issue deployment panel for a connected repository.
void main() {
  final project = Project.fromJson({
    'id': 'p1',
    'key': 'HIN',
    'name': 'hinata-app',
    'workflowStates': [
      {'id': 's1', 'name': 'In Progress', 'hue': 70},
      {'id': 's2', 'name': 'In Review', 'hue': 300},
    ],
    'git': {
      'provider': 'github',
      'owner': 'hinata-platform',
      'repo': 'hinata-app',
      'method': 'oauth',
      'branchTemplate': '{key}-{summary}',
      'automation': {
        'branchCreated': {'on': true, 'toStateId': 's1'},
        'prOpened': {'on': true, 'toStateId': 's2'},
        'smartCommits': true,
      },
    },
  });

  const issue = Issue(
    id: 'i1',
    projectId: 'p1',
    readableId: 'HIN-18',
    title: 'Restore drag-handle focus ring after a drop',
    state: 'Open',
  );

  Widget host(double width) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: DeploymentPanel(
                  issue: issue,
                  project: project,
                  onConnectInSettings: () {},
                  onProjectChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('expanding Create branch does not throw', (tester) async {
    await tester.pumpWidget(host(380));
    await tester.tap(find.text('Create branch'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanding Create commit does not throw', (tester) async {
    await tester.pumpWidget(host(380));
    await tester.tap(find.text('Create commit'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
