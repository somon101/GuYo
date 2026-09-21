import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../exercises/exercise_type.dart';
import '../models/lesson.dart';
import 'build_word_screen.dart';
import 'listen_word_screen.dart';
import 'matching_screen.dart';
import 'speaking_word_screen.dart';
import 'true_or_false_screen.dart';

/// One lesson's own screen: its fixed word set, each word's own cumulative
/// score/learned status, and whichever exercises the backend decided are
/// available for it. Reached by tapping a link in the "Уроки" chain
/// (LessonsScreen) -- for the still-open lesson this is where the user
/// actually plays exercises; for an already-completed one (see
/// [Lesson.isCompleted]) it's a read-only look back at what was learned,
/// no exercise buttons shown -- a finished lesson is history, not
/// something to keep replaying.
///
/// Re-fetches every time an exercise screen pushed from here is popped back
/// to it (see [_openExercise]) -- the score/learned state shown here must
/// always reflect the backend's latest answer, never a stale copy from
/// before the exercise ran.
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

  Future<void> _openExercise(String exerciseKey) async {
    final lesson = _lesson;
    if (lesson == null) return;
    final label = lessonExerciseTypes[exerciseKey]?.label ?? exerciseKey;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(label)),
          body: switch (exerciseKey) {
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
    // Resolves whenever the pushed route leaves the stack for any reason --
    // a plain pop back here after a round, or this whole screen's own
    // route being removed together with it via the completion screen's
    // popUntil(isFirst) -- either way, `mounted` below covers the case
    // where this screen no longer exists to update.
    await _load();
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
        if (!lesson.isCompleted) ...[
          if (lesson.exerciseKeys.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Для этого урока пока нет доступных упражнений.',
                style: TextStyle(color: Colors.black54),
              ),
            )
          else ...[
            const Text('Упражнения', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final key in lesson.exerciseKeys)
                  FilledButton.tonalIcon(
                    onPressed: () => _openExercise(key),
                    icon: Icon(lessonExerciseTypes[key]?.icon ?? Icons.school_outlined),
                    label: Text(lessonExerciseTypes[key]?.label ?? key),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
        ],
        const Text('Слова урока', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (final word in lesson.words) _LessonWordTile(word: word),
      ],
    );
  }
}

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
