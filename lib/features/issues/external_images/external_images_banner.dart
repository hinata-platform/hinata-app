import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/soft_card.dart';

/// The band above a description whose external images are held back
/// (HIN-181), as a mail program does it: why, load them this once, or always
/// for mail from [sender]. When the mail's sender could not be verified, there
/// is no "always" to offer, and the band says why instead of leaving the reader
/// to look for it.
///
/// Paper, not glass: it belongs to the content it sits on.
class ExternalImagesBanner extends StatelessWidget {
  const ExternalImagesBanner({
    super.key,
    required this.sender,
    required this.onLoadOnce,
    required this.onTrust,
    this.trusting = false,
    this.trustUnavailable,
  });

  /// The sender's domain; null when the document is not from a mail, or when
  /// its sender is not verified ([trustUnavailable] says why). Either way only
  /// "load once" is left.
  final String? sender;
  final VoidCallback onLoadOnce;
  final VoidCallback onTrust;

  /// While "always" is being saved: the button waits instead of firing twice.
  final bool trusting;

  /// Why the mail's sender cannot be trusted; shown only when there is no
  /// [sender] to offer.
  final ExternalImageTrustUnavailable? trustUnavailable;

  @override
  Widget build(BuildContext context) {
    final sender = this.sender;
    final why = sender == null ? trustUnavailable : null;
    return Semantics(
      liveRegion: true,
      container: true,
      child: SizedBox(
        width: double.infinity,
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
                        LucideIcons.imageOff,
                        size: 16,
                        color: AppColors.accentInk,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.t('issues.externalImages.blocked'),
                            style: TextStyle(
                              fontSize: AppType.label,
                              height: 1.35,
                              color: AppColors.ink,
                            ),
                          ),
                          if (why != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              context.t(switch (why) {
                                ExternalImageTrustUnavailable.unsigned =>
                                  'issues.externalImages.unavailable.unsigned',
                                ExternalImageTrustUnavailable.unverified =>
                                  'issues.externalImages.unavailable.unverified',
                              }),
                              style: TextStyle(
                                fontSize: AppType.label,
                                height: 1.35,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton(
                    onPressed: onLoadOnce,
                    style: _pill,
                    child: Text(context.t('issues.externalImages.loadOnce')),
                  ),
                  if (sender != null)
                    FilledButton(
                      onPressed: trusting ? null : onTrust,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: Text(
                        context.t(
                          'issues.externalImages.trust',
                          variables: {'domain': sender},
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static final ButtonStyle _pill = OutlinedButton.styleFrom(
    minimumSize: const Size(48, 48),
    shape: const StadiumBorder(),
    padding: const EdgeInsets.symmetric(horizontal: 16),
  );
}
