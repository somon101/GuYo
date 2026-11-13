import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'demo_words.dart';

/// One lesson of the demo: a few words and the answers given in its pass.
class DemoLesson {
  final int id;
  final int dictionaryId;
  final int number;
  final List<int> wordIds;
  bool completed;
  // exercise key -> [correct, total] of the current pass
  Map<String, List<int>> answers = {};
  // word id -> score at the pass start (to show what a pass gained)
  Map<int, int> scoreBefore = {};
  DateTime? startedAt;

  DemoLesson(this.id, this.dictionaryId, this.number, this.wordIds, {this.completed = false});

  Map<String, Object?> toJson() => {'id': id, 'd': dictionaryId, 'n': number, 'w': wordIds, 'c': completed};
  static DemoLesson fromJson(Map<String, dynamic> j) =>
      DemoLesson(j['id'] as int, j['d'] as int, j['n'] as int, (j['w'] as List).cast<int>(), completed: j['c'] as bool);
}

/// The demo's whole "server-side" state: what is learned, lessons and the day's goal. Kept on the
/// phone between launches (in the demo app's own storage), so progress is not lost.
class DemoState {
  DemoState._();
  static final DemoState instance = DemoState._();

  static const _key = 'guyo_demo_state_v1';
  static const _storage = FlutterSecureStorage();

  final Map<int, int> scores = {};
  final Set<int> learned = {for (final d in [1, 2]) ...learnedOf(d).map((w) => w.id)};
  final List<DemoLesson> lessons = [
    DemoLesson(1, 1, 1, [1, 2, 3, 4, 5], completed: true),
    DemoLesson(2, 1, 2, [6, 7, 8, 9, 10], completed: true),
  ];
  int nextLessonId = 3;
  int wordsToday = 12;
  int goal = 20;
  bool goalClaimed = false;
  int diamonds = 240;
  int freezes = 1;
  int merges = 0;

  int scoreOf(int wordId) => learned.contains(wordId) ? 100 : (scores[wordId] ?? 0);

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      scores
        ..clear()
        ..addAll({for (final e in (j['scores'] as Map<String, dynamic>).entries) int.parse(e.key): e.value as int});
      learned
        ..clear()
        ..addAll((j['learned'] as List).cast<int>());
      lessons
        ..clear()
        ..addAll([for (final l in j['lessons'] as List) DemoLesson.fromJson(l as Map<String, dynamic>)]);
      nextLessonId = j['next'] as int;
      wordsToday = j['today'] as int;
      goal = j['goal'] as int;
      goalClaimed = j['claimed'] as bool;
      diamonds = (j['dia'] as int?) ?? diamonds;
      freezes = (j['frz'] as int?) ?? freezes;
      merges = (j['mrg'] as int?) ?? merges;
    } catch (_) {}
  }

  void save() {
    final j = jsonEncode({
      'scores': {for (final e in scores.entries) '${e.key}': e.value},
      'learned': learned.toList(),
      'lessons': [for (final l in lessons) l.toJson()],
      'next': nextLessonId,
      'today': wordsToday,
      'goal': goal,
      'claimed': goalClaimed,
      'dia': diamonds,
      'frz': freezes,
      'mrg': merges,
    });
    _storage.write(key: _key, value: j).catchError((_) {});
  }

  Iterable<DemoWord> learnedWords(int dictionaryId) => wordsOf(dictionaryId).where((w) => learned.contains(w.id));

  DemoWord word(int id) => demoWords.firstWhere((w) => w.id == id);

  /// One answer: right gives +34, wrong -10; 100 means learned. Returns the answer's result.
  Map<String, Object?> answer(int lessonId, String exercise, int wordId, bool correct) {
    final lesson = lessons.firstWhere((l) => l.id == lessonId);
    final stat = lesson.answers.putIfAbsent(exercise, () => [0, 0]);
    stat[1]++;
    if (correct) stat[0]++;
    final before = scoreOf(wordId);
    var after = (before + (correct ? 34 : -10)).clamp(0, 100);
    var points = 0;
    if (after >= 100 && !learned.contains(wordId)) {
      learned.add(wordId);
      wordsToday++;
      points = 5;
    }
    if (!learned.contains(wordId)) scores[wordId] = after;
    save();
    return {'word_id': wordId, 'score': after, 'is_learned': learned.contains(wordId), 'lesson_completed': false, 'points_awarded': points};
  }

  DemoLesson create(int dictionaryId, List<int>? wordIds, int? count) {
    final pool = wordsOf(dictionaryId).where((w) => !learned.contains(w.id)).map((w) => w.id).toList();
    final ids = wordIds ?? pool.take(count ?? 5).toList();
    final number = lessons.where((l) => l.dictionaryId == dictionaryId).length + 1;
    final lesson = DemoLesson(nextLessonId++, dictionaryId, number, ids.isEmpty ? wordsOf(dictionaryId).take(5).map((w) => w.id).toList() : ids);
    lessons.add(lesson);
    save();
    return lesson;
  }

  Map<String, Object?> goalJson() {
    final done = wordsToday;
    final completed = done >= goal;
    return {
      'goal': goal, 'done': done, 'completed': completed, 'just_completed': false, 'xp': 0,
      'locked': completed, 'reward_ready': completed && !goalClaimed, 'claim_id': completed && !goalClaimed ? 1 : null,
      'options': [5, 10, 20],
      'tiers': [
        for (final n in [5, 10, 20])
          {'words': n, 'rewards': [{'type': 'xp', 'amount': n}, {'type': 'chest', 'key': 'wood', 'amount': 1}], 'claimed': n == goal && goalClaimed},
      ],
    };
  }
}
