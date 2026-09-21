import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/lesson.dart';
import 'learned_words_screen.dart';
import 'lesson_create_screen.dart';
import 'lesson_detail_screen.dart';
import 'quests_screen.dart';

/// "Уроки": the new primary progress system's own tab. Shows this
/// dictionary's FULL, permanent lesson history as a sequential chain --
/// every lesson the user has ever created, oldest first, each with its own
/// real status (never a locally-invented one) -- plus, once the last one
/// is fully complete (or there isn't one yet), one extra unlocked link at
/// the end for creating the next lesson. Lessons are never deleted or
/// replaced (see the backend's Lesson model): completing one just reveals
/// the next link in the chain, it never removes the one before it.
///
/// This screen owns none of the actual lesson mechanics -- word selection,
/// exercises, scoring, the learning threshold -- all of that is unchanged
/// and lives in LessonDetailScreen/LessonCreateScreen/the exercise
/// screens. This is purely "what lessons exist and in what order", always
/// re-fetched from the backend, never assembled from local state.
class LessonsScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const LessonsScreen({super.key, required this.dictionary});

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  bool _isLoading = true;
  String? _loadError;
  List<LessonSummary> _lessons = [];

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
      final lessons = await ApiClient.instance.fetchLessons(widget.dictionary.id);
      if (!mounted) return;
      setState(() {
        _lessons = lessons;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить уроки';
      });
    }
  }

  Future<void> _openLesson(int lessonId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LessonDetailScreen(lessonId: lessonId)),
    );
    await _load();
  }

  Future<void> _createNextLesson() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LessonCreateScreen(dictionary: widget.dictionary)),
    );
    await _load();
  }

  Future<void> _openLearnedWords() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LearnedWordsScreen(dictionary: widget.dictionary)),
    );
  }

  Future<void> _openQuests() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => QuestsScreen(dictionary: widget.dictionary)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _openQuests,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Квесты'),
                ),
                TextButton.icon(
                  onPressed: _openLearnedWords,
                  icon: const Icon(Icons.bookmark_outline),
                  label: const Text('Мои слова'),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
          ),
        ],
      ),
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

    final lessons = _lessons;
    // A new link is only ever added once the current last lesson is fully
    // complete -- exactly the backend's own creation rule (POST /lessons
    // 409s otherwise), mirrored here purely for what the chain displays.
    final canCreateNext = lessons.isEmpty || lessons.last.isCompleted;
    final nextNumber = lessons.isEmpty ? 1 : lessons.last.number + 1;
    final completedCount = lessons.where((l) => l.isCompleted).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          'Уроки',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 4),
        Text(
          lessons.isEmpty ? 'Создайте первый урок, чтобы начать' : 'Пройдено $completedCount из ${lessons.length}',
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < lessons.length; i++)
          _ChainNode(
            isFirst: i == 0,
            isLast: i == lessons.length - 1 && !canCreateNext,
            state: lessons[i].isCompleted ? _ChainNodeState.completed : _ChainNodeState.inProgress,
            title: 'Урок ${lessons[i].number}',
            subtitle: lessons[i].isCompleted
                ? 'Пройден'
                : 'Изучено ${lessons[i].learnedCount} из ${lessons[i].wordCount}',
            progress: lessons[i].wordCount == 0 ? 0.0 : lessons[i].learnedCount / lessons[i].wordCount,
            onTap: () => _openLesson(lessons[i].id),
          ),
        if (canCreateNext)
          _ChainNode(
            isFirst: lessons.isEmpty,
            isLast: true,
            state: _ChainNodeState.unlocked,
            title: 'Урок $nextNumber',
            subtitle: lessons.isEmpty ? 'Создать урок' : 'Доступен для создания',
            progress: null,
            onTap: _createNextLesson,
          ),
      ],
    );
  }
}

enum _ChainNodeState { completed, inProgress, unlocked }

/// One link of the vertical lesson chain: a status circle (with a subtle
/// progress ring while in progress) connected by a line to its neighbors
/// above/below, and a tappable, softly-shadowed, state-tinted card.
/// Adapted from the general "sequential chain of steps, done vs. not-done
/// look different" idea (not any particular reference design/colors/
/// assets) to GuYo's own indigo/emerald Material style.
class _ChainNode extends StatelessWidget {
  final bool isFirst;
  final bool isLast;
  final _ChainNodeState state;
  final String title;
  final String subtitle;
  final double? progress;
  final VoidCallback onTap;

  const _ChainNode({
    required this.isFirst,
    required this.isLast,
    required this.state,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineColor = Colors.grey.shade300;
    final List<Color> gradientColors;
    final Color tint;
    final IconData icon;
    switch (state) {
      case _ChainNodeState.completed:
        gradientColors = [Colors.green.shade400, Colors.teal.shade600];
        tint = Colors.green.shade600;
        icon = Icons.check_rounded;
      case _ChainNodeState.inProgress:
        gradientColors = [scheme.primary, Colors.indigo.shade900];
        tint = scheme.primary;
        icon = Icons.menu_book_rounded;
      case _ChainNodeState.unlocked:
        gradientColors = [Colors.grey.shade400, Colors.grey.shade500];
        tint = Colors.grey.shade500;
        icon = Icons.add_rounded;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Container(width: 3, height: 14, color: isFirst ? Colors.transparent : lineColor),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (state == _ChainNodeState.inProgress && progress != null && progress! > 0)
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 3,
                            backgroundColor: scheme.primary.withValues(alpha: 0.15),
                            valueColor: AlwaysStoppedAnimation(Colors.amber.shade600),
                          ),
                        ),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: gradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(color: tint.withValues(alpha: 0.45), blurRadius: 10, offset: const Offset(0, 3)),
                          ],
                        ),
                        child: Icon(icon, color: Colors.white, size: 19),
                      ),
                    ],
                  ),
                ),
                Expanded(child: Container(width: 3, color: isLast ? Colors.transparent : lineColor)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Material(
                color: state == _ChainNodeState.unlocked ? Colors.grey.shade50 : tint.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: state == _ChainNodeState.unlocked
                            ? Colors.grey.shade300
                            : tint.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.grey.shade900),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: state == _ChainNodeState.completed
                                      ? Colors.green.shade700
                                      : state == _ChainNodeState.unlocked
                                          ? Colors.black45
                                          : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          state == _ChainNodeState.unlocked ? Icons.add_circle_outline : Icons.chevron_right,
                          color: state == _ChainNodeState.unlocked ? tint : Colors.black38,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
