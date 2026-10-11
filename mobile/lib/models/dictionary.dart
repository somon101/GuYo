import '../l10n/l10n.dart';
class GuyoDictionary {
  /// The language of the dictionary open on the home screen: what the
  /// learner is studying. Speech is recognised in it, never in the phone's
  /// own language.
  static String studyLanguage = 'ru';

  /// [studyLanguage] as a speech-recognition locale.
  static String get speechLocale => const {'ru': 'ru_RU', 'en': 'en_US', 'zh': 'zh_CN'}[studyLanguage] ?? 'ru_RU';

  final int id;
  final String name;
  final String language; // "en" | "ru" | "zh"
  final int wordCount;

  GuyoDictionary({
    required this.id,
    required this.name,
    required this.language,
    required this.wordCount,
  });

  factory GuyoDictionary.fromJson(Map<String, dynamic> json) {
    return GuyoDictionary(
      id: json['id'] as int,
      name: json['name'] as String,
      language: json['language'] as String,
      wordCount: json['word_count'] as int? ?? 0,
    );
  }

  static Map<String, String> get languageLabels => {
    'en': 'English',
    'ru': tr('Русский'),
    'zh': '中文',
    'tg': 'Тоҷикӣ',
    'uz': 'Oʻzbekcha',
  };

  /// The language's own name; for a code without one, the dictionary's
  /// name as the admin wrote it, rather than a bare code like "tg".
  String get languageLabel => languageLabels[language] ?? (name.trim().isNotEmpty ? name : language);
}
