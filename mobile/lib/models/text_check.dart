/// «Проверка текста»: what the backend returns for one checked message
/// (see backend/app/schemas/text_check.py) plus the one thing the backend
/// deliberately does NOT decide -- the localized title, glyph and colour of
/// each error group, which belong to the interface, not to the model.
class TextCheckResult {
  final bool ok;
  final String summary;
  final List<TextCheckError> errors;

  /// The user's message with the mistakes fixed -- always Russian, whatever
  /// explanation language was picked.
  final String correctedText;

  /// True when the backend answered from its own cache instead of asking
  /// DeepSeek again: nothing was spent, so the daily limit did NOT move -- and
  /// the screen says so, because a counter that refuses to change otherwise
  /// reads as a bug.
  final bool cached;

  /// Checks left today, or null when no limit applies.
  final int? remaining;
  final int? dailyLimit;
  final bool unlimited;

  const TextCheckResult({
    required this.ok,
    required this.summary,
    required this.errors,
    required this.correctedText,
    this.cached = false,
    this.remaining,
    this.dailyLimit,
    this.unlimited = false,
  });

  /// The one thing the screen asks: are there mistakes to show? (`ok` alone
  /// is not enough -- an answer that lists errors is never "all correct".)
  bool get hasErrors => errors.isNotEmpty;

  factory TextCheckResult.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'];
    return TextCheckResult(
      ok: json['ok'] as bool? ?? false,
      summary: json['summary'] as String? ?? '',
      errors: rawErrors is List
          ? rawErrors
              .whereType<Map<String, dynamic>>()
              .map(TextCheckError.fromJson)
              .toList(growable: false)
          : const [],
      correctedText: json['corrected_text'] as String? ?? '',
      cached: json['cached'] as bool? ?? false,
      remaining: json['remaining'] as int?,
      dailyLimit: json['daily_limit'] as int?,
      unlimited: json['unlimited'] as bool? ?? false,
    );
  }
}

/// GET /text-check/info: what the screen needs before the first message is
/// typed -- whether the checker is on, how long a message may be, and how many
/// checks are left today.
///
/// A separate call on purpose: the field's own limit and the counter must be
/// right BEFORE the user writes anything, and the admin can change both here
/// without a new app build.
class TextCheckInfo {
  final bool enabled;
  final int maxChars;
  final int? remaining;
  final int? dailyLimit;
  final bool unlimited;

  const TextCheckInfo({
    required this.enabled,
    required this.maxChars,
    this.remaining,
    this.dailyLimit,
    this.unlimited = false,
  });

  factory TextCheckInfo.fromJson(Map<String, dynamic> json) {
    return TextCheckInfo(
      enabled: json['enabled'] as bool? ?? false,
      maxChars: json['max_chars'] as int? ?? 500,
      remaining: json['remaining'] as int?,
      dailyLimit: json['daily_limit'] as int?,
      unlimited: json['unlimited'] as bool? ?? false,
    );
  }

  /// The counter as it stands after one check, taken from that check's own
  /// answer -- so the screen never needs a second request to stay honest.
  TextCheckInfo afterCheck(TextCheckResult result) {
    return TextCheckInfo(
      enabled: enabled,
      maxChars: maxChars,
      remaining: result.remaining,
      dailyLimit: result.dailyLimit,
      unlimited: result.unlimited,
    );
  }
}

/// One mistake: the fragment as written, what it should be, and why.
class TextCheckError {
  /// One of the backend's own keys: gender / punctuation / formality /
  /// orthography / grammar / style.
  final String group;
  final String fragment;
  final String correct;
  final String explanation;

  const TextCheckError({
    required this.group,
    required this.fragment,
    required this.correct,
    required this.explanation,
  });

  factory TextCheckError.fromJson(Map<String, dynamic> json) {
    return TextCheckError(
      group: json['group'] as String? ?? 'grammar',
      fragment: json['fragment'] as String? ?? '',
      correct: json['correct'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
    );
  }
}

/// The explanation languages the user can pick, written in their own
/// language -- the same convention the app's own interface-language picker
/// follows (l10n.dart's uiLanguages), so no translation of a language name
/// is ever needed.
const List<({String code, String label})> textCheckLanguages = [
  (code: 'ru', label: 'Русский'),
  (code: 'tg', label: 'Тоҷикӣ'),
  (code: 'uz', label: 'Oʻzbekcha'),
  (code: 'en', label: 'English'),
];

/// The short code the top bar's own button shows: RU / TJ / UZ / EN.
String textCheckLanguageCode(String code) => switch (code) {
      'tg' => 'TJ',
      'uz' => 'UZ',
      'en' => 'EN',
      _ => 'RU',
    };

/// The group titles, per explanation language. The group a mistake belongs
/// to is decided by the model (a key); the title is drawn here, in the
/// language the user asked for explanations in.
///
/// Tajik and Uzbek are deliberately empty for now: each is a one-line
/// addition, and until it is filled in the Russian title is shown (see
/// [textCheckGroupTitle]). Nothing here is ever machine-translated.
const Map<String, Map<String, String>> _groupTitles = {
  'gender': {'ru': 'Род', 'en': 'Gender'},
  'punctuation': {'ru': 'Пунктуация', 'en': 'Punctuation'},
  'formality': {'ru': 'Формальность', 'en': 'Formality'},
  'orthography': {'ru': 'Орфография', 'en': 'Spelling'},
  'grammar': {'ru': 'Грамматика', 'en': 'Grammar'},
  'style': {'ru': 'Стиль', 'en': 'Style'},
};

/// The group's title in [language], falling back to Russian when that
/// language has no title yet.
String textCheckGroupTitle(String group, String language) {
  final titles = _groupTitles[group] ?? _groupTitles['grammar']!;
  return titles[language] ?? titles['ru']!;
}

/// The tiny round badge in front of a group title -- the same glyphs the
/// original prototype used, which read the same in every language.
const Map<String, String> _groupGlyphs = {
  'gender': '👤',
  'punctuation': '!',
  'formality': '🎩',
  'orthography': 'A',
  'grammar': '📘',
  'style': '✨',
};

String textCheckGroupGlyph(String group) => _groupGlyphs[group] ?? _groupGlyphs['grammar']!;

/// Whether a group is shown in the app's warm "attention" colour instead of
/// the red used for a plain mistake -- «Стиль» is advice, not an error.
bool textCheckGroupIsStyle(String group) => group == 'style';
