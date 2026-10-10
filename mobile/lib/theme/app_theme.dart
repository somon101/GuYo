import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../l10n/l10n.dart';
import 'app_colors.dart';

/// Светлая / тёмная / как в системе -- chosen in Настройки, kept on the
/// device. [appThemeChoice] changing rebuilds the app with AppColors.dark
/// set to match (see main.dart).
final ValueNotifier<String> appThemeChoice = ValueNotifier('system');

List<({String code, String label})> get themeChoices => [
      (code: 'system', label: tr('Как в системе')),
      (code: 'light', label: tr('Светлая')),
      (code: 'dark', label: tr('Тёмная')),
    ];

const _storage = FlutterSecureStorage();
const _key = 'guyo_theme';

Future<void> loadAppTheme() async {
  try {
    final saved = await _storage.read(key: _key);
    if (saved == 'light' || saved == 'dark' || saved == 'system') appThemeChoice.value = saved!;
  } catch (_) {}
  applyAppTheme();
}

Future<void> setAppTheme(String code) async {
  appThemeChoice.value = code;
  applyAppTheme();
  try {
    await _storage.write(key: _key, value: code);
  } catch (_) {}
}

/// Sets AppColors.dark from the choice (and, for "system", the phone's
/// current setting). Returns whether it changed.
bool applyAppTheme() {
  final system = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  final dark = switch (appThemeChoice.value) {
    'dark' => true,
    'light' => false,
    _ => system,
  };
  final changed = dark != AppColors.dark;
  AppColors.dark = dark;
  return changed;
}

/// Material's own widgets (dialogs, sheets, fields, menus) in the palette.
ThemeData buildAppTheme() {
  final dark = AppColors.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.indigo,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: dark ? scheme.copyWith(surface: AppColors.surface, primary: AppColors.primary) : scheme,
    scaffoldBackgroundColor: dark ? AppColors.canvas : null,
    dialogTheme: dark ? DialogThemeData(backgroundColor: AppColors.surface) : null,
    bottomSheetTheme: dark ? BottomSheetThemeData(backgroundColor: AppColors.surface) : null,
    appBarTheme: dark
        ? AppBarTheme(backgroundColor: AppColors.canvas, foregroundColor: AppColors.primaryDark, surfaceTintColor: Colors.transparent)
        : null,
  );
}
