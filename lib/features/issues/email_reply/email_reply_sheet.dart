import 'package:dio/dio.dart' show MultipartFile;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/repositories/issue_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../sprint/modals/glass_modal.dart';

/// Opens the Liquid-Glass "Reply by email" composer for an email-sourced issue.
/// Sends a reply to the issue's original sender ([Issue.reporterEmail]) via the
/// platform SMTP; attachments are uploaded onto the issue and referenced by id.
Future<void> showEmailReplySheet(
  BuildContext context, {
  required Issue issue,
  required IssueRepository repo,
}) {
  return showGlassModal<void>(
    context,
    width: 560,
    builder: (_) => _EmailReplyForm(issue: issue, repo: repo),
  );
}

class _EmailReplyForm extends StatefulWidget {
  const _EmailReplyForm({required this.issue, required this.repo});

  final Issue issue;
  final IssueRepository repo;

  @override
  State<_EmailReplyForm> createState() => _EmailReplyFormState();
}

/// One attachment the user added to the draft. It is uploaded onto the issue
/// immediately on pick (so the reply can reference it by id), showing a spinner
/// while in flight and an error affordance if the upload fails.
class _Draft {
  _Draft(this.name);
  final String name;
  String? id; // set once uploaded
  bool uploading = true;
  bool failed = false;
}

class _EmailReplyFormState extends State<_EmailReplyForm> {
  late final TextEditingController _subject = TextEditingController(
    text: _prefillSubject(),
  );
  final TextEditingController _body = TextEditingController();
  final List<_Draft> _drafts = [];
  bool _sending = false;

  String _prefillSubject() {
    final original = widget.issue.inboundSubject?.trim();
    if (original == null || original.isEmpty) return '';
    // Don't stack "Re: Re: …" if the source subject already carries one.
    return original.toLowerCase().startsWith('re:') ? original : 'Re: $original';
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending &&
      _subject.text.trim().isNotEmpty &&
      _body.text.trim().isNotEmpty &&
      !_drafts.any((d) => d.uploading);

  Future<void> _pick() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: kIsWeb, // web has no path; bytes are required
      );
    } catch (_) {
      if (mounted) {
        showGlassErrorToast(context, context.t('issues.attachments.pickFailed'));
      }
      return;
    }
    if (result == null || !mounted) return;
    for (final f in result.files) {
      final draft = _Draft(f.name);
      setState(() => _drafts.add(draft));
      _upload(draft, f);
    }
  }

  Future<void> _upload(_Draft draft, PlatformFile file) async {
    try {
      final multipart = kIsWeb || file.path == null
          ? MultipartFile.fromBytes(file.bytes ?? const [], filename: file.name)
          : await MultipartFile.fromFile(file.path!, filename: file.name);
      final saved = await widget.repo.uploadAttachment(
        widget.issue.id,
        multipart,
      );
      // The just-added attachment is the newest one on the returned issue.
      final id = saved.attachments.isNotEmpty ? saved.attachments.last.id : null;
      if (!mounted) return;
      setState(() {
        draft.id = id;
        draft.uploading = false;
        draft.failed = id == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        draft.uploading = false;
        draft.failed = true;
      });
    }
  }

  Future<void> _removeDraft(_Draft draft) async {
    setState(() => _drafts.remove(draft));
    // Best-effort: also detach it from the issue so a cancelled attachment
    // doesn't linger. Ignore failures — the reply simply won't reference it.
    if (draft.id != null) {
      try {
        await widget.repo.deleteAttachment(widget.issue.id, draft.id!);
      } catch (_) {}
    }
  }

  Future<void> _send() async {
    if (!_canSend) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _sending = true);
    try {
      await widget.repo.replyEmail(
        widget.issue.id,
        subject: _subject.text.trim(),
        body: _body.text.trim(),
        attachmentIds: [
          for (final d in _drafts)
            if (d.id != null && !d.failed) d.id!,
        ],
      );
      if (!mounted) return;
      Navigator.of(context).maybePop();
      showGlassToast(
        context,
        context.t('issues.replyEmail.sent'),
        kind: GlassToastKind.success,
      );
    } on ApiFailure catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showGlassErrorToast(context, context.t(e.message));
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      showGlassErrorToast(context, context.t('errors.unexpected'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipient = widget.issue.reporterEmail ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.mail,
          title: context.t('issues.replyEmail.title'),
          subtitle: context.t('issues.replyEmail.subtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassInfoLine(
                  icon: LucideIcons.atSign,
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                      children: [
                        TextSpan(text: '${context.t('issues.replyEmail.to')} '),
                        TextSpan(
                          text: recipient,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ).copyWith(color: AppColors.ink),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t('issues.replyEmail.subject'),
                  child: TextField(
                    controller: _subject,
                    onChanged: (_) => setState(() {}),
                    decoration: glassInputDecoration(
                      hint: context.t('issues.replyEmail.subjectHint'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t('issues.replyEmail.body'),
                  child: TextField(
                    controller: _body,
                    onChanged: (_) => setState(() {}),
                    minLines: 6,
                    maxLines: 12,
                    keyboardType: TextInputType.multiline,
                    decoration: glassInputDecoration(
                      hint: context.t('issues.replyEmail.bodyHint'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _AttachmentsRow(
                  drafts: _drafts,
                  onAdd: _sending ? null : _pick,
                  onRemove: _sending ? null : _removeDraft,
                ),
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('issues.replyEmail.send'),
          confirmIcon: LucideIcons.send,
          busy: _sending,
          onConfirm: _canSend ? _send : null,
        ),
      ],
    );
  }
}

/// The "Add attachment" affordance plus a wrapping list of attachment chips.
class _AttachmentsRow extends StatelessWidget {
  const _AttachmentsRow({
    required this.drafts,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_Draft> drafts;
  final VoidCallback? onAdd;
  final ValueChanged<_Draft>? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _AddChip(onTap: onAdd),
            for (final d in drafts)
              _AttachmentChip(
                draft: d,
                onRemove: onRemove == null ? null : () => onRemove!(d),
              ),
          ],
        ),
      ],
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.paperclip,
                size: 15,
                color: AppColors.accentStrong,
              ),
              const SizedBox(width: 7),
              Text(
                context.t('issues.replyEmail.attach'),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.draft, required this.onRemove});
  final _Draft draft;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final failed = draft.failed;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 6, 8),
      decoration: BoxDecoration(
        color: failed
            ? AppColors.danger.withValues(alpha: 0.10)
            : AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(
          color: failed
              ? AppColors.danger.withValues(alpha: 0.5)
              : AppColors.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (draft.uploading)
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              failed ? LucideIcons.circleAlert : LucideIcons.file,
              size: 14,
              color: failed ? AppColors.danger : AppColors.inkSoft,
            ),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              draft.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: failed ? AppColors.danger : AppColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            onPressed: onRemove,
            icon: Icon(LucideIcons.x, size: 14, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}
