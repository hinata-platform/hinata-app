import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../shell/page_chrome.dart';
import 'report_overview.dart';

/// The report page for servers without the extended time module (HIN-157):
/// the overview of one project, alone. With the module on, `/reports` leads to
/// the module's report page instead, where this same overview is the first
/// view next to the time reports and the budgets.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => PageChrome(
    title: context.t('reports.title'),
    child: ReportOverviewView(
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        context.isCompact ? context.topGutter + 6 : context.pageGutter,
        context.pageGutter,
        context.pageGutter + context.bottomGutter,
      ),
    ),
  );
}
