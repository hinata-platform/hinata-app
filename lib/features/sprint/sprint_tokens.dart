import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Single source of truth for the sprint feature's accent colours — mirrors
/// `Design/sprints/sprint.css` (point buckets, capacity-bar segments, glass
/// header). Theme-aware where it matters so dark mode stays legible.
abstract final class SprintTokens {
  // Point-bucket / capacity-bar segment colours (todo · in-progress · done).
  static const todo = AppColors.stBacklog; // indigo-grey, hue 255
  static const progress = AppColors.accent; // honey
  static const done = Color(0xFF34A878); // oklch(0.66 0.13 155)
  static const over = AppColors.danger;

  /// Fibonacci planning-poker scale.
  static const fib = <int>[1, 2, 3, 5, 8, 13, 21];

  /// Pale honey/indigo wash behind the active-sprint glass header.
  static List<Color> headerTint(Brightness b) => b == Brightness.dark
      ? const [Color(0xCC201E38), Color(0x99181630)]
      : const [Color(0xB8FFFFFF), Color(0x6BFFFFFF)];
}
