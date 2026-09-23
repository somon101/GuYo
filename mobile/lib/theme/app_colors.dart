import 'package:flutter/material.dart';

/// A small set of named design tokens for the "Уроки" screen's visual
/// reference (see lessons_screen.dart/lesson_detail_screen.dart), shared
/// with the bottom navigation (home_screen.dart) so the same accent color
/// is used consistently in both places rather than each picking its own
/// shade of indigo. Deliberately NOT swapped in as the app's global
/// ColorScheme seed -- this only restyles these specific screens, nothing
/// else changes color.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF5862DD);
  static const Color primaryDark = Color(0xFF101B63);
  static const Color secondaryText = Color(0xFF7180B0);
  static const Color success = Color(0xFF0A9C5D);
  static const Color successLight = Color(0xFFE8F8F1);
}
