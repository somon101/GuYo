import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/lesson.dart';
import 'build_word_screen.dart';
import 'lesson_results_screen.dart';
import 'listen_word_screen.dart';
import 'matching_screen.dart';
import 'speaking_word_screen.dart';
import 'true_or_false_screen.dart';

/// One lesson's own screen: its fixed word set, each word's own cumulative
/// score/learned status, and one "Начать урок" button. Reached by tapping a
/// link in the "Уроки" chain (LessonsScreen).
///
/// The user never picks which exercise to play: tapping "Начать урок" walks
/// this lesson's own `exerciseKeys` (decided once at creation, unchanged)
/// IN ORDER, pushing each exercise type's existing screen in turn -- an
/// exercise whose round currently has nothing left to test (every one of
/// its words already at the required level) is skipped automatically,
/// never shown as an empty screen. Once every exercise type has been
/// attempted (or skipped), [LessonResultsScreen] shows the real, dynamic
/// outcome -- per-word progress/level, and whether the lesson is fully
/// "Пройден" or needs another pass. A repeat pass runs the exact same
/// sequence again; each exercise's own round (see backend/app/exercises/
/// common.py's lesson_words_pending) already narrows itself to only the
/// words still short of their level, so nothing already secured gets
/// re-tested.
///
/// For an already-completed lesson this is a read-only look back at what
/// was learned -- no "Начать урок" button, a finished lesson is history.
class LessonDetailScreen extends StatefulWidget {
  final int lessonId;
  const LessonDetailScreen({super.key, required this.lessonId});

  @override
  State<LessonDetailScreen> createState() => _LessonDetailScreenState();
}

class _LessonDetailScreenState extends State<LessonDetailScreen> {
  bool _isLoading = true;
  String? _loadError;
  Lesson? _lesson;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final lesson = await ApiClient.instance.fetchLesson(widget.lessonId);
      if (!mounted) return;
      setState(() {
        _lesson = lesson;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить урок';
      });
    }
  }

  /// Whether exercise [key]'s round currently has anything left to test --
  /// fetched fresh every time (never cached), since an earlier exercise
  /// type in this same pass can push a word over its required level and
  /// shrink what THIS exercise still needs to cover. Сопоставление alone
  /// needs at least 2 remaining words to form a board at all (matching a
  /// single leftover word against nothing isn't a real round); every other
  /// type is meaningful with just 1.
  Future<bool> _hasPendingWork(String key) async {
    switch (key) {
      case 'true_or_false':
        return (await ApiClient.instance.fetchLessonTrueOrFalseRound(widget.lessonId)).items.isNotEmpty;
      case 'matching':
        return (await ApiClient.instance.fetchLessonMatchingWords(widget.lessonId)).length >= 2;
      case 'build_word':
        return (await ApiClient.instance.fetchLessonBuildWordRound(widget.lessonId)).items.isNotEmpty;
      case 'speaking_word':
        return (await ApiClient.instance.fetchLessonSpeakingWordRound(widget.lessonId)).items.isNotEmpty;
      case 'listen_word':
        return (await ApiClient.instance.fetchLessonListenWordRound(widget.lessonId)).items.isNotEmpty;
      default:
        return false;
    }
  }

  Future<void> _pushExercise(String key, Lesson lesson) async {
    final label = _exerciseLabels[key] ?? key;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(label)),
          body: switch (key) {
            'true_or_false' => TrueOrFalseScreen(lessonId: lesson.id, lessonNumber: lesson.number),
            'matching' => MatchingScreen(lessonId: lesson.id, lessonNumber: lesson.number),
            'build_word' => BuildWordScreen(lessonId: lesson.id, lessonNumber: lesson.number),
            'speaking_word' => SpeakingWordScreen(lessonId: lesson.id, lessonNumber: lesson.number),
            'listen_word' => ListenWordScreen(lessonId: lesson.id, lessonNumber: lesson.number),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  /// Walks `lesson.exerciseKeys` in the backend's own fixed order, skipping
  /// any exercise with nothing pending, then shows the results screen. If
  /// the user chooses "Повторить урок" there, this whole sequence just
  /// runs again -- naturally covering only what's still short, since every
  /// round is re-fetched fresh each time.
  Future<void> _startLesson() async {
    final lesson = _lesson;
    if (lesson == null || _isRunning) return;
    setState(() => _isRunning = true);
    try {
      for (final key in lesson.exerciseKeys) {
        bool hasWork;
        try {
          hasWork = await _hasPendingWork(key);
        } catch (_) {
          // A single exercise's own availability check failing (a network
          // blip) shouldn't derail the whole run -- try to still show it
          // rather than silently skip a real round.
          hasWork = true;
        }
        if (!hasWork) continue;
        if (!mounted) return;
        await _pushExercise(key, lesson);
        if (!mounted) return;
      }

      if (!mounted) return;
      final fresh = await ApiClient.instance.fetchLesson(widget.lessonId);
      if (!mounted) return;
      final repeat = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => LessonResultsScreen(lesson: fresh)),
      );
      if (!mounted) return;
      if (repeat == true) {
        setState(() => _isRunning = false);
        await _startLesson();
        return;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось продолжить урок, попробуйте ещё раз')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRunning = false);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_lesson != null ? 'Урок ${_lesson!.number}' : 'Урок')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(
        children: const [SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))],
      );
    }
    if (_loadError != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Повторить')),
              ],
            ),
          ),
        ],
      );
    }

    final lesson = _lesson!;
    final learnedCount = lesson.words.where((w) => w.isLearned).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (lesson.isCompleted)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade600),
                const SizedBox(width: 8),
                const Text('Урок пройден', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
              ],
            ),
          ),
        Text(
          'Изучено $learnedCount из ${lesson.words.length}',
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: lesson.words.isEmpty ? 0.0 : learnedCount / lesson.words.length,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 20),
        Text('Слова урока', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (final word in lesson.words) _LessonWordTile(word: word),
        if (!lesson.isCompleted) ...[
          const SizedBox(height: 20),
          if (lesson.exerciseKeys.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Для этого урока пока нет доступных упражнений.',
                style: TextStyle(color: Colors.black54),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isRunning ? null : _startLesson,
                icon: _isRunning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(_isRunning ? 'Загрузка…' : 'Начать урок'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
        ],
      ],
    );
  }
}

const Map<String, String> _exerciseLabels = {
  'true_or_false': 'Правда или ложь',
  'matching': 'Сопоставление',
  'build_word': 'Собери слово',
  'speaking_word': 'Произнеси слово',
  'listen_word': 'Услышь слово',
};

class _LessonWordTile extends StatelessWidget {
  final LessonWord word;
  const _LessonWordTile({required this.word});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: word.isLearned ? Colors.green.shade50 : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: word.isLearned ? Colors.green.shade300 : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(word.word, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                if (word.translation != null && word.translation!.isNotEmpty)
                  Text(word.translation!, style: const TextStyle(fontSize: 14, color: Colors.black54)),
              ],
            ),
          ),
          if (word.isLearned)
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 20)
          else
            Text('${word.score}', style: const TextStyle(fontSize: 14, color: Colors.black54)),
        ],
      ),
    );
  }
}
