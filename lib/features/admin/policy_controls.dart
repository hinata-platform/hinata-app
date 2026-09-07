import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
import '../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassDatePicker,
        showGlassDatePopover,
        showGlassOptions;
import 'admin_form_helpers.dart';

/// Controls for an operator *policy* — a setting with three states rather than
/// two.
///
/// Every policy in the server's settings document is nullable, and absent is not
/// the same as off: it means "whatever this deployment's environment says". That
/// is how an operator keeps one answer in `HINATA_*` env vars across a fleet of
/// servers instead of copying it into every database. So "take the environment
/// default" has to be reachable from this screen — otherwise the only way back
/// to it is editing Mongo by hand, and the admin console quietly becomes a
/// one-way door.
///
/// The second thing these carry is the co-determination note. A policy that
/// makes one person's working time legible to another is, under § 87 Abs. 1
/// Nr. 6 BetrVG (and the Länder's LPVG in the public sector), subject to
/// co-determination — objective suitability for monitoring is enough, intent is
/// not required. The note belongs *at the switch*, at the moment somebody
/// reaches for it, not on a documentation page they may never open.

/// The note itself, rendered directly under a monitoring-capable policy.
class CodeterminationNote extends StatelessWidget {
  const CodeterminationNote({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: AdminNote(
      icon: LucideIcons.scale,
      tone: AdminNoteTone.warning,
      text: context.t('admin.timeTracking.codetermination'),
    ),
  );
}

/// The badge that stands where a control would be while the value is absent.
///
/// It deliberately does not draw a switch in some arbitrary position: we do not
/// know what the environment says, and guessing would be a lie the operator
/// would have no way to catch. Tapping it commits an explicit value, which is
/// the only way a control can honestly appear.
class _EnvDefaultBadge extends StatelessWidget {
  const _EnvDefaultBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.t('admin.timeTracking.envDefaultHint'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: Text(
              context.t('admin.timeTracking.envDefault'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Take the environment default" — clears the value back to absent. Rendered
/// only while there is something to clear.
class EnvDefaultAction extends StatelessWidget {
  const EnvDefaultAction({
    super.key,
    required this.isDefault,
    required this.onReset,
  });

  /// Whether the value is already absent (then this renders nothing).
  final bool isDefault;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    if (isDefault) return const SizedBox.shrink();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: onReset,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: AppColors.inkSoft,
        ),
        icon: const Icon(LucideIcons.rotateCcw, size: 13),
        label: Text(
          context.t('admin.timeTracking.useEnvDefault'),
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}

/// Shared frame: title, description, the control, the co-determination note when
/// the policy is monitoring-capable, and the reset back to the env default.
class _PolicyRow extends StatelessWidget {
  const _PolicyRow({
    required this.title,
    required this.description,
    required this.control,
    required this.isDefault,
    required this.onReset,
    required this.monitoring,
  });

  final String title;
  final String description;
  final Widget control;
  final bool isDefault;
  final VoidCallback onReset;
  final bool monitoring;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Bounded rather than flexible: a Flexible sibling of the title's
              // Expanded would split the row down the middle and leave a gap
              // beside a switch that needs 50 px. The cap is well clear of the
              // longest real label and only bites on a phone in a language that
              // spells "environment default" at length — where an ellipsis is
              // the right answer and a 78-pixel overflow is not.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: control,
              ),
            ],
          ),
          if (monitoring) const CodeterminationNote(),
          EnvDefaultAction(isDefault: isDefault, onReset: onReset),
        ],
      ),
    );
  }
}

/// A three-state policy switch: on, off, or absent (environment decides).
class PolicySwitch extends StatelessWidget {
  const PolicySwitch({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.monitoring = false,
  });

  final String title;
  final String description;

  /// Null means the value is absent — the environment default applies.
  final bool? value;
  final ValueChanged<bool?> onChanged;

  /// Whether this policy makes one person's time legible to another, and so
  /// carries the co-determination note.
  final bool monitoring;

  @override
  Widget build(BuildContext context) {
    final current = value;
    return _PolicyRow(
      title: title,
      description: description,
      isDefault: current == null,
      onReset: () => onChanged(null),
      monitoring: monitoring,
      control: current == null
          ? _EnvDefaultBadge(onTap: () => onChanged(false))
          : HiveSwitch(value: current, onChanged: onChanged),
    );
  }
}

/// A one-line field that opens a glass picker rather than rendering the choices
/// inline. The list always offers the environment default as its own row, so
/// clearing the value is a pick like any other.
class PolicyChoice extends StatefulWidget {
  const PolicyChoice({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.helper,
  });

  final String label;

  /// The stored wire value, or null for "environment decides".
  final String? value;

  /// Wire value → the i18n key naming it.
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;
  final String? helper;

  @override
  State<PolicyChoice> createState() => _PolicyChoiceState();
}

class _PolicyChoiceState extends State<PolicyChoice> {
  final _fieldKey = GlobalKey();

  Future<void> _pick() async {
    final anchor = anchorRectOf(_fieldKey);
    // A record is needed to carry "null was chosen" through a nullable result:
    // showGlassOptions resolves to null on dismiss too, and clearing a value is
    // not the same as changing nothing.
    final picked = await showGlassOptions<({String? value})>(
      context,
      title: widget.label,
      anchorRect: anchor,
      options: [
        (
          value: (value: null),
          child: _OptionLabel(
            text: context.t('admin.timeTracking.envDefault'),
            muted: true,
          ),
        ),
        for (final entry in widget.options.entries)
          (
            value: (value: entry.key),
            child: _OptionLabel(text: context.t(entry.value)),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    widget.onChanged(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final labelKey = widget.value == null ? null : widget.options[widget.value];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TapField(
            fieldKey: _fieldKey,
            label: widget.label,
            helper: widget.helper,
            onTap: _pick,
            value: labelKey == null
                ? context.t('admin.timeTracking.envDefault')
                : context.t(labelKey),
            muted: labelKey == null,
            icon: LucideIcons.chevronDown,
          ),
          EnvDefaultAction(
            isDefault: widget.value == null,
            onReset: () => widget.onChanged(null),
          ),
        ],
      ),
    );
  }
}

/// A one-line date field on the glass calendar. Absent means the environment
/// default; the calendar's own "clear" row lands there too.
class PolicyDate extends StatefulWidget {
  const PolicyDate({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
  });

  final String label;

  /// ISO `yyyy-MM-dd`, or null for "environment decides".
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? helper;

  @override
  State<PolicyDate> createState() => _PolicyDateState();
}

class _PolicyDateState extends State<PolicyDate> {
  final _fieldKey = GlobalKey();

  /// Dates are stored as a plain `yyyy-MM-dd` calendar day, never an instant:
  /// a lock date is the same day in every time zone, so it must not be shifted
  /// by one on the way in or out.
  static String _iso(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  Future<void> _pick() async {
    final parsed = DateTime.tryParse(widget.value ?? '');
    final initial = parsed ?? DateTime.now();
    final first = DateTime(initial.year - 10);
    final last = DateTime(initial.year + 10, 12, 31);
    final anchor = anchorRectOf(_fieldKey);
    final wide =
        MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint &&
        anchor != null;
    var cleared = false;
    void clear() => cleared = true;
    final picked = wide
        ? await showGlassDatePopover(
            context,
            anchorRect: anchor,
            initialDate: initial,
            firstDate: first,
            lastDate: last,
            title: widget.label,
            onClear: clear,
          )
        : await showGlassDatePicker(
            context,
            initialDate: initial,
            firstDate: first,
            lastDate: last,
            title: widget.label,
            onClear: clear,
          );
    if (!mounted) return;
    if (cleared) {
      widget.onChanged(null);
    } else if (picked != null) {
      widget.onChanged(_iso(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TapField(
            fieldKey: _fieldKey,
            label: widget.label,
            helper: widget.helper,
            onTap: _pick,
            value: value ?? context.t('admin.timeTracking.envDefault'),
            muted: value == null,
            icon: LucideIcons.calendar,
          ),
          EnvDefaultAction(
            isDefault: value == null,
            onReset: () => widget.onChanged(null),
          ),
        ],
      ),
    );
  }
}

/// A nullable number field. An empty field *is* the absent value, so clearing it
/// and pressing the reset do the same thing — both are offered because only one
/// of them is discoverable.
class PolicyNumber extends StatefulWidget {
  const PolicyNumber({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
    this.suffix,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String? helper;
  final String? suffix;

  @override
  State<PolicyNumber> createState() => _PolicyNumberState();
}

class _PolicyNumberState extends State<PolicyNumber> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value?.toString() ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      widget.onChanged(null);
      return;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed != null) widget.onChanged(parsed < 0 ? 0 : parsed);
  }

  void _reset() {
    _controller.clear();
    widget.onChanged(null);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(fontSize: 14, color: AppColors.ink),
            decoration: adminInputDecoration(
              context,
              label: widget.label,
              helper: widget.helper,
              suffix: widget.suffix,
            ),
            onChanged: (raw) {
              _onChanged(raw);
              // The reset affordance appears and disappears with the value.
              setState(() {});
            },
          ),
          EnvDefaultAction(
            isDefault: _controller.text.trim().isEmpty,
            onReset: _reset,
          ),
        ],
      ),
    );
  }
}

/// A nullable text field (a currency code, a privacy notice). Same rule: empty
/// means absent.
class PolicyText extends StatefulWidget {
  const PolicyText({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
    this.hint,
    this.maxLines = 1,
    this.maxLength,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? helper;
  final String? hint;
  final int maxLines;
  final int? maxLength;

  @override
  State<PolicyText> createState() => _PolicyTextState();
}

class _PolicyTextState extends State<PolicyText> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    _controller.clear();
    widget.onChanged(null);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            maxLines: widget.maxLines,
            maxLength: widget.maxLength,
            style: TextStyle(fontSize: 14, color: AppColors.ink),
            decoration: adminInputDecoration(
              context,
              label: widget.label,
              helper: widget.helper,
              hint: widget.hint,
            ),
            onChanged: (raw) {
              final trimmed = raw.trim();
              widget.onChanged(trimmed.isEmpty ? null : trimmed);
              setState(() {});
            },
          ),
          EnvDefaultAction(
            isDefault: _controller.text.trim().isEmpty,
            onReset: _reset,
          ),
        ],
      ),
    );
  }
}

/// A read-only field that opens a picker — the shared shell for [PolicyChoice]
/// and [PolicyDate], so a choice and a date read as the same kind of control.
class _TapField extends StatelessWidget {
  const _TapField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onTap,
    required this.icon,
    required this.muted,
    this.helper,
  });

  final GlobalKey fieldKey;
  final String label;
  final String value;
  final VoidCallback onTap;
  final IconData icon;
  final bool muted;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: fieldKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InputDecorator(
        decoration: adminInputDecoration(
          context,
          label: label,
          helper: helper,
        ).copyWith(floatingLabelBehavior: FloatingLabelBehavior.always),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: muted ? AppTheme.fontMono : null,
                  color: muted ? AppColors.inkSoft : AppColors.ink,
                ),
              ),
            ),
            Icon(icon, size: 16, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _OptionLabel extends StatelessWidget {
  const _OptionLabel({required this.text, this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontFamily: muted ? AppTheme.fontMono : null,
      color: muted ? AppColors.inkSoft : AppColors.ink,
    ),
  );
}

/// The on-screen rectangle of a field, so a picker can be anchored beside it on
/// a wide window instead of taking over the screen.
Rect? anchorRectOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
