import '../api/api_client.dart';
import '../services/media_cache.dart';
import 'exercise.dart';
import 'lesson.dart';
import 'word.dart';

/// Every exercise round of one lesson pass, fetched together up front, so
/// the pass runs from start to finish without another request or a
/// loading screen between exercises.
///
/// A key whose fetch failed maps to null: that exercise then loads its own
/// round when it starts, exactly as it did before -- a network blip while
/// preparing never drops a real exercise.
class LessonRounds {
  final Map<String, Object?> _rounds;
  final Map<String, bool>? _availability;

  const LessonRounds(Map<String, Object?> rounds)
      : _rounds = rounds,
        _availability = null;

  /// For tests: which keys have something to play, without any real round.
  const LessonRounds.availability(Map<String, bool> availability)
      : _rounds = const {},
        _availability = availability;

  T? round<T>(String key) {
    final round = _rounds[key];
    return round is T ? round : null;
  }

  /// Whether exercise [key] has anything to test in this pass. Сопоставление
  /// alone needs at least 2 words to form a board; every other type works
  /// with 1.
  bool hasWork(String key) {
    final availability = _availability;
    if (availability != null) return availability[key] ?? false;
    if (!_rounds.containsKey(key)) return false;
    return switch (_rounds[key]) {
      null => true,
      TrueOrFalseRound r => r.items.isNotEmpty,
      List<GuyoWord> words => words.length >= 2,
      BuildWordRound r => r.items.isNotEmpty,
      SpeakingWordRound r => r.items.isNotEmpty,
      ListenWordRound r => r.items.isNotEmpty,
      _ => false,
    };
  }

  /// Every picture and recording any of these rounds can show or play.
  Iterable<String> get mediaUrls sync* {
    for (final round in _rounds.values) {
      switch (round) {
        case TrueOrFalseRound r:
          for (final i in r.items) {
            yield* _present([i.imageUrl, i.wordAudioUrl, i.shownTranslationAudioUrl]);
          }
        case List<GuyoWord> words:
          for (final w in words) {
            yield* _present([w.imageUrl, w.wordAudioUrl, w.translationAudioUrl]);
          }
        case BuildWordRound r:
          for (final i in r.items) {
            yield* _present([i.imageUrl, i.wordAudioUrl, i.translationAudioUrl]);
          }
        case SpeakingWordRound r:
          for (final i in r.items) {
            yield* _present([i.imageUrl]);
          }
        case ListenWordRound r:
          for (final i in r.items) {
            yield* _present([i.wordAudioUrl]);
          }
      }
    }
  }

  static Iterable<String> _present(List<String?> urls) => urls.whereType<String>().where((u) => u.isNotEmpty);

  /// Fetches every round of [exerciseKeys] in parallel, then downloads the
  /// media they use. Call right after the pass is started (its word set is
  /// frozen for the whole pass, so rounds fetched now are the ones each
  /// exercise would have fetched itself).
  static Future<LessonRounds> prepare(int lessonId, List<String> exerciseKeys) async {
    final api = ApiClient.instance;
    Future<Object?> fetch(String key) async {
      try {
        return switch (key) {
          'true_or_false' => await api.fetchLessonTrueOrFalseRound(lessonId),
          'matching' => await api.fetchLessonMatchingWords(lessonId),
          'build_word' => await api.fetchLessonBuildWordRound(lessonId),
          'speaking_word' => await api.fetchLessonSpeakingWordRound(lessonId),
          'listen_word' => await api.fetchLessonListenWordRound(lessonId),
          _ => null,
        };
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait(exerciseKeys.map(fetch));
    final rounds = LessonRounds({for (var i = 0; i < exerciseKeys.length; i++) exerciseKeys[i]: results[i]});
    await MediaCache.instance.prefetch(rounds.mediaUrls);
    return rounds;
  }
}
