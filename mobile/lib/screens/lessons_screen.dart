import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/lesson.dart';
import 'build_word_screen.dart';
import 'learned_words_screen.dart';
import 'lesson_create_screen.dart';
import 'matching_screen.dart';
import 'true_or_false_screen.dart';

const Map<String, String> _exerciseLabels = {
  'true_or_false': 'Правда или ложь',
  'matching': 'Сопоставление',
  'build_word': 'Собери слово',
};

const Map<String, IconData> _exerciseIcons = {
  'true_or_false': Icons.rule_outlined,
  'matching': Icons.extension_outlined,
  'build_word': Icons.abc_outlined,
};

/// "Уроки": the new primary progress system's own tab. Shows this
/// dictionary's current active lesson (its fixed word set, each word's own
/// cumulative score/learned status, and whichever exercises the backend
/// decided are available for it) -- or, once it's fully complete (every
/// word at or above the admin's threshold) or there isn't one yet, the
/// entry point to create the next one.
///
/// All progress state -- scores, learned status, lesson completion -- is
/// whatever the backend's last response said; this screen never computes
/// any of it, only reloads after anything that could have changed it (an
/// exercise round, a new lesson).
class LessonsScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const LessonsScreen({super.key, required this.dictionary});

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  bool _isLoading = true;
  String? _loadError;
  Lesson? _lesson;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Guarded even before the first await: `_openExercise` calls this right
    // after an awaited Navigator.push returns, and that push/pop round trip
    // is a wide enough window for HomeScreen's unrelated resume-triggered
    // dictionaries reload to have already torn down and disposed this
    // screen by the time control comes back here.
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final lesson = await ApiClient.instance.fetchActiveLesson(widget.dictionary.id);
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
    final label = _exerciseLabels[exerciseKey] ?? exerciseKey;
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(label)),
          body: switch (exerciseKey) {
            'true_or_false' => TrueOrFalseScreen(lessonId: lesson.id),
            'matching' => MatchingScreen(lessonId: lesson.id),
            'build_word' => BuildWordScreen(lessonId: lesson.id),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
    await _load();
    if (!mounted) return;
    if (completed == true) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Урок пройден! Можно создать следующий.')));
    }
  }

  Future<void> _openLearnedWords() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LearnedWordsScreen(dictionary: widget.dictionary)),
    );
  }

  Future<void> _createLesson() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LessonCreateScreen(dictionary: widget.dictionary)),
    );
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _openLearnedWords,
                icon: const Icon(Icons.bookmark_outline),
                label: const Text('Мои слова'),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(
        children: const [
          SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
        ],
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

    final lesson = _lesson;
    if (lesson == null) {
      return ListView(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_stories_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  const Text(
                    'Пока нет активного урока',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Выберите слова для нового урока, чтобы начать',
                    style: TextStyle(color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _createLesson, child: const Text('Создать урок')),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final learnedCount = lesson.words.where((w) => w.isLearned).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('Урок ${lesson.number}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
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
                  icon: Icon(_exerciseIcons[key] ?? Icons.school_outlined),
                  label: Text(_exerciseLabels[key] ?? key),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
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
