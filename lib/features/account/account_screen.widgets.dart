part of 'account_screen.dart';

/// The hero avatar with a camera badge + busy overlay; tap to change/remove.
class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({
    required this.name,
    required this.imageUrl,
    required this.busy,
    required this.onTap,
    this.radius = 28,
  });

  final String name;
  final String? imageUrl;
  final bool busy;
  final VoidCallback onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.t('account.avatar.title'),
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
              child: AppAvatar(name: name, imageUrl: imageUrl, radius: radius),
            ),
            if (busy)
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.rail, width: 2),
                ),
                child: const Icon(
                  LucideIcons.camera,
                  size: 12,
                  color: Color(0xFF2A2410),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessToggle extends StatelessWidget {
  const _AccessToggle({
    required this.teams,
    required this.teamsLabel,
    required this.projectsLabel,
    required this.onChanged,
  });
  final bool teams;
  final String teamsLabel;
  final String projectsLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool active, VoidCallback onTap) =>
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.ink : AppColors.inkSoft,
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(teamsLabel, teams, () => onChanged(true)),
          seg(projectsLabel, !teams, () => onChanged(false)),
        ],
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.mode, required this.onChanged});
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <(ThemeMode, IconData, String)>[
      (ThemeMode.system, LucideIcons.monitor, 'settings.themeSystem'),
      (ThemeMode.light, LucideIcons.sun, 'settings.themeLight'),
      (ThemeMode.dark, LucideIcons.moon, 'settings.themeDark'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.hairline),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (m, icon, labelKey) in options)
            Tooltip(
              message: context.t(labelKey),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: m == mode
                        ? AppColors.accentSoft
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 17,
                    color: m == mode
                        ? AppColors.accentStrong
                        : AppColors.inkSoft,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
