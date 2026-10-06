import '../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/lesson.dart';
import '../models/word.dart';
import '../theme/app_colors.dart';
import '../widgets/word_card.dart';
import 'lesson_run_screen.dart';
import 'word_detail_screen.dart';
import '../widgets/skeleton.dart';

/// One lesson's own screen: its fixed word set, each word's own cumulative
/// score/learned status, and one "Начать урок" button. Reached by tapping a
/// link in the "Уроки" chain (LessonsScreen).
///
/// The user never picks which exercise to play: "Начать урок" opens
/// LessonRunScreen, which plays every available exercise back to back on
/// one screen and ends with the results. This screen is never shown
/// between exercises.
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = tr('Не удалось загрузить урок');
      });
    }
  }

  /// Runs the lesson on its own screen (LessonRunScreen): every available
  /// exercise back to back, then the results. This screen only reappears
  /// once the user leaves the lesson, and refreshes what it shows then.
  Future<void> _startLesson() async {
    final lesson = _lesson;
    if (lesson == null || _isRunning) return;
    setState(() => _isRunning = true);
    try {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonRunScreen.forLesson(lesson)));
    } finally {
      if (mounted) setState(() => _isRunning = false);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_lesson != null ? tr('Урок {0}', [_lesson!.number]) : tr('Урок'))),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(
        children: const [SizedBox(height: 520, child: SkeletonList(rows: 6))],
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
                FilledButton(onPressed: _load, child: Text(tr('Повторить'))),
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
                Text(tr('Урок пройден'), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
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
                tr('Изучено {0} из {1} слов', [learnedCount, lesson.words.length]),
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
        Text(tr('Слова урока'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                tr('Для этого урока пока нет доступных упражнений.'),
                style: TextStyle(color: Colors.black54),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isRunning ? null : _startLesson,
                icon: const Icon(Icons.play_arrow_rounded),
                label: _isRunning ? SkeletonPulse(child: Text(tr('Готовим урок…'))) : Text(tr('Начать урок')),
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
