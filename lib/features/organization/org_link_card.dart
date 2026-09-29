import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/widgets/hive_widgets.dart' show forwardArrow;
import '../admin/admin_form_helpers.dart';

/// A card on the Organisation page that leads to a page of its own: the
/// holiday calendars, the organisation's log. What lives there does not fit a
/// card in a form that saves as a whole, so the card only names it and opens
/// it.
class OrgLinkCard extends StatelessWidget {
  const OrgLinkCard({
    super.key,
    required this.icon,
    required this.titleKey,
    required this.hintKey,
    required this.openKey,
    required this.route,
  });

  final IconData icon;

  /// i18n keys of the card's title, its one line and its button.
  final String titleKey;
  final String hintKey;
  final String openKey;

  /// Where the button goes.
  final String route;

  @override
  Widget build(BuildContext context) => AdminSectionCard(
    icon: icon,
    title: context.t(titleKey),
    subtitle: context.t(hintKey),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            onPressed: () => context.go(route),
            icon: Icon(forwardArrow(context), size: 16),
            label: Text(context.t(openKey)),
          ),
        ),
      ),
    ],
  );
}
