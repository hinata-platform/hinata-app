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

/// "Recorded, not yet acted on."
///
/// A policy screen that describes a rule in the present indicative is a promise.
/// Most of these rules are stored by this stage and enforced by a later one, and
/// an administrator who sets a lock date to freeze a closed payroll period —
/// because an auditor or a works agreement asked for it — would otherwise get a
/// green toast and no lock at all. Nothing about that failure is visible until
/// somebody edits a frozen entry.
///
/// Each stage that implements a policy drops this from the controls it took
/// over, and the note disappears on its own.
class PendingNote extends StatelessWidget {
  const PendingNote({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: AdminNote(
      icon: LucideIcons.hourglass,
      text: context.t('admin.timeTracking.notYetEnforced'),
    ),
  );
}

/// The badge that stands where a control would be while the value is absent.
///
/// It deliberately does not draw a switch in some arbitrary position — that
/// would say "off" where the truth is "whatever this deployment decided". What
/// it does say is what the deployment decided: the server sends the resolved
/// value alongside the stored one, so the badge reads "Env: On" rather than
/// leaving the operator to guess. Tapping it commits an explicit value, which
/// is the only way a control can honestly appear.
class _EnvDefaultBadge extends StatelessWidget {
  const _EnvDefaultBadge({required this.onTap, this.effective});

  final VoidCallback onTap;

  /// What the environment currently resolves this policy to, already localized.
  /// Null when the server did not say — an older server, or a value that has no
  /// short rendering.
  final String? effective;

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
              effective == null
                  ? context.t('admin.timeTracking.envDefault')
                  : '${context.t('admin.timeTracking.envDefault')}: $effective',
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
    this.pending = false,
  });

  final String title;
  final String description;
  final Widget control;
  final bool isDefault;
  final VoidCallback onReset;
  final bool monitoring;
  final bool pending;

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
          if (pending) const PendingNote(),
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
    this.pending = false,
    this.effective,
  });

  final String title;
  final String description;

  /// Null means the value is absent — the environment default applies.
  final bool? value;
  final ValueChanged<bool?> onChanged;

  /// Whether this policy makes one person's time legible to another, and so
  /// carries the co-determination note.
  final bool monitoring;

  /// Whether the policy is recorded but not yet acted on — see [PendingNote].
  final bool pending;

  /// What the environment resolves this policy to while nothing is stored.
  final bool? effective;

  @override
  Widget build(BuildContext context) {
    final current = value;
    return _PolicyRow(
      title: title,
      description: description,
      isDefault: current == null,
      onReset: () => onChanged(null),
      monitoring: monitoring,
      pending: pending,
      control: current == null
          ? _EnvDefaultBadge(
              // Commits what is already in force, not its opposite. The tap
              // exists to make the switch appear, not to change the policy —
              // and on a monitoring-capable switch a tap that silently turned
              // something on would be the worst possible reading of it.
              onTap: () => onChanged(effective ?? false),
              effective: effective == null
                  ? null
                  : context.t(effective! ? 'admin.stateOn' : 'admin.stateOff'),
            )
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
    this.pending = false,
    this.effective,
  });

  final String label;

  /// The stored wire value, or null for "environment decides".
  final String? value;

  /// Wire value → the i18n key naming it.
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;
  final String? helper;

  /// Recorded but not yet acted on — see [PendingNote].
  final bool pending;

  /// The option the environment resolves to while nothing is stored, so the
  /// placeholder can name it instead of saying only "Env default".
  final String? effective;

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
    final stored = widget.value;
    // A stored value the option list does not offer used to render exactly like
    // "nothing is stored", so the field said "Env default" while the reset
    // button beside it offered to clear a value — two statements contradicting
    // each other, over a value the operator then could not choose again.
    assert(
      stored == null || widget.options.containsKey(stored),
      'PolicyChoice "${widget.label}" holds "$stored", which is not one of '
      '${widget.options.keys.toList()} — the option list has fallen behind the '
      'server enum and the value cannot be selected again.',
    );
    final labelKey = stored == null ? null : widget.options[stored];
    final effectiveKey = widget.effective == null
        ? null
        : widget.options[widget.effective];
    final envLabel = effectiveKey == null
        ? context.t('admin.timeTracking.envDefault')
        : '${context.t('admin.timeTracking.envDefault')}: '
              '${context.t(effectiveKey)}';
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
            // A stored value we cannot name is shown raw rather than disguised
            // as the default — in release, where the assert above is off.
            value: stored == null ? envLabel : context.t(labelKey ?? stored),
            muted: stored == null,
            icon: LucideIcons.chevronDown,
          ),
          if (widget.pending) const PendingNote(),
          EnvDefaultAction(
            isDefault: stored == null,
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
    this.pending = false,
  });

  final String label;

  /// ISO `yyyy-MM-dd`, or null for "environment decides".
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? helper;

  /// Recorded but not yet acted on — see [PendingNote].
  final bool pending;

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
          if (widget.pending) const PendingNote(),
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
    this.pending = false,
    this.maxValue,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String? helper;

  /// Recorded but not yet acted on — see [PendingNote].
  final bool pending;
  final String? suffix;

  /// The largest value the server will store. Clamped here so the operator
  /// is not told about it by a failed save of an unrelated section.
  final int? maxValue;

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
    // digitsOnly on the field already rules out a minus sign, so there is no
    // floor to apply here — a second guard would only suggest one was needed.
    // The ceiling is real: the server refuses anything above it, and without
    // this the operator finds that out as a validation error on a save that
    // touched five other sections.
    final parsed = int.tryParse(trimmed);
    if (parsed == null) return;
    final max = widget.maxValue;
    if (max != null && parsed > max) {
      // Write the clamped value back into the field as well. Clamping only the
      // document would leave the screen showing 5000 over a stored 1200, and
      // the save would succeed — the same "what you were told is not what was
      // recorded" this screen spent the round removing.
      _controller.value = TextEditingValue(
        text: '$max',
        selection: TextSelection.collapsed(offset: '$max'.length),
      );
      widget.onChanged(max);
      return;
    }
    widget.onChanged(parsed);
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
          if (widget.pending) const PendingNote(),
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
    this.pending = false,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? helper;

  /// Recorded but not yet acted on — see [PendingNote].
  final bool pending;
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
          if (widget.pending) const PendingNote(),
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
