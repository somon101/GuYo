import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../l10n/l10n.dart';
import '../models/text_check.dart';

/// «Проверка текста»'s own settings, kept on the device between runs:
/// the writer's gender, the formality of the message, the language the
/// explanations come in, and whether punctuation is checked at all.
///
/// Device-local ON PURPOSE, exactly like the prototype kept them in
/// localStorage: this is NOT the app's interface language (l10n.dart's
/// `appLanguage` is never touched by this screen) and NOT a profile field,
/// so opening the checker changes nothing anywhere else in the app.
///
/// The addressee is deliberately absent: it resets for every single
/// message, so there is nothing to remember.
class TextCheckSettings {
  static const _storage = FlutterSecureStorage();
  static const _key = 'guyo_text_check';

  /// "male" or "female" -- whose self-reference and verb endings are right.
  final String userGender;

  /// "" (not chosen), "formal" or "informal".
  final String formality;

  /// One of [textCheckLanguages]' codes.
  final String explanationLanguage;

  final bool checkPunctuation;

  const TextCheckSettings({
    required this.userGender,
    required this.formality,
    required this.explanationLanguage,
    required this.checkPunctuation,
  });

  /// What this screen starts from before anything was saved. The
  /// explanation language starts as the language the app is being used in --
  /// a Tajik speaker opening the checker wants the explanations in Tajik,
  /// not in Russian -- and falls back to Russian for anything the checker
  /// cannot explain in.
  factory TextCheckSettings.defaults() {
    final ui = appLanguage.value;
    return TextCheckSettings(
      userGender: 'male',
      formality: '',
      explanationLanguage: textCheckLanguages.any((l) => l.code == ui) ? ui : 'ru',
      checkPunctuation: true,
    );
  }

  TextCheckSettings copyWith({
    String? userGender,
    String? formality,
    String? explanationLanguage,
    bool? checkPunctuation,
  }) {
    return TextCheckSettings(
      userGender: userGender ?? this.userGender,
      formality: formality ?? this.formality,
      explanationLanguage: explanationLanguage ?? this.explanationLanguage,
      checkPunctuation: checkPunctuation ?? this.checkPunctuation,
    );
  }

  /// The saved settings, or [TextCheckSettings.defaults] when nothing has
  /// been saved yet (or the stored value can't be read).
  static Future<TextCheckSettings> load() async {
    final fallback = TextCheckSettings.defaults();
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return fallback;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final gender = json['user_gender'];
      final formality = json['formality'];
      final language = json['explanation_language'];
      final punctuation = json['check_punctuation'];
      return TextCheckSettings(
        userGender: gender == 'female' ? 'female' : 'male',
        formality: (formality == 'formal' || formality == 'informal') ? formality as String : '',
        explanationLanguage:
            textCheckLanguages.any((l) => l.code == language) ? language as String : fallback.explanationLanguage,
        checkPunctuation: punctuation is bool ? punctuation : true,
      );
    } catch (_) {
      // Never let unreadable settings stop the screen from opening.
      return fallback;
    }
  }

  Future<void> save() async {
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode({
          'user_gender': userGender,
          'formality': formality,
          'explanation_language': explanationLanguage,
          'check_punctuation': checkPunctuation,
        }),
      );
    } catch (_) {
      // Best effort: losing a preference is never worth an error on screen.
    }
  }
}
