import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

// ════════════════════════════════════════════════════════════════════════
//  Hivora "Hive" v2 design kit — shared primitives that mirror the
//  reference web prototype (./Design/v2). Every workspace screen builds
//  from these so cards, badges, glyphs and motion stay 1:1 consistent.
// ════════════════════════════════════════════════════════════════════════

/// Cubic easing used across the design (cubic-bezier(.22,1,.36,1)).
const hiveEase = Cubic(0.22, 1, 0.36, 1);

// ───────────────────────────── meta tables ──────────────────────────────

class _TypeMeta {
  const _TypeMeta(this.icon, this.color);
  final IconData icon;
  final Color color;
}

const _typeMeta = <String, _TypeMeta>{
  'STORY': _TypeMeta(Icons.bookmark_border_rounded, AppColors.stDone),
  'TASK': _TypeMeta(Icons.check_circle_outline_rounded, AppColors.stTodo),
  'BUG': _TypeMeta(Icons.bug_report_outlined, AppColors.priUrgent),
  'EPIC': _TypeMeta(Icons.bolt_rounded, AppColors.stReview),
};

_TypeMeta _typeOf(String type) =>
    _typeMeta[type.toUpperCase()] ?? _typeMeta['TASK']!;

class _PriMeta {
  const _PriMeta(this.icon, this.color);
  final IconData icon;
  final Color color;
}

const _priMeta = <String, _PriMeta>{
  'URGENT': _PriMeta(Icons.keyboard_double_arrow_up_rounded, AppColors.priUrgent),
  'HIGH': _PriMeta(Icons.keyboard_arrow_up_rounded, AppColors.priHigh),
  'NORMAL': _PriMeta(Icons.drag_handle_rounded, AppColors.priNormal),
  'LOW': _PriMeta(Icons.keyboard_arrow_down_rounded, AppColors.priLow),
};

_PriMeta _priOf(String pri) => _priMeta[pri.toUpperCase()] ?? _priMeta['NORMAL']!;

/// Friendly label for a workflow state code, falling back to a humanized form.
String stateLabel(String state) => switch (state.toUpperCase()) {
      'BACKLOG' => 'Backlog',
      'TODO' => 'To Do',
      'IN_PROGRESS' => 'In Progress',
      'IN_REVIEW' => 'In Review',
      'DONE' => 'Done',
      _ => state
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
          .join(' '),
    };

// ───────────────────────────── glyphs / badges ──────────────────────────

/// Small tinted rounded square holding an issue-type icon.
class TypeGlyph extends StatelessWidget {
  const TypeGlyph({super.key, required this.type, this.size = 20});

  final String type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final m = _typeOf(type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.soft(m.color),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Icon(m.icon, size: size * 0.66, color: m.color),
    );
  }
}

/// Pill badge with type icon + label.
class TypeBadge extends StatelessWidget {
  const TypeBadge({super.key, required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final m = _typeOf(type);
    return _Pill(
      color: m.color,
      icon: m.icon,
      label: context.t('type.${type.toLowerCase()}'),
    );
  }
}

/// Priority indicator: a bare flag icon, or a labelled pill.
class PriorityFlag extends StatelessWidget {
  const PriorityFlag({super.key, required this.priority, this.withLabel = false});

  final String priority;
  final bool withLabel;

  @override
  Widget build(BuildContext context) {
    final m = _priOf(priority);
    if (!withLabel) {
      return Icon(m.icon, size: 16, color: m.color);
    }
    return _Pill(
      color: m.color,
      icon: m.icon,
      label: context.t('priority.${priority.toLowerCase()}'),
    );
  }
}

/// Inline state cell: colored dot + state name (matches `.c-state`).
class StateDotBadge extends StatelessWidget {
  const StateDotBadge({super.key, required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.stateColor(state.toUpperCase());
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            stateLabel(state),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.icon, required this.label});
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.soft(color),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }
}

/// Subtle label/tag chip (matches `.tag`).
class LabelTag extends StatelessWidget {
  const LabelTag(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.inkSoft)),
    );
  }
}

/// Monospace readable id (`HIV-241`).
class IdMono extends StatelessWidget {
  const IdMono(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: color ?? AppColors.inkSoft,
        ));
  }
}

// ───────────────────────────── progress ─────────────────────────────────

/// Thin animated progress bar (matches `.prog`).
class HiveProgress extends StatelessWidget {
  const HiveProgress({super.key, required this.value, this.color, this.height = 6});

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 800),
        curve: hiveEase,
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        builder: (_, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: AppColors.canvas2,
          valueColor: AlwaysStoppedAnimation(color ?? AppColors.accent),
        ),
      ),
    );
  }
}

// ───────────────────────────── avatars ──────────────────────────────────

/// Deterministic harmonious color from a seed string (approximates the
/// prototype's oklch(0.62 0.12 hue)).
Color hiveHueColor(String seed) {
  final hue = (seed.hashCode.abs() % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.42, 0.55).toColor();
}

String _initials(String value) {
  final parts =
      value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
}

/// Round initials avatar tinted by name hue.
class HiveAvatar extends StatelessWidget {
  const HiveAvatar({
    super.key,
    required this.name,
    this.size = 30,
    this.ring = false,
    this.imageUrl,
  });

  final String name;
  final double size;
  final bool ring;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: hiveHueColor(name),
        shape: BoxShape.circle,
        image: (imageUrl != null && imageUrl!.isNotEmpty)
            ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover)
            : null,
        boxShadow: ring
            ? const [BoxShadow(color: AppColors.surface, spreadRadius: 2)]
            : null,
      ),
      alignment: Alignment.center,
      child: (imageUrl != null && imageUrl!.isNotEmpty)
          ? null
          : Text(
              _initials(name),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.4,
              ),
            ),
    );
  }
}

/// Overlapping avatar stack with optional +N overflow chip.
class HiveAvatarStack extends StatelessWidget {
  const HiveAvatarStack({
    super.key,
    required this.names,
    this.size = 26,
    this.max = 4,
  });

  final List<String> names;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = names.take(max).toList();
    final extra = names.length - shown.length;
    final overlap = size * 0.3;
    final count = shown.length + (extra > 0 ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    return SizedBox(
      height: size,
      width: size + (count - 1) * (size - overlap),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: HiveAvatar(name: shown[i], size: size, ring: true),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * (size - overlap),
              child: Container(
                width: size,
                height: size,
                decoration: const BoxDecoration(
                  color: AppColors.canvas2,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.surface, spreadRadius: 2)],
                ),
                alignment: Alignment.center,
                child: Text('+$extra',
                    style: TextStyle(
                        fontSize: size * 0.36,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft)),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────── page head ────────────────────────────────

/// Page title + subtitle on the left, optional action buttons on the right.
class PageHead extends StatelessWidget {
  const PageHead({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBrand,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: AppColors.ink,
                  height: 1.1,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, color: AppColors.inkSoft)),
              ],
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: 10), a],
      ],
    );
  }
}

// ───────────────────────────── buttons ──────────────────────────────────

/// Navy primary action button.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton(
      {super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl)),
      ),
      icon: Icon(icon ?? Icons.add_rounded, size: 16),
      label: Text(label),
    );
  }
}

/// White hairline-bordered secondary button.
class GhostButton extends StatelessWidget {
  const GhostButton(
      {super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.hairline),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl)),
      ),
      icon: Icon(icon ?? Icons.tune_rounded, size: 16),
      label: Text(label),
    );
  }
}

// ───────────────────────────── segmented control ────────────────────────

class SegmentItem {
  const SegmentItem({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

/// Pill segmented control (Board / Backlog / Timeline · Weeks / Days).
class SegmentedControl extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<SegmentItem> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: i == selected ? AppColors.navy : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(items[i].icon,
                        size: 15,
                        color: i == selected ? Colors.white : AppColors.inkSoft),
                    const SizedBox(width: 6),
                    Text(items[i].label,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: i == selected
                                ? Colors.white
                                : AppColors.inkSoft)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────── helpers ──────────────────────────────────

/// Relative due label + lateness, mirroring the prototype's dueLabel().
({String text, bool late})? dueLabel(DateTime? due) {
  if (due == null) return null;
  final d = DateTime(due.year, due.month, due.day);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = d.difference(today).inDays;
  if (diff < 0) return (text: '${-diff}d overdue', late: true);
  if (diff == 0) return (text: 'Today', late: true);
  if (diff == 1) return (text: 'Tomorrow', late: false);
  if (diff <= 7) return (text: '${diff}d', late: false);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return (text: '${months[d.month - 1]} ${d.day}', late: false);
}

/// Format minutes as `2h 30m`.
String fmtDuration(int? minutes) {
  if (minutes == null) return '—';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}
