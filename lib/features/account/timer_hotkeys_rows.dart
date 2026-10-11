import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:system_hotkeys/system_hotkeys.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/timer_surfaces/adapters/global_hotkeys_surface.dart';
import '../../core/timer_surfaces/hotkey_rules.dart';
import '../../core/timer_surfaces/surface_platform.dart';
import '../../core/timer_surfaces/timer_surface_prefs.dart';
import '../sprint/modals/glass_modal.dart'
    show anchorRectOfContext, showGlassAnchoredPopover;
import '../time/hotkey_label.dart';
import 'account_widgets.dart';

/// The two system-wide shortcuts under their master switch: each with its
/// combination, what the system answered for it, and a way to change it; and
/// a check that a press really arrives.
///
/// The system's answer is shown as it is: a conflict the person can fix here
/// rather than a shortcut that silently does nothing. Windows reports any
/// combination another app holds; a Mac only the system's own, which is what
/// the check below is for.
class TimerHotkeysRows extends StatelessWidget {
  const TimerHotkeysRows({
    super.key,
    required this.prefs,
    required this.platform,
    this.stack = false,
  });

  final TimerSurfacePrefsCubit prefs;
  final SurfacePlatform platform;
  final bool stack;

  @override
  Widget build(BuildContext context) {
    final state = prefs.state;
    final status = context.read<HotkeyStatus>();
    final divider = Divider(height: 1, color: AppColors.hairline2);
    return ValueListenableBuilder<Map<String, HotKeyResult>>(
      valueListenable: status.results,
      builder: (context, results, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HotkeyRow(
            label: context.t('account.timerSurfaces.hotkeyToggle'),
            icon: LucideIcons.squarePower,
            hotKey: state.toggleHotkey,
            result: results[GlobalHotkeysSurface.toggleId],
            platform: platform,
            stack: stack,
            onChanged: (hotKey) =>
                prefs.update(prefs.state.copyWith(toggleHotkey: hotKey)),
          ),
          divider,
          _HotkeyRow(
            label: context.t('account.timerSurfaces.hotkeyFocus'),
            icon: LucideIcons.target,
            hotKey: state.focusHotkey,
            result: results[GlobalHotkeysSurface.focusId],
            platform: platform,
            stack: stack,
            onChanged: (hotKey) =>
                prefs.update(prefs.state.copyWith(focusHotkey: hotKey)),
          ),
          divider,
          _SelfTestRow(
            status: status,
            hotKeys: [?state.toggleHotkey, ?state.focusHotkey],
            platform: platform,
            stack: stack,
          ),
        ],
      ),
    );
  }
}

class _HotkeyRow extends StatelessWidget {
  const _HotkeyRow({
    required this.label,
    required this.icon,
    required this.hotKey,
    required this.result,
    required this.platform,
    required this.stack,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final HotKey? hotKey;
  final HotKeyResult? result;
  final SurfacePlatform platform;
  final bool stack;
  final ValueChanged<HotKey> onChanged;

  @override
  Widget build(BuildContext context) {
    final combo = hotKey;
    final status = switch (result) {
      HotKeyResult.bound => 'account.timerSurfaces.hotkeyBound',
      HotKeyResult.conflict => 'account.timerSurfaces.hotkeyConflict',
      HotKeyResult.unsupported => 'account.timerSurfaces.hotkeyUnsupported',
      null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingRow(
          label: label,
          description: status == null || result == HotKeyResult.conflict
              ? null
              : context.t(status),
          icon: icon,
          stack: stack,
          trailing: Builder(
            builder: (buttonContext) => AccountActionButton(
              label: combo == null
                  ? context.t('account.timerSurfaces.hotkeyChoose')
                  : hotkeyLabel(combo, platform, names: keyNames(context)),
              icon: LucideIcons.keyboard,
              onPressed: () => unawaited(_record(buttonContext)),
            ),
          ),
        ),
        if (result == HotKeyResult.conflict)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AccountNote(
              text: context.t(status!),
              icon: LucideIcons.triangleAlert,
            ),
          ),
      ],
    );
  }

  Future<void> _record(BuildContext buttonContext) async {
    final anchor = anchorRectOfContext(buttonContext);
    if (anchor == null) return;
    final chosen = await showGlassAnchoredPopover<HotKey>(
      buttonContext,
      anchorRect: anchor,
      width: 320,
      minHeight: 170,
      builder: (context) => HotkeyRecorder(platform: platform),
    );
    if (chosen != null) onChanged(chosen);
  }
}

/// Listens for one key combination and hands it back.
///
/// A combination needs a modifier: a bare key would be taken from every app on
/// the system. Escape alone cancels; modifier keys on their own are waited
/// past, so the person can press them first.
class HotkeyRecorder extends StatefulWidget {
  const HotkeyRecorder({super.key, required this.platform});

  final SurfacePlatform platform;

  @override
  State<HotkeyRecorder> createState() => _HotkeyRecorderState();
}

class _HotkeyRecorderState extends State<HotkeyRecorder> {
  final FocusNode _focus = FocusNode(debugLabel: 'hotkey-recorder');
  String? _problem;

  bool get _mac => widget.platform == SurfacePlatform.macos;

  static final _modifierKeys = {
    PhysicalKeyboardKey.controlLeft,
    PhysicalKeyboardKey.controlRight,
    PhysicalKeyboardKey.altLeft,
    PhysicalKeyboardKey.altRight,
    PhysicalKeyboardKey.shiftLeft,
    PhysicalKeyboardKey.shiftRight,
    PhysicalKeyboardKey.metaLeft,
    PhysicalKeyboardKey.metaRight,
    PhysicalKeyboardKey.fn,
    PhysicalKeyboardKey.capsLock,
  };

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final key = event.physicalKey;
    if (_modifierKeys.contains(key)) return KeyEventResult.handled;
    final keyboard = HardwareKeyboard.instance;
    final modifiers = {
      if (keyboard.isControlPressed) HotKeyModifier.control,
      if (keyboard.isAltPressed) HotKeyModifier.alt,
      if (keyboard.isShiftPressed) HotKeyModifier.shift,
      if (keyboard.isMetaPressed) HotKeyModifier.meta,
    };
    if (modifiers.isEmpty && key == PhysicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    final hotKey = HotKey(key: key, modifiers: modifiers);
    final problem = !HotKey.isSupportedKey(key)
        ? 'account.timerSurfaces.recordUnsupportedKey'
        : !isSafeHotkey(hotKey, widget.platform)
        ? _mac
              ? 'account.timerSurfaces.recordNeedsModifierMac'
              : 'account.timerSurfaces.recordNeedsModifier'
        : null;
    if (problem != null) {
      setState(() => _problem = problem);
      return KeyEventResult.handled;
    }
    Navigator.of(context).pop(hotKey);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final example = hotkeyLabel(
      TimerSurfacePrefs.defaultToggleHotkey(widget.platform),
      widget.platform,
      names: keyNames(context),
    );
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                context.t('account.timerSurfaces.recordPrompt'),
                style: TextStyle(
                  fontSize: AppType.body,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              problem == null
                  ? context.t(
                      _mac
                          ? 'account.timerSurfaces.recordHintMac'
                          : 'account.timerSurfaces.recordHint',
                      variables: {'example': example},
                    )
                  : context.t(problem),
              style: TextStyle(
                fontSize: AppType.label,
                color: problem == null ? AppColors.inkSoft : AppColors.danger,
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.t('common.cancel')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Press it now": the one proof that a shortcut arrives, also from another
/// app in front. On a Mac the system cannot say whether another app holds a
/// combination; this can. Either shortcut counts, and the check names nothing
/// more than that one arrived.
class _SelfTestRow extends StatefulWidget {
  const _SelfTestRow({
    required this.status,
    required this.hotKeys,
    required this.platform,
    required this.stack,
  });

  final HotkeyStatus status;
  final List<HotKey> hotKeys;
  final SurfacePlatform platform;
  final bool stack;

  @override
  State<_SelfTestRow> createState() => _SelfTestRowState();
}

enum _Test { idle, waiting, worked, silent }

class _SelfTestRowState extends State<_SelfTestRow> {
  _Test _test = _Test.idle;
  Timer? _timeout;
  ({String id, int count})? _before;

  static const _window = Duration(seconds: 15);

  HotkeyStatus get _status => widget.status;

  void _start() {
    _before = _status.lastPress.value;
    _status.selfTest.value = true;
    _status.lastPress.addListener(_pressed);
    _timeout?.cancel();
    _timeout = Timer(_window, () => _finish(_Test.silent));
    setState(() => _test = _Test.waiting);
  }

  void _pressed() {
    final press = _status.lastPress.value;
    if (press != null && press != _before) _finish(_Test.worked);
  }

  /// Stops listening and lets presses act again; shared by the end of the
  /// check and by leaving the page in the middle of it.
  void _stopListening() {
    _timeout?.cancel();
    _status.lastPress.removeListener(_pressed);
    _status.selfTest.value = false;
  }

  void _finish(_Test result) {
    _stopListening();
    if (mounted) setState(() => _test = result);
  }

  @override
  void dispose() {
    if (_test == _Test.waiting) _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = keyNames(context);
    final combos = widget.hotKeys
        .map((k) => hotkeyLabel(k, widget.platform, names: names))
        .join(' / ');
    final note = switch (_test) {
      _Test.idle => null,
      _Test.waiting => (
        context.t(
          'account.timerSurfaces.testWaiting',
          variables: {'combo': combos},
        ),
        LucideIcons.keyboard,
        AccountNoteTone.info,
      ),
      _Test.worked => (
        context.t('account.timerSurfaces.testWorked'),
        LucideIcons.circleCheck,
        AccountNoteTone.info,
      ),
      _Test.silent => (
        context.t('account.timerSurfaces.testSilent'),
        LucideIcons.triangleAlert,
        AccountNoteTone.warn,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingRow(
          label: context.t('account.timerSurfaces.test'),
          description: context.t('account.timerSurfaces.testHint'),
          icon: LucideIcons.badgeCheck,
          stack: widget.stack,
          trailing: AccountActionButton(
            label: context.t('account.timerSurfaces.testButton'),
            icon: LucideIcons.play,
            onPressed: widget.hotKeys.isEmpty || _test == _Test.waiting
                ? null
                : _start,
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              liveRegion: true,
              child: AccountNote(text: note.$1, icon: note.$2, tone: note.$3),
            ),
          ),
      ],
    );
  }
}

/// The modifier names in the reader's language.
KeyNames keyNames(BuildContext context) => KeyNames(
  ctrl: context.t('account.timerSurfaces.key.ctrl'),
  alt: context.t('account.timerSurfaces.key.alt'),
  shift: context.t('account.timerSurfaces.key.shift'),
  win: context.t('account.timerSurfaces.key.win'),
  space: context.t('account.timerSurfaces.keySpace'),
);
