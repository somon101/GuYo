class GuyoDictionary {
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

  static const Map<String, String> languageLabels = {
    'en': 'English',
    'ru': 'Русский',
    'zh': '中文',
  };

  String get languageLabel => languageLabels[language] ?? language;
}
