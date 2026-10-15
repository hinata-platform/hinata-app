import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/soft_card.dart';

/// The band under the header for somebody the issue is shared with (HIN-136):
/// what they may do here, that the project stays hidden, and the way out.
/// Paper, not glass: it is content, not chrome.
class ParticipantBanner extends StatelessWidget {
  const ParticipantBanner({
    super.key,
    required this.projectName,
    required this.onLeave,
  });

  final String projectName;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: SoftCard(
        color: AppColors.accentSoft,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 10, 10),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 6,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      LucideIcons.users,
                      size: 16,
                      color: AppColors.accentInk,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      context.t(
                        'issues.participants.banner',
                        variables: {'project': projectName},
                      ),
                      style: TextStyle(
                        fontSize: AppType.label,
                        height: 1.35,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: onLeave,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(context.t('issues.participants.leave')),
            ),
          ],
        ),
      ),
    );
  }
}
