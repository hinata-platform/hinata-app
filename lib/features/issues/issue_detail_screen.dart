import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import 'issue_detail_sheet.dart';

/// Deep-link / route target for `/issues/:id`. Reuses the shared editable
/// [IssueDetailBody]; the primary in-app entry point is the modal sheet
/// (`showIssueDetailSheet`).
class IssueDetailScreen extends StatelessWidget {
  const IssueDetailScreen({
    super.key,
    required this.issueId,
    this.fromModal = false,
    this.onChanged,
  });

  final String issueId;

  /// Set when the page was promoted from the modal sheet ("full screen"), so the
  /// top bar offers an "exit full screen" button back to the modal.
  final bool fromModal;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    // No SafeArea here: the compact shell injects the glass app-bar and floating
    // nav footprints into MediaQuery padding, so we add them as scroll padding
    // (topGutter / bottomGutter) and let content scroll *behind* the bars — the
    // same convention every other screen follows. A SafeArea would instead eat
    // those insets as a flat gap, planting a solid band behind the floating nav
    // instead of letting it float over dissolving content.
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        top: context.topGutter,
        bottom: context.bottomGutter,
      ),
      child: IssueDetailBody(
        issueId: issueId,
        canMinimize: fromModal,
        onChanged: onChanged,
      ),
    );
  }
}
