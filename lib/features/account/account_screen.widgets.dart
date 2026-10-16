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
              child: Icon(
                LucideIcons.camera,
                size: 12,
                color: AppColors.onAccent,
              ),
            ),
          ),
          // The tap surface sits on top: an ink drawn under the opaque photo
          // would never be seen, and a tap on the camera badge would stop at
          // the badge instead of reaching it.
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap, customBorder: const CircleBorder()),
            ),
          ),
        ],
      ),
    );
  }
}
