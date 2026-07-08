import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import 'issue_detail_sheet.dart';

/// Deep-link / route target for `/issues/:id`. Reuses the shared editable
/// [IssueDetailBody]; the primary in-app entry point is the modal sheet
/// (`showIssueDetailSheet`).
class IssueDetailScreen extends StatefulWidget {
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
  State<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends State<IssueDetailScreen> {
  // Reach the shared body to render its floating composer as a bottom overlay
  // (the route has no wolt sticky-action-bar), and to animate to the newest
  // comment after posting.
  final _bodyKey = GlobalKey<IssueDetailBodyState>();
  final _scroll = ScrollController();
  // Bumped by the body when the floating composer's appearance changes (load
  // complete, inline edit) so this overlay — a separate subtree — rebuilds.
  final _composerRev = ValueNotifier<int>(0);

  @override
  void dispose() {
    _scroll.dispose();
    _composerRev.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keyboard height. When it's up the composer rides flush above it (the
    // device inset is hidden then), so the input never gets covered — the modal
    // sheet gets this free from Wolt's Scaffold; the raw route must do it itself.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    // No SafeArea here: the compact shell injects the glass app-bar and floating
    // nav footprints into MediaQuery padding, so we add them as scroll padding
    // (topGutter / bottomGutter) and let content scroll *behind* the bars — the
    // same convention every other screen follows. A SafeArea would instead eat
    // those insets as a flat gap, planting a solid band behind the floating nav
    // instead of letting it float over dissolving content.
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.only(
            top: context.topGutter,
            bottom: context.bottomGutter,
          ),
          child: IssueDetailBody(
            key: _bodyKey,
            issueId: widget.issueId,
            canMinimize: widget.fromModal,
            onChanged: widget.onChanged,
            sheetScroll: _scroll,
            composerRev: _composerRev,
            floatingComposer: true,
          ),
        ),
        // Floating composer pinned to the PHYSICAL bottom of the screen — the
        // same way the modal sheet's sticky action bar anchors. It must NOT be
        // lifted by `bottomGutter`: this route is immersive on compact (no bottom
        // nav), so an offset would only float the dock up off the bottom, leaving
        // the feed visible beneath it and slicing the fade off mid-screen (the
        // exact bug seen in full-screen). Instead the dock sits at `bottom: 0`
        // and adds the home-indicator inset internally (deviceSafeArea: true) so
        // the fade reaches the true bottom and the input pill still clears it.
        Positioned(
          left: 0,
          right: 0,
          bottom: keyboard,
          child: ValueListenableBuilder<int>(
            valueListenable: _composerRev,
            builder: (context, _, _) {
              final state = _bodyKey.currentState;
              if (state == null || !state.hasIssue) {
                return const SizedBox.shrink();
              }
              // Keyboard closed → pad the home-indicator inset in the dock so the
              // fade still reaches the true bottom. Keyboard up → the dock sits
              // flush above it (device inset hidden), so skip the inset.
              return state.buildFloatingComposer(
                context,
                deviceSafeArea: keyboard <= 0,
              );
            },
          ),
        ),
      ],
    );
  }
}
