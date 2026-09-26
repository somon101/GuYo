import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/word.dart';
import '../widgets/premium_ui.dart';
import '../widgets/word_card.dart';

/// Word selection for a new lesson: either a random count (1-15) or a
/// manual, per-word pick (also capped at 15), grouped by category so
/// browsing is manageable even for a large dictionary. Both modes draw from
/// the SAME pool -- GET /dictionaries/{id}/lesson-candidate-words, every
/// word in this dictionary the user hasn't already learned -- and both
/// ultimately just call POST /lessons, which is the only place a Lesson
/// actually gets created (never client-side).
class LessonCreateScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const LessonCreateScreen({super.key, required this.dictionary});

  @override
  State<LessonCreateScreen> createState() => _LessonCreateScreenState();
}

const int _maxLessonWords = 15;

enum _Mode { random, manual }

class _LessonCreateScreenState extends State<LessonCreateScreen> {
  bool _isLoading = true;
  String? _loadError;
  List<GuyoWord> _candidates = [];
  // Only decides each card's level stripe; failing to load it just leaves
  // the stripes neutral.
  List<WordLevelSummary> _levels = [];

  _Mode _mode = _Mode.random;
  int _randomCount = 5;
  final Set<int> _selectedIds = {};

  bool _isSubmitting = false;
  String? _submitError;

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
      // Neutral stripes are an acceptable degraded state.
    }
  }

  void _toggleWord(int wordId) {
    setState(() {
      if (_selectedIds.contains(wordId)) {
        _selectedIds.remove(wordId);
      } else if (_selectedIds.length < _maxLessonWords) {
        _selectedIds.add(wordId);
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final result = await ApiClient.instance.fetchLessonCandidateWords(widget.dictionary.id);
      if (!mounted) return;
      setState(() {
        _candidates = result.words;
        _randomCount = result.words.isEmpty ? 0 : (result.words.length < _maxLessonWords ? result.words.length : _maxLessonWords).clamp(1, _maxLessonWords);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить доступные слова';
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      if (_mode == _Mode.random) {
        await ApiClient.instance.createLesson(dictionaryId: widget.dictionary.id, randomCount: _randomCount);
      } else {
        await ApiClient.instance.createLesson(dictionaryId: widget.dictionary.id, wordIds: _selectedIds.toList());
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 429) {
        // The daily/weekly lesson limit -- the backend's own wording, plus
        // a way to Premium, rather than an error line under the button.
        setState(() => _isSubmitting = false);
        await showLessonLimitDialog(context, e.message);
        return;
      }
      setState(() {
        _isSubmitting = false;
        _submitError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = 'Не удалось создать урок';
      });
    }
  }

  Map<String, List<GuyoWord>> _groupByCategory(List<GuyoWord> words) {
    final groups = <String, List<GuyoWord>>{};
    for (final w in words) {
      final name = (w.categoryName == null || w.categoryName!.isEmpty) ? 'Без категории' : w.categoryName!;
      groups.putIfAbsent(name, () => []).add(w);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый урок')),
      body: _buildBody(),
      bottomNavigationBar: _isLoading || _loadError != null || _candidates.isEmpty ? null : _buildSubmitBar(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
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
      );
    }
    if (_candidates.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Все доступные слова уже изучены -- новых слов для урока нет.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(value: _Mode.random, label: Text('Случайно'), icon: Icon(Icons.shuffle)),
              ButtonSegment(value: _Mode.manual, label: Text('Вручную'), icon: Icon(Icons.checklist)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ),
        Expanded(
          child: _mode == _Mode.random ? _buildRandomPicker() : _buildManualPicker(),
        ),
        if (_submitError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(_submitError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _buildRandomPicker() {
    final maxCount = _candidates.length < _maxLessonWords ? _candidates.length : _maxLessonWords;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Сколько слов взять в урок?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('От 1 до $maxCount (доступно: ${_candidates.length})', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: _randomCount > 1 ? () => setState(() => _randomCount--) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '$_randomCount',
                    key: const ValueKey('lesson-random-count'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _randomCount < maxCount ? () => setState(() => _randomCount++) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualPicker() {
    final groups = _groupByCategory(_candidates);
    final categoryNames = groups.keys.toList();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'Выбрано: ${_selectedIds.length}/$_maxLessonWords',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
        for (final categoryName in categoryNames)
          ExpansionTile(
            title: Text(categoryName),
            subtitle: Text('${groups[categoryName]!.length} слов'),
            children: [
              for (final word in groups[categoryName]!)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: WordCard(
                    word: word.word,
                    transcription: word.transcription,
                    translation: word.translation,
                    audioUrl: word.wordAudioUrl,
                    level: WordLevelView.resolve(word.wordLevelId, word.wordLevelName, _levels),
                    selected: _selectedIds.contains(word.id),
                    onTap: () => _toggleWord(word.id),
                    trailing: Checkbox(
                      key: ValueKey('lesson-word-checkbox-${word.id}'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      value: _selectedIds.contains(word.id),
                      onChanged: (_) => _toggleWord(word.id),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildSubmitBar() {
    final canSubmit = !_isSubmitting && (_mode == _Mode.random ? _randomCount >= 1 : _selectedIds.isNotEmpty);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: canSubmit ? _submit : null,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_mode == _Mode.random ? 'Создать урок' : 'Создать урок (${_selectedIds.length})'),
        ),
      ),
    );
  }
}
