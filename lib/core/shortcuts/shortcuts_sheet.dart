import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/sprint/modals/glass_modal.dart'
    show GlassModalHeader, showGlassModal;
import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_shortcuts.dart';

/// The list of shortcuts that work right now, grouped by what they belong to.
///
/// Built from the registry rather than written out, so a shortcut that was
/// registered is a shortcut that is listed — and one that was not cannot be
/// listed by mistake. A screen that owns a key only while it is open (Escape,
/// in the focus view) therefore appears here only while it is open, which is
/// the honest answer to "what can I press".
Future<void> showShortcutsSheet(BuildContext context) => showGlassModal<void>(
  context,
  width: 460,
  adaptive: false,
  builder: (context) => const _ShortcutsSheet(),
);

class _ShortcutsSheet extends StatelessWidget {
  const _ShortcutsSheet();

  @override
  Widget build(BuildContext context) {
    final registry = ShortcutScope.of(context);
    return AnimatedBuilder(
      animation: registry,
      builder: (context, _) {
        final groups = <String, List<AppShortcut>>{};
        for (final shortcut in registry.listed) {
          groups.putIfAbsent(shortcut.groupKey, () => []).add(shortcut);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassModalHeader(
              icon: LucideIcons.keyboard,
              title: context.t('shortcuts.title'),
              subtitle: context.t('shortcuts.subtitle'),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (groups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          context.t('shortcuts.none'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 6),
                        child: Text(
                          context.t(entry.key),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: AppColors.inkFaint,
                          ),
                        ),
                      ),
                      for (final shortcut in entry.value)
                        _ShortcutRow(shortcut: shortcut),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.shortcut});

  final AppShortcut shortcut;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            context.t(shortcut.labelKey),
            style: TextStyle(fontSize: 13.5, color: AppColors.ink),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.hairline.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          ),
          child: Text(
            shortcut.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              // Tabular so a column of them lines up rather than wobbling with
              // the width of each glyph.
              fontFeatures: const [FontFeature.tabularFigures()],
              color: AppColors.inkSoft,
            ),
          ),
        ),
      ],
    ),
  );
}
