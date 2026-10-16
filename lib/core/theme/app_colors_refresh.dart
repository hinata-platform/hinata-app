import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/theme_cubit.dart';
import '../blocs/tint_cubit.dart';

/// Rebuilds the whole tree when light and dark switch or the tint changes.
///
/// The app's colours come from the `AppColors` getters, which read a static
/// brightness and register no dependency. A widget that reads them rebuilds
/// only when something above it hands it a new instance; a `const` subtree
/// gets the same instance back and Flutter skips it. So a switch to dark left
/// such subtrees (the settings cards among them) painted light until they
/// happened to rebuild for another reason.
///
/// Listens to the [ThemeCubit], the [TintCubit] and the platform's
/// brightness, and on a
/// change marks every element for a rebuild before the next frame. That
/// frame builds from the top down, so `MaterialApp.builder` sets the new
/// brightness before any of them reads it. One full rebuild per switch, the
/// cost of a hot reload, and only when the switch happens.
class AppColorsRefresh extends StatefulWidget {
  const AppColorsRefresh({super.key, required this.child});

  final Widget child;

  @override
  State<AppColorsRefresh> createState() => _AppColorsRefreshState();
}

class _AppColorsRefreshState extends State<AppColorsRefresh>
    with WidgetsBindingObserver {
  late final ThemeCubit _theme = context.read<ThemeCubit>();
  late final TintCubit _tint = context.read<TintCubit>();
  StreamSubscription<ThemeMode>? _modes;
  StreamSubscription<TintState>? _tints;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _modes = _theme.stream.listen((_) => rebuildAllElements());
    // A new palette only: equal states are not emitted, and the palette is
    // a function of the preferences.
    _tints = _tint.stream.listen((_) => rebuildAllElements());
  }

  @override
  void didChangePlatformBrightness() {
    // Only the system mode follows the platform; the others stay put.
    if (_theme.state == ThemeMode.system) rebuildAllElements();
  }

  @override
  void dispose() {
    _modes?.cancel();
    _tints?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Marks every element in the app for a rebuild. Call it outside a build:
/// from a listener, never from `build` itself.
void rebuildAllElements() {
  void mark(Element element) {
    element.markNeedsBuild();
    element.visitChildren(mark);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(mark);
}
