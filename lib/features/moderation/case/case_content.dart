import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/util/dates.dart';
import '../../issues/attachments/attachment_kind.dart' show formatBytes;
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/soft_card.dart';

/// What was reported, as it was, in the look of the original (HIN-174): a
/// comment with whom it answers, an issue with its title, a page, a person,
/// and the files it consists of.
class ReportedContent extends StatelessWidget {
  const ReportedContent({
    super.key,
    required this.content,
    required this.names,
    required this.files,
  });

  final CaseContent content;
  final Map<String, String> names;

  /// The files of the content, with what can be done with each.
  final Widget? files;

  @override
  Widget build(BuildContext context) {
    final c = content;
    final author = c.suggestedResponsible == null
        ? null
        : names[c.suggestedResponsible];
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.kind == ContentKind.comment)
            _CommentLike(content: c, author: author)
          else
            _Document(content: c),
          if (c.externalSender != null) ...[
            const SizedBox(height: 8),
            Text(
              context.t(
                'moderation.case.fromMail',
                variables: {'sender': c.externalSender!},
              ),
              style: TextStyle(
                fontSize: AppType.caption,
                color: AppColors.inkSoft,
              ),
            ),
          ],
          if (files != null) ...[const SizedBox(height: 10), files!],
        ],
      ),
    );
  }
}

class _CommentLike extends StatelessWidget {
  const _CommentLike({required this.content, required this.author});

  final CaseContent content;
  final String? author;

  @override
  Widget build(BuildContext context) {
    final written = content.editedAt ?? content.createdAt;
    final name = author ?? context.t('moderation.case.someone');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppAvatar(name: name, radius: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  if (written != null)
                    Text(
                      recentMoment(context, written),
                      style: TextStyle(
                        fontSize: AppType.caption,
                        color: AppColors.inkSoft,
                      ),
                    ),
                ],
              ),
              if (content.context != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.recess,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    content.context!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.caption,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ],
              if (content.excerpt.isNotEmpty) ...[
                const SizedBox(height: 6),
                SelectableText(
                  content.excerpt,
                  style: TextStyle(
                    fontSize: AppType.body,
                    height: 1.45,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Document extends StatelessWidget {
  const _Document({required this.content});

  final CaseContent content;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (content.title != null)
        SelectableText(
          content.title!,
          style: TextStyle(
            fontSize: AppType.body,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      if (content.excerpt.isNotEmpty) ...[
        const SizedBox(height: 6),
        SelectableText(
          content.excerpt,
          style: TextStyle(
            fontSize: AppType.label,
            height: 1.45,
            color: AppColors.ink,
          ),
        ),
      ],
    ],
  );
}

/// The files of a reported content, by their place in the evidence. Sexual
/// content opens only after a warning; a case about the safety of children
/// never shows its files at all.
class CaseFiles extends StatelessWidget {
  const CaseFiles({
    super.key,
    required this.media,
    required this.childSafety,
    required this.onOpen,
    required this.onProcedure,
  });

  final List<CaseMedia> media;

  /// The safety of children: the files are listed, never opened.
  final bool childSafety;

  /// Opens file [index].
  final void Function(int index) onOpen;
  final VoidCallback onProcedure;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < media.length; i++)
        _FileRow(
          file: media[i],
          index: i,
          onOpen: childSafety ? null : () => onOpen(i),
        ),
      if (childSafety)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Text(
                context.t('moderation.case.filesNeverShown'),
                style: TextStyle(
                  fontSize: AppType.label,
                  color: AppColors.inkSoft,
                ),
              ),
              TextButton(
                onPressed: onProcedure,
                child: Text(context.t('moderation.case.procedure')),
              ),
            ],
          ),
        ),
    ],
  );
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.index, this.onOpen});

  final CaseMedia file;
  final int index;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final name =
        file.fileName ??
        context.t(
          'moderation.case.fileNumber',
          variables: {'n': '${index + 1}'},
        );
    final details = [
      ?file.contentType,
      if (file.size > 0) formatBytes(file.size),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            file.image ? LucideIcons.image : LucideIcons.file,
            size: 18,
            color: AppColors.inkSoft,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.label,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: TextStyle(
                      fontSize: AppType.caption,
                      color: AppColors.inkSoft,
                    ),
                  ),
              ],
            ),
          ),
          if (onOpen != null)
            TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(LucideIcons.eye, size: 16),
              label: Text(context.t('moderation.case.viewFile')),
            ),
        ],
      ),
    );
  }
}
