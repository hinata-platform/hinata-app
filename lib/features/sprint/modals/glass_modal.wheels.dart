part of 'glass_modal.dart';

/// Height of one row of a [_GlassWheel].
const double _kWheelExtent = 40;

/// How far a mouse wheel has to turn before the wheel moves a row. One notch
/// of an ordinary mouse arrives as twenty pixels or more, depending on the
/// platform; the fine deltas of a precise device add up to it.
const double _kWheelNotch = 16;

/// The wheel every picker here is built from: a fixed-extent list on glass,
/// with the selected row lit rather than boxed.
///
/// **It takes its own input.** The list underneath is only drawn; every way of
/// moving it is handled here, because the list's own scrolling answered none
/// of them well. On a desktop a mouse is no drag device, so pulling the wheel
/// did nothing, and its scroll physics snapped every notch of a mouse wheel
/// that moved it less than half a row straight back — the wheel looked stuck
/// to anyone without a touch screen. Here a drag moves it with any pointer
/// (finger, mouse, pen, trackpad), a mouse wheel moves it a row per notch,
/// tapping a row goes to that row, and the arrow keys step it once it has
/// focus.
class _GlassWheel extends StatefulWidget {
  const _GlassWheel({
    required this.count,
    required this.index,
    required this.label,
    required this.onChanged,
    this.semanticsLabel,
  });

  final int count;

  /// The selected row. Controlled, not merely initial: a picker that sets its
  /// value from somewhere other than this wheel — a typed value, a preset, or
  /// the meridiem wheel moving the hour — has to be able to move it.
  final int index;

  /// What row [index] reads as — already formatted, because an hour is written
  /// differently from a minute and from a count of hours.
  final String Function(int index) label;
  final ValueChanged<int> onChanged;
  final String? semanticsLabel;

  @override
  State<_GlassWheel> createState() => _GlassWheelState();
}

class _GlassWheelState extends State<_GlassWheel> {
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: widget.index);
  final FocusNode _focus = FocusNode(debugLabel: 'glass-wheel');
  late int _selected = widget.index;

  /// Where the wheel is headed while an animation runs. Steps that arrive
  /// faster than a row takes to settle — a spun mouse wheel, a held arrow key —
  /// count from here, not from the row the animation has not reached yet.
  ///
  /// While it is set the rows the wheel passes on its way are drawn but not
  /// reported: the value is the target, said once. Reporting each passing
  /// row fed them back as new values — typing `0` for nine o'clock sent the
  /// hour wheel from 23 down through every hour, each one rewriting the field
  /// the person was still typing in.
  int? _heading;

  /// What a precise scroll device has turned but not yet made a row of.
  double _carry = 0;

  /// Whether the focus ring shows: only for focus that came from the keyboard.
  /// A wheel somebody just grabbed with the mouse knows where it is.
  bool _ring = false;

  /// Set just before a pointer takes the focus, so the ring stays off for it.
  bool _pointerFocus = false;

  double get _maxOffset => (widget.count - 1) * _kWheelExtent;

  @override
  void didUpdateWidget(covariant _GlassWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when the value moved from outside. A change this wheel just reported
    // comes back as the same index, and animating to where we already are
    // would fight the pointer that is still on it.
    // Compared with where the wheel is going, not where it is: mid-way through
    // a turn it passes rows it will not stop on.
    if (widget.index != (_heading ?? _selected)) _goTo(widget.index);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _selected) return;
    setState(() => _selected = index);
    if (_heading == null) widget.onChanged(index);
  }

  /// Turns the wheel to [index]; [report] says the new value to the picker,
  /// which a move that came *from* the picker must not.
  void _goTo(int index, {bool report = false}) {
    final target = index.clamp(0, widget.count - 1);
    _heading = target;
    if (report && target != widget.index) widget.onChanged(target);
    if (!_controller.hasClients) return;
    final rows = (target - _controller.offset / _kWheelExtent).abs();
    unawaited(
      _controller
          .animateTo(
            target * _kWheelExtent,
            duration: Duration(
              milliseconds: (120 + 30 * rows).clamp(120, 420).round(),
            ),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (_heading != target || !mounted) return;
            _heading = null;
            if (_selected != target) setState(() => _selected = target);
          }),
    );
  }

  void _step(int rows) => _goTo((_heading ?? _selected) + rows, report: true);

  void _takeFocus() {
    _pointerFocus = true;
    _focus.requestFocus();
  }

  void _dragStart(DragStartDetails _) {
    _heading = null;
    _takeFocus();
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (!_controller.hasClients) return;
    final offset = (_controller.offset - details.delta.dy).clamp(
      0.0,
      _maxOffset,
    );
    _controller.jumpTo(offset);
  }

  /// Settles on a row: where the fling would carry the wheel, a little of it,
  /// rounded to the nearest row — what a wheel of real mass does.
  void _dragEnd(DragEndDetails details) {
    if (!_controller.hasClients) return;
    final velocity = -(details.primaryVelocity ?? 0);
    final projected = _controller.offset + velocity * 0.12;
    _goTo((projected / _kWheelExtent).round(), report: true);
  }

  /// A tap on a row other than the selected one goes to it.
  void _tapUp(TapUpDetails details, double height) {
    _takeFocus();
    final rows = ((details.localPosition.dy - height / 2) / _kWheelExtent)
        .round();
    if (rows != 0) _step(rows);
  }

  void _pointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Registered rather than handled, so a page that scrolls around the modal
    // does not scroll as well: the first to register is the one that gets it.
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      _carry += (resolved as PointerScrollEvent).scrollDelta.dy;
      if (_carry.abs() < _kWheelNotch) return;
      final rows = math.max(1, (_carry.abs() / _kWheelExtent).round());
      _step(_carry.sign.toInt() * rows);
      _carry = 0;
    });
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final int? rows = switch (key) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.pageUp => -5,
      LogicalKeyboardKey.pageDown => 5,
      _ => null,
    };
    if (rows == null) return KeyEventResult.ignored;
    _step(rows);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    const height = 176.0;
    return Semantics(
      label: widget.semanticsLabel,
      value: widget.label(_selected),
      increasedValue: _selected < widget.count - 1
          ? widget.label(_selected + 1)
          : null,
      decreasedValue: _selected > 0 ? widget.label(_selected - 1) : null,
      onIncrease: _selected < widget.count - 1 ? () => _step(1) : null,
      onDecrease: _selected > 0 ? () => _step(-1) : null,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        onFocusChange: (focused) => setState(() {
          _ring = focused && !_pointerFocus;
          _pointerFocus = false;
        }),
        child: Listener(
          onPointerSignal: _pointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: _dragStart,
            onVerticalDragUpdate: _dragUpdate,
            onVerticalDragEnd: _dragEnd,
            onTapUp: (details) => _tapUp(details, height),
            child: DecoratedBox(
              // Where the arrow keys will go, for the one who got here with Tab.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                border: Border.all(
                  color: _ring ? AppColors.accentLine : Colors.transparent,
                ),
              ),
              child: SizedBox(
                height: height,
                // Drawn, not scrolled: the gestures above move it, and a list
                // that answered them as well would move it twice.
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: ListWheelScrollView.useDelegate(
                      controller: _controller,
                      itemExtent: _kWheelExtent,
                      // A gentle curve: the app's glass is flat, and a strongly
                      // barrelled wheel would be the one skeuomorphic surface.
                      diameterRatio: 2.2,
                      perspective: 0.002,
                      physics: const NeverScrollableScrollPhysics(),
                      onSelectedItemChanged: _select,
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: widget.count,
                        builder: (_, index) {
                          final selected = index == _selected;
                          return Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 120),
                              style: TextStyle(
                                fontSize: selected ? 26 : 20,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontFeatures: const [
                                  ui.FontFeature.tabularFigures(),
                                ],
                                color: selected
                                    ? AppColors.ink
                                    : AppColors.inkFaint,
                              ),
                              child: Text(widget.label(index)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The lit band behind the selected row of a set of wheels, and the wheels
/// themselves. Shared so the pickers cannot drift apart visually.
class _WheelRow extends StatelessWidget {
  const _WheelRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The selection band. Behind the wheels and ignoring pointers, so it
          // reads as a highlight on the surface rather than a control.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                // The app's active wash, which resolves against the theme; a
                // navy tint would be a dark band on the dark canvas.
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
              child: const SizedBox(height: 42, width: double.infinity),
            ),
          ),
          Row(children: children),
        ],
      ),
    );
  }
}

/// The separator between two wheels — a colon for a clock time, a gap for a
/// duration (whose units are written on the wheels themselves).
class _WheelSeparator extends StatelessWidget {
  const _WheelSeparator({this.text});

  final String? text;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 18,
    child: text == null
        ? null
        : Text(
            text!,
            textAlign: TextAlign.center,
            // Not const: the ink tokens are theme-aware getters, so a const
            // style would freeze the light-mode colour into the dark theme.
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
            ),
          ),
  );
}

/// Whether a picker should put the caret in its typing field as it opens.
///
/// Where a keyboard is the normal way in. On a phone the keyboard would slide
/// up over the wheels the moment the picker opened, which is the opposite of
/// what somebody reaching for a wheel wants.
bool _typeFirst(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

/// The typing half of a picker: the value as text, read back as it is typed.
///
/// Beside the wheels rather than instead of them. A wheel is how one looks
/// around a value; typing is how one says a value one already knows, and a
/// start time somebody wrote down at nine is faster typed than turned to. The
/// two stay in step both ways: a valid entry moves the wheels as it is typed,
/// and a turned wheel rewrites the field — unless the field already says the
/// same thing in other words, so `930` is not snatched away as `09:30` while
/// the caret is still in it.
class _TypedValueField<T> extends StatefulWidget {
  const _TypedValueField({
    required this.value,
    required this.format,
    required this.parse,
    required this.onChanged,
    required this.hint,
    required this.label,
    required this.onSubmitted,
    required this.incomplete,
    this.inputFormatters = const [],
  });

  final T value;
  final String Function(T value) format;

  /// The value [text] means, or null when it means nothing yet.
  final T? Function(String text) parse;
  final ValueChanged<T> onChanged;

  /// An example in the notation the field reads.
  final String hint;

  /// What the field is for, for a screen reader and the tooltip.
  final String label;

  /// Enter: the picker's own confirm, so a typed value needs no mouse at all.
  final VoidCallback onSubmitted;

  /// Whether [text], which means nothing yet, may still become something —
  /// `93` on its way to `930`. Such a field is not marked wrong while the
  /// person is still typing it.
  final bool Function(String text) incomplete;

  /// Shapes the text as it is typed — the time's colon, for one.
  final List<TextInputFormatter> inputFormatters;

  @override
  State<_TypedValueField<T>> createState() => _TypedValueFieldState<T>();
}

class _TypedValueFieldState<T> extends State<_TypedValueField<T>> {
  late final TextEditingController _text = TextEditingController(
    text: widget.format(widget.value),
  );
  final FocusNode _focus = FocusNode(debugLabel: 'glass-picker-typed');
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_tidyOnLeave);
  }

  @override
  void didUpdateWidget(covariant _TypedValueField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        widget.parse(_text.text) != widget.value) {
      _text.text = widget.format(widget.value);
      _invalid = false;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_tidyOnLeave);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  /// Leaving the field writes the value out in full, or back to what it was
  /// when what was typed never meant anything.
  void _tidyOnLeave() {
    if (_focus.hasFocus) return;
    setState(() {
      _text.text = widget.format(widget.value);
      _invalid = false;
    });
  }

  void _changed(String text) {
    final parsed = widget.parse(text);
    setState(
      () => _invalid =
          parsed == null &&
          text.trim().isNotEmpty &&
          !widget.incomplete(text.trim()),
    );
    if (parsed != null && parsed != widget.value) widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Center(
        child: SizedBox(
          width: 200,
          child: Tooltip(
            message: widget.label,
            child: TextField(
              controller: _text,
              focusNode: _focus,
              autofocus: _typeFirst(context),
              textAlign: TextAlign.center,
              keyboardType: TextInputType.datetime,
              textInputAction: TextInputAction.done,
              inputFormatters: widget.inputFormatters,
              onChanged: _changed,
              onSubmitted: (_) {
                if (widget.parse(_text.text) != null) widget.onSubmitted();
              },
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
                color: AppColors.ink,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.hint,
                prefixIcon: Icon(
                  LucideIcons.keyboard,
                  size: 16,
                  color: AppColors.inkSoft,
                  semanticLabel: widget.label,
                ),
                // The rim goes red rather than a line of text appearing under
                // it: the field is one short line, and a message would push the
                // wheels down on every keystroke that is not yet a time.
                enabledBorder: _invalid
                    ? HiveFieldBorder(
                        borderRadius: GlassFieldStyle.radius,
                        borderSide: const BorderSide(color: AppColors.danger),
                      )
                    : null,
                focusedBorder: _invalid
                    ? HiveFieldBorder(
                        borderRadius: GlassFieldStyle.radius,
                        borderSide: const BorderSide(
                          color: AppColors.danger,
                          width: 1.5,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hour and minute wheels, the meridiem wheel when the locale wants one,
/// and the field to type the time instead.
///
/// One widget rather than a pair per picker: a modal that shows "2:30 PM" in
/// its header and then offers a 00–23 wheel underneath is a modal that was
/// written twice, and only one of the two copies knew about twelve-hour
/// locales.
class _TimeWheels extends StatelessWidget {
  const _TimeWheels({
    required this.value,
    required this.use24,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TimeOfDay value;
  final bool use24;
  final ValueChanged<TimeOfDay> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    String format(TimeOfDay time) =>
        localizations.formatTimeOfDay(time, alwaysUse24HourFormat: use24);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TypedValueField<TimeOfDay>(
          value: value,
          format: format,
          parse: (text) {
            // `09:` and `09:3` are a time being typed, not nine o'clock and
            // three minutes past; the wheels wait for the second digit.
            if (RegExp(r'^\d{2}:\d?$').hasMatch(text.trim())) return null;
            final parsed = parseTimeInput(
              text,
              meridiems: (
                am: localizations.anteMeridiemAbbreviation,
                pm: localizations.postMeridiemAbbreviation,
              ),
            );
            return parsed == null
                ? null
                : TimeOfDay(hour: parsed.hour, minute: parsed.minute);
          },
          onChanged: onChanged,
          hint: format(const TimeOfDay(hour: 9, minute: 30)),
          label: context.t('common.picker.typeTime'),
          onSubmitted: onSubmitted,
          // Up to three digits, or a separator waiting for its minutes.
          incomplete: (text) =>
              RegExp(r'^\d{1,3}$').hasMatch(text) ||
              RegExp(r'^\d{1,2}[:.h]\d?$').hasMatch(text),
          // The shape is a 24-hour one; a twelve-hour field takes its
          // meridiem as typed and is read as a whole.
          inputFormatters: use24 ? const [TimeInputFormatter()] : const [],
        ),
        const SizedBox(height: 8),
        _WheelRow(
          children: [
            Expanded(
              child: _GlassWheel(
                count: use24 ? 24 : 12,
                index: use24 ? value.hour : value.hour % 12,
                semanticsLabel: localizations.timePickerHourLabel,
                label: (index) => use24
                    ? index.toString().padLeft(2, '0')
                    : (index == 0 ? 12 : index).toString(),
                onChanged: (index) => onChanged(
                  TimeOfDay(
                    // Keep the half of the day the meridiem wheel is showing.
                    hour: use24
                        ? index
                        : (index % 12) + (value.hour >= 12 ? 12 : 0),
                    minute: value.minute,
                  ),
                ),
              ),
            ),
            const _WheelSeparator(text: ':'),
            Expanded(
              child: _GlassWheel(
                count: 60,
                index: value.minute,
                semanticsLabel: localizations.timePickerMinuteLabel,
                label: (index) => index.toString().padLeft(2, '0'),
                onChanged: (index) =>
                    onChanged(TimeOfDay(hour: value.hour, minute: index)),
              ),
            ),
            if (!use24) ...[
              const _WheelSeparator(),
              Expanded(
                child: _GlassWheel(
                  count: 2,
                  index: value.hour >= 12 ? 1 : 0,
                  label: (index) => index == 0
                      ? localizations.anteMeridiemAbbreviation
                      : localizations.postMeridiemAbbreviation,
                  onChanged: (index) => onChanged(
                    TimeOfDay(
                      hour: (value.hour % 12) + (index == 1 ? 12 : 0),
                      minute: value.minute,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
