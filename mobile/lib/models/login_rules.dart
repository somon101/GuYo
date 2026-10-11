import 'package:flutter/services.dart';

import '../l10n/l10n.dart';

/// A login: English letters, digits, _ and . -- up to [loginMaxLength],
/// case never matters (always lower-case). Same rules as the server
/// (backend app/schemas/user.py, normalize_login).
const int loginMinLength = 3;
const int loginMaxLength = 13;

/// Lower-cases what is typed and drops anything not allowed, so a wrong
/// character simply never appears.
final List<TextInputFormatter> loginInputFormatters = [
  TextInputFormatter.withFunction(
    (oldValue, newValue) => newValue.copyWith(text: newValue.text.toLowerCase()),
  ),
  FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_.]')),
  LengthLimitingTextInputFormatter(loginMaxLength),
];

/// Why [login] can't be used, or null.
String? loginRuleProblem(String login) {
  if (login.isEmpty) return tr('Введите логин');
  if (login.length < loginMinLength) return tr('Минимум 3 символа');
  if (!RegExp(r'^[a-z0-9_.]+$').hasMatch(login)) return tr('Только английские буквы, цифры, _ и .');
  return null;
}
