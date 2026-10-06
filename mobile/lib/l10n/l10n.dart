import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'strings.dart';

/// The interface language: "ru", "tg" or "uz". Every interface string is
/// written in Russian in the code and wrapped in [tr], which looks up its
/// Tajik or Uzbek version in [uiStrings]. The app root rebuilds from
/// scratch when this changes (see main.dart), so no screen keeps old text.
///
/// The server keeps the same choice on the user (`ui_language`); it decides
/// which word translations the user is served.
final ValueNotifier<String> appLanguage = ValueNotifier('ru');

const List<({String code, String label})> uiLanguages = [
  (code: 'ru', label: 'Русский'),
  (code: 'tg', label: 'Тоҷикӣ'),
  (code: 'uz', label: 'Oʻzbekcha'),
];

/// Whether this device has a language the user picked here; if not, the
/// one saved on their account is used after login.
bool hasSavedAppLanguage = false;

const _storage = FlutterSecureStorage();
const _storageKey = 'ui_language';

Future<void> loadAppLanguage() async {
  try {
    final saved = await _storage.read(key: _storageKey);
    if (saved != null && uiLanguages.any((l) => l.code == saved)) {
      appLanguage.value = saved;
      hasSavedAppLanguage = true;
    }
  } catch (_) {}
}

Future<void> setAppLanguage(String code) async {
  if (!uiLanguages.any((l) => l.code == code)) return;
  appLanguage.value = code;
  hasSavedAppLanguage = true;
  try {
    await _storage.write(key: _storageKey, value: code);
  } catch (_) {}
}

/// [ru] in the current interface language, with `{0}`, `{1}`… replaced by
/// [args]. Falls back to Russian for any string without a translation.
String tr(String ru, [List<Object?> args = const []]) {
  var text = ru;
  final lang = appLanguage.value;
  if (lang != 'ru') {
    final row = uiStrings[ru];
    if (row != null) text = lang == 'tg' ? row.$1 : row.$2;
  }
  for (var i = 0; i < args.length; i++) {
    text = text.replaceAll('{$i}', '${args[i]}');
  }
  return text;
}
