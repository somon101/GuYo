import 'demo_state.dart';
import 'demo_words.dart';

/// Lessons, exercises and the day's goal of the demo, on top of [DemoState].
/// Returns null when the path is not one of these (the caller goes on); `_none` means 404.
const demoNotFound = Object();

Object? demoDynamic(String method, String path, Map<String, String> q, Map<String, dynamic> body) {
  final s = DemoState.instance;
  RegExpMatch? m;

  if (path == '/daily-goal') {
    if (method == 'PUT') {
      s.goal = (body['goal'] as int?) ?? s.goal;
      s.save();
    }
    return s.goalJson();
  }
  if (path == '/daily-goal/claim' && method == 'POST') {
    s.goalClaimed = true;
    s.save();
    return {'state': s.goalJson()};
  }

  if (path == '/season-pass' || path == '/season-pass/summary') return _pass();
  if (path == '/season-pass/claim' && method == 'POST') {
    s.passClaimed.add('${body['level']}:${body['track']}');
    s.save();
    return _pass();
  }
  if (path == '/season-pass/claim-all' && method == 'POST') {
    final taken = <Map<String, Object?>>[];
    for (final l in _passLevels) {
      for (final t in ['free', 'premium']) {
        final r = l[t] as Map<String, Object?>?;
        if (r != null && (l['level'] as int) <= _passLevel && !s.passClaimed.contains('${l['level']}:$t')) {
          s.passClaimed.add('${l['level']}:$t');
          taken.add({...r});
        }
      }
    }
    s.save();
    return {'state': _pass(), 'rewards': taken, 'xp': 0};
  }
  if (path == '/text-check/info') {
    return {'enabled': true, 'max_chars': 500, 'remaining': null, 'daily_limit': null, 'unlimited': true, 'confirmation_style': 'banner'};
  }
  if (path == '/text-check' && method == 'POST') {
    final text = (body['text'] as String?) ?? '';
    // A made-up checker: it flags the word «чтобы» written apart as an example of a mistake.
    final hasMistake = text.contains('что бы');
    return hasMistake
        ? {
            'ok': false, 'summary': 'Одна ошибка', 'cached': false, 'remaining': null, 'daily_limit': null, 'unlimited': true,
            'errors': [
              {'group': 'orthography', 'fragment': 'что бы', 'correct': 'чтобы', 'explanation': 'Союз «чтобы» пишется слитно.'},
            ],
            'corrected_text': text.replaceAll('что бы', 'чтобы'),
          }
        : {'ok': true, 'summary': 'Всё хорошо, ошибок нет.', 'cached': false, 'remaining': null, 'daily_limit': null, 'unlimited': true, 'errors': <Object>[], 'corrected_text': text};
  }
  if (path == '/shop') return _shop();
  m = RegExp(r'^/shop/(\d+)/buy$').firstMatch(path);
  if (m != null && method == 'POST') {
    final p = _products.firstWhere((p) => p['id'] == int.parse(m!.group(1)!));
    final price = p['price_diamonds'] as int;
    if (s.diamonds < price) return demoNotFound;
    s.diamonds -= price;
    if (p['item_type'] == 'streak_merge') {
      s.merges += p['quantity'] as int;
    } else {
      s.freezes += p['quantity'] as int;
    }
    s.save();
    return _shop();
  }

  m = RegExp(r'^/dictionaries/(\d+)/lessons$').firstMatch(path);
  if (m != null && method == 'GET') {
    final d = int.parse(m.group(1)!);
    return {
      'lessons': [
        for (final l in s.lessons.where((l) => l.dictionaryId == d))
          {'id': l.id, 'number': l.number, 'is_completed': l.completed, 'word_count': l.wordIds.length, 'learned_count': l.wordIds.where(s.learned.contains).length},
      ],
    };
  }
  m = RegExp(r'^/dictionaries/(\d+)/lesson-candidate-words$').firstMatch(path);
  if (m != null) {
    final d = int.parse(m.group(1)!);
    final pool = wordsOf(d).where((w) => !s.learned.contains(w.id)).toList();
    return {'dictionary_id': d, 'available_count': pool.length, 'words': [for (final w in pool) wordJson(w)], 'max_words': 15};
  }
  if (path == '/lessons/active') {
    final d = int.tryParse(q['dictionary_id'] ?? '') ?? 1;
    final open = s.lessons.where((l) => l.dictionaryId == d && !l.completed);
    return open.isEmpty ? demoNotFound : _lesson(open.last);
  }
  if (path == '/lessons' && method == 'POST') {
    final lesson = s.create(body['dictionary_id'] as int, (body['word_ids'] as List?)?.cast<int>(), body['random_count'] as int?);
    return _lesson(lesson);
  }
  m = RegExp(r'^/lessons/(\d+)(/.*)?$').firstMatch(path);
  if (m != null) {
    final lesson = s.lessons.firstWhere((l) => l.id == int.parse(m!.group(1)!), orElse: () => s.lessons.last);
    final rest = m.group(2) ?? '';
    if (rest.isEmpty) return _lesson(lesson);
    if (rest == '/pass' && method == 'POST') {
      lesson.answers = {};
      lesson.scoreBefore = {for (final id in lesson.wordIds) id: s.scoreOf(id)};
      lesson.startedAt = DateTime.now();
      return _lesson(lesson);
    }
    if (rest == '/pass/finish') {
      lesson.completed = true;
      s.save();
      return {..._lesson(lesson), 'pass_stats': _stats(lesson)};
    }
    if (rest == '/pass/stats') return _stats(lesson);
    if (rest.startsWith('/check')) return {'enabled': false, 'skip_allowed': true, 'items': <Object>[]};
    final ex = RegExp(r'^/exercises/([a-z\-_]+)(/answers)?$').firstMatch(rest);
    if (ex != null) {
      if (ex.group(2) != null) {
        return s.answer(lesson.id, ex.group(1)!, body['word_id'] as int, body['is_correct'] as bool);
      }
      final ids = (q['word_ids'] != null && q['word_ids']!.isNotEmpty) ? q['word_ids']!.split(',').map(int.parse).toList() : lesson.wordIds;
      return _round(ex.group(1)!, lesson.dictionaryId, ids);
    }
  }

  // Practice outside lessons: rounds over the words already learned.
  m = RegExp(r'^/dictionaries/(\d+)/(practice|exercises)/([a-z\-]+)$').firstMatch(path);
  if (m != null && method == 'GET') {
    final d = int.parse(m.group(1)!);
    final ids = s.learnedWords(d).map((w) => w.id).take(10).toList();
    if (m.group(3) == 'review-due') return {'count': 12, 'word_ids': ids};
    return _round(m.group(3)!, d, ids);
  }
  m = RegExp(r'^/dictionaries/(\d+)/exercises/([a-z\-_]+)/learned-words$').firstMatch(path);
  if (m != null) {
    final d = int.parse(m.group(1)!);
    return {'words': [for (final w in s.learnedWords(d)) wordJson(w)]};
  }
  return null;
}

Map<String, Object?> _lesson(DemoLesson l) {
  final s = DemoState.instance;
  return {
    'id': l.id, 'dictionary_id': l.dictionaryId, 'number': l.number, 'is_completed': l.completed,
    'exercise_keys': ['true_or_false', 'matching', 'build_word'],
    'words': [
      for (final id in l.wordIds)
        {
          'word_id': id, 'word': s.word(id).word, 'translation': s.word(id).translation, 'score': s.scoreOf(id),
          'is_learned': s.learned.contains(id), 'word_level_id': s.learned.contains(id) ? 4 : 1,
          'word_level_name': s.learned.contains(id) ? 'Выучено' : 'Новое', 'transcription': s.word(id).transcription,
          'word_audio_url': null, 'translation_audio_url': null, 'image_url': null,
        },
    ],
    'mini_phrases': <Object>[],
  };
}

Map<String, Object?> _stats(DemoLesson l) {
  final s = DemoState.instance;
  final total = l.answers.values.fold<int>(0, (n, a) => n + a[1]);
  final correct = l.answers.values.fold<int>(0, (n, a) => n + a[0]);
  return {
    'duration_seconds': l.startedAt == null ? 60 : DateTime.now().difference(l.startedAt!).inSeconds.clamp(5, 3600),
    'total_answers': total, 'correct_answers': correct, 'wrong_answers': total - correct,
    'accuracy': total == 0 ? 0 : correct * 100 ~/ total,
    'score_gained': [for (final id in l.wordIds) s.scoreOf(id) - (l.scoreBefore[id] ?? 0)].fold<int>(0, (a, b) => a + b),
    'newly_learned': [for (final id in l.wordIds) if (s.learned.contains(id) && (l.scoreBefore[id] ?? 0) < 100) id].length,
    'exercises': [for (final e in l.answers.entries) {'exercise_key': e.key, 'correct': e.value[0], 'total': e.value[1]}],
    'words': [
      for (final id in l.wordIds)
        {
          'word_id': id, 'word': s.word(id).word, 'score_before': l.scoreBefore[id] ?? 0, 'score_after': s.scoreOf(id),
          'gained': s.scoreOf(id) - (l.scoreBefore[id] ?? 0), 'became_learned': s.learned.contains(id) && (l.scoreBefore[id] ?? 0) < 100,
        },
    ],
  };
}

Object _round(String key, int dictionaryId, List<int> ids) {
  final s = DemoState.instance;
  final words = [for (final id in ids) s.word(id)];
  final all = wordsOf(dictionaryId).toList();
  switch (key) {
    case 'true-or-false':
      return {
        'dictionary_id': dictionaryId, 'available_count': words.length,
        'items': [
          for (var i = 0; i < words.length; i++)
            () {
              final right = i.isEven;
              final other = all[(all.indexOf(words[i]) + 3) % all.length];
              return {
                'word_id': words[i].id, 'original': words[i].word, 'transcription': words[i].transcription, 'image_url': null,
                'word_audio_url': null, 'shown_translation': right ? words[i].translation : other.translation,
                'shown_translation_audio_url': null, 'is_correct': right,
              };
            }(),
        ],
      };
    case 'matching':
      return {'words': [for (final w in words.take(6)) wordJson(w)]};
    case 'build-word':
      return {
        'dictionary_id': dictionaryId, 'available_count': words.length, 'case_sensitive': false,
        'items': [
          for (final w in words)
            {
              'word_id': w.id, 'translation': w.translation, 'correct_word': w.word,
              'letters': ([...w.word.split(''), 'e', 'o']..shuffle()), 'transcription': w.transcription, 'image_url': null,
              'word_audio_url': null, 'translation_audio_url': null,
            },
        ],
      };
    case 'speaking-word':
      return {
        'dictionary_id': dictionaryId, 'available_count': words.length, 'match_threshold': 70,
        'items': [for (final w in words) {'word_id': w.id, 'word': w.word, 'transcription': w.transcription, 'image_url': null}],
      };
    case 'listen-word':
      return {
        'dictionary_id': dictionaryId, 'available_count': words.length,
        'items': [
          for (final w in words)
            {
              'word_id': w.id, 'word_audio_url': null,
              'options': [for (final o in ([w, ...all.where((x) => x.id != w.id).take(3)]..shuffle())) {'word_id': o.id, 'word': o.word}],
            },
        ],
      };
  }
  return {'items': <Object>[], 'words': <Object>[], 'dictionary_id': dictionaryId, 'available_count': 0};
}

const _products = <Map<String, Object>>[
  {'id': 1, 'name': 'Заморозка серии', 'description': 'Спасает серию, если пропущено больше одного дня', 'item_type': 'streak_freeze', 'quantity': 1, 'price_diamonds': 50},
  {'id': 2, 'name': 'Заморозки ×5', 'description': 'Спасает серию, если пропущено больше одного дня', 'item_type': 'streak_freeze', 'quantity': 5, 'price_diamonds': 200},
  {'id': 3, 'name': 'Заморозки ×10', 'description': 'Спасает серию, если пропущено больше одного дня', 'item_type': 'streak_freeze', 'quantity': 10, 'price_diamonds': 350},
  {'id': 4, 'name': 'Объединитель серии', 'description': 'Склеивает прерванные серии в одну', 'item_type': 'streak_merge', 'quantity': 1, 'price_diamonds': 300},
];

Map<String, Object?> _shop() {
  final s = DemoState.instance;
  return {'diamonds': s.diamonds, 'streak_freezes': s.freezes, 'streak_merge_items': s.merges, 'products': _products};
}

const _passLevel = 4;

// (level, free, premium): each reward is {type, amount, key?, kind?, text?}.
final _passLevels = <Map<String, Object?>>[
  for (final e in <(int, Map<String, Object>, Map<String, Object>)>[
    (1, {'type': 'rating_points', 'amount': 10}, {'type': 'diamonds', 'amount': 5}),
    (2, {'type': 'chest', 'amount': 1, 'key': 'wood'}, {'type': 'booster', 'amount': 30, 'kind': 'rating'}),
    (3, {'type': 'booster', 'amount': 30, 'kind': 'xp'}, {'type': 'streak_freeze', 'amount': 1}),
    (4, {'type': 'rating_points', 'amount': 15}, {'type': 'chest', 'amount': 1, 'key': 'silver'}),
    (5, {'type': 'chest', 'amount': 1, 'key': 'silver'}, {'type': 'booster', 'amount': 60, 'kind': 'chest'}),
    (6, {'type': 'streak_freeze', 'amount': 1}, {'type': 'diamonds', 'amount': 10}),
    (7, {'type': 'rating_points', 'amount': 20}, {'type': 'chest', 'amount': 1, 'key': 'gold'}),
    (8, {'type': 'chest', 'amount': 1, 'key': 'silver'}, {'type': 'frame', 'amount': 1, 'key': 'gold', 'text': 'Золотая рамка'}),
    (9, {'type': 'diamonds', 'amount': 5}, {'type': 'title', 'amount': 1, 'key': 'scholar', 'text': 'Знаток'}),
    (10, {'type': 'chest', 'amount': 1, 'key': 'gold'}, {'type': 'premium_days', 'amount': 3}),
  ])
    {'level': e.$1, 'xp': e.$1 * 100, 'free': e.$2, 'premium': e.$3},
];

Map<String, Object?> _passReward(Map<String, Object?> r, int level, String track) {
  final s = DemoState.instance;
  final taken = s.passClaimed.contains('$level:$track');
  return {
    ...r,
    'claimed': taken,
    'claimable': !taken && level <= _passLevel,
    'locked_by_premium': false,
  };
}

Map<String, Object?> _pass() {
  return {
    'season_name': 'Осень', 'ends_at': DateTime.now().add(const Duration(days: 29)).toUtc().toIso8601String(),
    'xp': 140, 'level': _passLevel, 'xp_into_level': 40, 'xp_for_next': 100, 'is_premium': true, 'premium_enabled': true,
    'levels': [
      for (final l in _passLevels)
        {
          'level': l['level'], 'xp': l['xp'],
          'free': _passReward(l['free'] as Map<String, Object?>, l['level'] as int, 'free'),
          'premium': _passReward(l['premium'] as Map<String, Object?>, l['level'] as int, 'premium'),
        },
    ],
    'week': {
      'ends_at': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(),
      'tasks': [
        {'id': 'w1', 'metric': 'word', 'target': 30, 'xp': 20, 'progress': 18, 'claimed': false, 'claimable': false},
        {'id': 'w2', 'metric': 'lesson', 'target': 3, 'xp': 15, 'progress': 2, 'claimed': false, 'claimable': false},
      ],
    },
  };
}
