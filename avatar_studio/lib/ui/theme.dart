// Цвета и тема студии: индиго-акцент, светлая и тёмная.
import 'package:flutter/material.dart';

class SC extends ThemeExtension<SC> {
  final Color bg, panel, panel2, ink, mut, line, accent, accent2, onAccent, stage, grid, warn, ok;
  const SC({required this.bg, required this.panel, required this.panel2, required this.ink, required this.mut, required this.line, required this.accent, required this.accent2, required this.onAccent, required this.stage, required this.grid, required this.warn, required this.ok});

  static const light = SC(
    bg: Color(0xFFF3F4FA), panel: Color(0xFFFFFFFF), panel2: Color(0xFFEEF0FB), ink: Color(0xFF12195C), mut: Color(0xFF6E7AA8),
    line: Color(0xFFE3E6F3), accent: Color(0xFF5560E0), accent2: Color(0xFFE8EAFD), onAccent: Color(0xFFFFFFFF), stage: Color(0xFFE7EAF8),
    grid: Color(0xFFD8DDF2), warn: Color(0xFFE08A1E), ok: Color(0xFF1E9E6A));
  static const dark = SC(
    bg: Color(0xFF0C0E17), panel: Color(0xFF171A29), panel2: Color(0xFF20243A), ink: Color(0xFFE8EAFA), mut: Color(0xFF8F99C7),
    line: Color(0x14FFFFFF), accent: Color(0xFF7F88F2), accent2: Color(0xFF262B4D), onAccent: Color(0xFF0C0E17), stage: Color(0xFF12152A),
    grid: Color(0xFF1D2140), warn: Color(0xFFF0A546), ok: Color(0xFF43C793));

  @override
  SC copyWith() => this;
  @override
  SC lerp(ThemeExtension<SC>? other, double t) => this;
}

SC sc(BuildContext c) => Theme.of(c).extension<SC>()!;

ThemeData buildTheme(Brightness b) {
  final k = b == Brightness.dark ? SC.dark : SC.light;
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    scaffoldBackgroundColor: k.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: k.accent, brightness: b).copyWith(primary: k.accent, surface: k.panel, onSurface: k.ink),
    textTheme: Typography.material2021().black.apply(bodyColor: k.ink, displayColor: k.ink).copyWith(),
    sliderTheme: SliderThemeData(activeTrackColor: k.accent, thumbColor: k.accent, inactiveTrackColor: k.panel2, trackHeight: 4, overlayShape: SliderComponentShape.noOverlay),
    dividerColor: k.line,
    extensions: [k],
  );
}
