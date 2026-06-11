import 'package:flutter/material.dart';

/// Design tokens derived from the Hivora base design (pastel glassmorphism).
abstract final class AppColors {
  // Brand
  static const navy = Color(0xFF2D2B55);
  static const navyDark = Color(0xFF1E1C3A);
  static const lavender = Color(0xFFAEA7F0);

  // Surfaces
  static const background = Color(0xFFF2F1F8);
  static const backgroundEnd = Color(0xFFE9E4F1);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF7F6FB);

  // Pastel card palette (rotating accents, like the "Today Task" cards)
  static const pastelBlue = Color(0xFFC9DCF5);
  static const pastelLavender = Color(0xFFDCD6F7);
  static const pastelPeach = Color(0xFFF8CDB8);
  static const pastelMint = Color(0xFFCBEAD9);

  // Accents
  static const accentOrange = Color(0xFFE8836B);
  static const accentPurple = Color(0xFF9B8CF0);
  static const accentBlue = Color(0xFF6FA8DC);
  static const accentTeal = Color(0xFFA8CDC4);

  // Text
  static const textPrimary = Color(0xFF2B2950);
  static const textSecondary = Color(0xFF8C8AA7);
  static const textOnDark = Color(0xFFFFFFFF);

  // Semantic
  static const success = Color(0xFF4CAF85);
  static const warning = Color(0xFFE8B26B);
  static const danger = Color(0xFFD9534F);

  static const pastels = [pastelBlue, pastelLavender, pastelPeach, pastelMint];

  static Color pastelFor(int index) => pastels[index % pastels.length];
}
