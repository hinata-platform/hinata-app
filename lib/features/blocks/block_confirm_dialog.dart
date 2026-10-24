import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../account/account_widgets.dart' show AccountNote, AccountNoteTone;
import '../sprint/modals/glass_modal.dart'
    show GlassModalFooter, GlassModalHeader, showGlassModal;

/// Asks before blocking [name] (HIN-168), and runs [onConfirm] behind the
/// button so a refusal shows in the dialog instead of after it closed.
///
/// True once the block is in place; null when the reader changed their mind.
/// Says plainly what ends and what stays, including the part that surprises:
/// assigning and adding still work, and their notices still arrive.
Future<bool?> showBlockConfirm(
  BuildContext context, {
  required String name,
  required Future<void> Function() onConfirm,
}) {
  return showGlassModal<bool>(
    context,
    adaptive: false,
    width: 460,
    builder: (_) => BlockConfirmDialog(name: name, onConfirm: onConfirm),
  );
}

/// The body of [showBlockConfirm].
class BlockConfirmDialog extends StatefulWidget {
  const BlockConfirmDialog({
    super.key,
    required this.name,
    required this.onConfirm,
  });

  final String name;
  final Future<void> Function() onConfirm;

  @override
  State<BlockConfirmDialog> createState() => _BlockConfirmDialogState();
}

class _BlockConfirmDialogState extends State<BlockConfirmDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).maybePop(true);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _error = context.t(failure.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = {'name': widget.name};
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassModalHeader(
          icon: LucideIcons.userX,
          title: context.t('blocks.confirm.title', variables: name),
          subtitle: context.t('blocks.confirm.subtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoLine(
                  icon: LucideIcons.bellOff,
                  text: context.t(
                    'blocks.confirm.notifications',
                    variables: name,
                  ),
                ),
                _InfoLine(
                  icon: LucideIcons.chevronsDownUp,
                  text: context.t('blocks.confirm.folded', variables: name),
                ),
                _InfoLine(
                  icon: LucideIcons.userRoundMinus,
                  text: context.t('blocks.confirm.contact', variables: name),
                ),
                _InfoLine(
                  icon: LucideIcons.folderOpen,
                  text: context.t('blocks.confirm.work', variables: name),
                ),
                _InfoLine(
                  icon: LucideIcons.eyeOff,
                  text: context.t('blocks.confirm.private', variables: name),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  AccountNote(
                    text: _error!,
                    icon: LucideIcons.triangleAlert,
                    tone: AccountNoteTone.danger,
                  ),
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('blocks.confirm.button'),
          confirmIcon: LucideIcons.userX,
          busy: _busy,
          onConfirm: _run,
        ),
      ],
    );
  }
}

/// One thing that changes, or does not, with its glyph.
class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ExcludeSemantics(
              child: Icon(icon, size: 16, color: AppColors.inkSoft),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppType.label,
                height: 1.4,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
