import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_type.dart';

/// Where the project's documentation lives: the same site the legal pages are
/// on, so it is reachable whichever server the app talks to.
const String docsBaseUrl = 'https://hinata.ahmadre.com';

/// The languages the documentation is written in. Everybody else reads the
/// English page rather than a 404.
const Set<String> docsLanguages = {'en', 'de'};

/// The pages the app links to. One place, so a renamed page is one edit and a
/// test can hold the list against the site's navigation.
abstract final class DocsPage {
  static const timeTracking = 'guide-time';
  static const timeTrackingAdvanced = 'time-tracking-advanced';
  static const absences = 'absences';
  static const timeTrackingAdmin = 'admin-time-tracking';
  static const timeTrackingPrivacy = 'time-tracking-privacy';
  static const adminArea = 'admin-area';

  /// For moderators, with the procedure for content that endangers children
  /// (HIN-174, written in HIN-178).
  static const moderation = 'moderation';
}

/// Public URL of a documentation page in the reader's language, or in English
/// where the page is not written in it.
Uri docsUrl(String languageCode, String slug) {
  final lang = docsLanguages.contains(languageCode) ? languageCode : 'en';
  return Uri.parse('$docsBaseUrl/$lang/$slug.html');
}

/// Opens a documentation page in the external browser.
Future<void> openDocs(BuildContext context, String slug) => launchUrl(
  docsUrl(Localizations.localeOf(context).languageCode, slug),
  mode: LaunchMode.externalApplication,
);

/// A quiet "read more in the docs" link under a help text.
class DocsLink extends StatelessWidget {
  const DocsLink({super.key, required this.slug, this.labelKey});

  final String slug;

  /// What the link says; "Read more in the documentation" when not given.
  final String? labelKey;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.accentInk;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        link: true,
        child: InkWell(
          onTap: () => openDocs(context, slug),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.bookOpen, size: 14, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    context.t(labelKey ?? 'docs.readMore'),
                    style: TextStyle(
                      fontSize: AppType.caption,
                      fontWeight: FontWeight.w600,
                      color: color,
                      decoration: TextDecoration.underline,
                      decorationColor: color.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                ExcludeSemantics(
                  child: Icon(LucideIcons.externalLink, size: 12, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
