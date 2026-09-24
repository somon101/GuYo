import 'dart:async';

import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/lesson.dart';
import '../models/word.dart';
import '../theme/app_colors.dart';
import '../widgets/word_card.dart';
import 'build_word_screen.dart';
import 'lesson_results_screen.dart';
import 'listen_word_screen.dart';
import 'matching_screen.dart';
import 'speaking_word_screen.dart';
import 'true_or_false_screen.dart';
import 'word_detail_screen.dart';

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
  // Set only by the "Продолжить" button on the "Уроки" list's in-progress
  // card: jumps straight into the exercise sequence the moment this
  // screen's own first load finishes, instead of waiting for a tap on
  // "Начать урок" -- the exact same _startLesson() flow either way, this
  // just skips the one extra tap. Ignored for an already-completed lesson
  // (nothing to start) or one with no available exercises.
  final bool autoStart;
  const LessonDetailScreen({super.key, required this.lessonId, this.autoStart = false});

  @override
  State<LessonDetailScreen> createState() => _LessonDetailScreenState();
}

class _LessonDetailScreenState extends State<LessonDetailScreen> {
  bool _isLoading = true;
  String? _loadError;
  Lesson? _lesson;
  bool _isRunning = false;
  // One-shot: _load() also runs again at the end of every _startLesson()
  // pass (to refresh word/status state) and on pull-to-refresh -- without
  // this guard, autoStart would re-trigger itself forever the moment its
  // own run finishes.
  bool _autoStartTriggered = false;
  // Only decides the shared word card's stripe color; a failure to load it
  // leaves the cards uncolored rather than failing the lesson.
  List<WordLevelSummary> _levels = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadLevels();
  }

  Future<void> _loadLevels() async {
    try {
      final levels = await ApiClient.instance.fetchWordLevels();
      if (!mounted) return;
      setState(() => _levels = levels);
    } catch (_) {
      // Colorless cards are an acceptable degraded state.
    }
  }

  void _openWord(LessonWord word) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WordDetailScreen(
          word: word.word,
          transcription: word.transcription,
          translation: word.translation,
          wordAudioUrl: word.wordAudioUrl,
          translationAudioUrl: word.translationAudioUrl,
          imageUrl: word.imageUrl,
          score: word.score,
          level: WordLevelView.resolve(word.wordLevelId, word.wordLevelName, _levels),
        ),
      ),
    );
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
      if (widget.autoStart && !_autoStartTriggered && !lesson.isCompleted && lesson.exerciseKeys.isNotEmpty) {
        _autoStartTriggered = true;
        unawaited(_startLesson());
      }
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
    final tint = lesson.isCompleted ? AppColors.success : AppColors.primary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (lesson.isCompleted)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success),
                const SizedBox(width: 10),
                const Text('Урок пройден', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tint.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Изучено $learnedCount из ${lesson.words.length} слов',
                style: const TextStyle(color: AppColors.secondaryText, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: lesson.words.isEmpty ? 0.0 : learnedCount / lesson.words.length,
                  minHeight: 8,
                  backgroundColor: tint.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(tint),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Слова урока', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        for (final word in lesson.words)
          WordCard(
            word: word.word,
            transcription: word.transcription,
            translation: word.translation,
            audioUrl: word.wordAudioUrl,
            level: WordLevelView.resolve(word.wordLevelId, word.wordLevelName, _levels),
            onTap: () => _openWord(word),
            trailing: word.isLearned
                ? const Icon(Icons.check_circle, color: AppColors.success, size: 18)
                : const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB9BEDA)),
          ),
        if (!lesson.isCompleted) ...[
          const SizedBox(height: 12),
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
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
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
