/// Made-up vocabulary for the demo build: two dictionaries of English words with Russian
/// translations (the demo shows Russian as the translation language), their phrases and categories.

class DemoWord {
  final int id;
  final int dictionaryId;
  final String word;
  final String translation;
  final String transcription;
  final int categoryId;
  const DemoWord(this.id, this.dictionaryId, this.word, this.translation, this.transcription, this.categoryId);
}

const demoCategories = {
  1: 'Фрукты и овощи',
  2: 'Напитки и еда',
  3: 'В пути',
  4: 'В городе',
};

// Dictionary 1 «Еда»: ids 1..24; dictionary 2 «Путешествия»: ids 101..124.
const demoWords = <DemoWord>[
  DemoWord(1, 1, 'apple', 'яблоко', '[ˈæpl]', 1),
  DemoWord(2, 1, 'banana', 'банан', '[bəˈnɑːnə]', 1),
  DemoWord(3, 1, 'orange', 'апельсин', '[ˈɒrɪndʒ]', 1),
  DemoWord(4, 1, 'grape', 'виноград', '[ɡreɪp]', 1),
  DemoWord(5, 1, 'lemon', 'лимон', '[ˈlemən]', 1),
  DemoWord(6, 1, 'potato', 'картофель', '[pəˈteɪtəʊ]', 1),
  DemoWord(7, 1, 'tomato', 'помидор', '[təˈmɑːtəʊ]', 1),
  DemoWord(8, 1, 'carrot', 'морковь', '[ˈkærət]', 1),
  DemoWord(9, 1, 'onion', 'лук', '[ˈʌnjən]', 1),
  DemoWord(10, 1, 'cucumber', 'огурец', '[ˈkjuːkʌmbə]', 1),
  DemoWord(11, 1, 'water', 'вода', '[ˈwɔːtə]', 2),
  DemoWord(12, 1, 'milk', 'молоко', '[mɪlk]', 2),
  DemoWord(13, 1, 'tea', 'чай', '[tiː]', 2),
  DemoWord(14, 1, 'coffee', 'кофе', '[ˈkɒfi]', 2),
  DemoWord(15, 1, 'juice', 'сок', '[dʒuːs]', 2),
  DemoWord(16, 1, 'bread', 'хлеб', '[bred]', 2),
  DemoWord(17, 1, 'cheese', 'сыр', '[tʃiːz]', 2),
  DemoWord(18, 1, 'rice', 'рис', '[raɪs]', 2),
  DemoWord(19, 1, 'soup', 'суп', '[suːp]', 2),
  DemoWord(20, 1, 'egg', 'яйцо', '[eɡ]', 2),
  DemoWord(101, 2, 'ticket', 'билет', '[ˈtɪkɪt]', 3),
  DemoWord(102, 2, 'train', 'поезд', '[treɪn]', 3),
  DemoWord(103, 2, 'airport', 'аэропорт', '[ˈeəpɔːt]', 3),
  DemoWord(104, 2, 'luggage', 'багаж', '[ˈlʌɡɪdʒ]', 3),
  DemoWord(105, 2, 'passport', 'паспорт', '[ˈpɑːspɔːt]', 3),
  DemoWord(106, 2, 'bus', 'автобус', '[bʌs]', 3),
  DemoWord(107, 2, 'taxi', 'такси', '[ˈtæksi]', 3),
  DemoWord(108, 2, 'map', 'карта', '[mæp]', 3),
  DemoWord(109, 2, 'road', 'дорога', '[rəʊd]', 3),
  DemoWord(110, 2, 'bridge', 'мост', '[brɪdʒ]', 3),
  DemoWord(111, 2, 'hotel', 'гостиница', '[həʊˈtel]', 4),
  DemoWord(112, 2, 'street', 'улица', '[striːt]', 4),
  DemoWord(113, 2, 'market', 'рынок', '[ˈmɑːkɪt]', 4),
  DemoWord(114, 2, 'museum', 'музей', '[mjuˈziːəm]', 4),
  DemoWord(115, 2, 'park', 'парк', '[pɑːk]', 4),
  DemoWord(116, 2, 'bank', 'банк', '[bæŋk]', 4),
  DemoWord(117, 2, 'restaurant', 'ресторан', '[ˈrestrɒnt]', 4),
  DemoWord(118, 2, 'pharmacy', 'аптека', '[ˈfɑːməsi]', 4),
  DemoWord(119, 2, 'station', 'вокзал', '[ˈsteɪʃn]', 4),
  DemoWord(120, 2, 'city', 'город', '[ˈsɪti]', 4),
];

/// (id, dictionary, original, translation, category)
const demoPhrases = <(int, int, String, String, int)>[
  (1, 1, 'I like apples', 'Я люблю яблоки', 1),
  (2, 1, 'Water and tea, please', 'Воду и чай, пожалуйста', 2),
  (3, 1, 'Bread and cheese', 'Хлеб и сыр', 2),
  (4, 1, 'A cup of coffee', 'Чашка кофе', 2),
  (5, 2, 'Where is the airport?', 'Где аэропорт?', 3),
  (6, 2, 'One ticket to the city', 'Один билет до города', 3),
  (7, 2, 'My passport is in the hotel', 'Мой паспорт в гостинице', 4),
];

/// How many of a dictionary's words count as learned in the demo.
const demoLearnedPerDictionary = 14;

Iterable<DemoWord> wordsOf(int dictionaryId) => demoWords.where((w) => w.dictionaryId == dictionaryId);

Iterable<DemoWord> learnedOf(int dictionaryId) => wordsOf(dictionaryId).take(demoLearnedPerDictionary);

Map<String, Object?> wordJson(DemoWord w, {bool progress = false}) => {
      'id': w.id, 'dictionary_id': w.dictionaryId, 'word': w.word, 'translation': w.translation,
      'transcription': w.transcription, 'word_audio_url': null, 'translation_audio_url': null, 'image_url': null,
      'category_id': w.categoryId, 'category_name': demoCategories[w.categoryId], 'forms': <Object>[],
      if (progress) ...{'score': 100, 'word_level_id': 4, 'word_level_name': 'Выучено'},
    };

Map<String, Object?> phraseJson((int, int, String, String, int) p) => {
      'id': p.$1, 'dictionary_id': p.$2, 'category_id': p.$5, 'category_name': demoCategories[p.$5], 'original': p.$3,
      'transcription': null, 'translation_tg': p.$4, 'translation': p.$4, 'original_audio_url': null, 'translation_audio_url': null,
    };
