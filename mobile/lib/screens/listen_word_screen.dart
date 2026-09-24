import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/lesson.dart';
import 'lesson_exercise_flow.dart';

/// "Услышь слово", as one of a Lesson's exercises: the backend hands back a
/// round built from THIS lesson's own words (see ApiClient.
/// fetchLessonListenWordRound) -- one word's own recording per task, a
/// shuffled multiple-choice among other lesson words. Correctness is
/// decided purely by comparing the tapped option's word_id to the item's
/// own word_id -- never by comparing text -- same principle as every other
/// exercise here (Сопоставление, Правда или ложь).
///
/// After every answer, this screen reports {word_id, is_correct} to the
/// backend via submitLessonAnswer, which is the ONLY place a word's score
/// actually changes.
class ListenWordScreen extends StatefulWidget {
  final int lessonId;
  final int lessonNumber;
  const ListenWordScreen({super.key, required this.lessonId, required this.lessonNumber});

  @override
  State<ListenWordScreen> createState() => _ListenWordScreenState();
}

class _ListenWordScreenState extends State<ListenWordScreen> with LessonExerciseFlow {
  bool _isLoading = true;
  String? _errorMessage;
  List<ListenWordItem> _items = [];
  int _index = 0;
  int _correctCount = 0;
  ListenWordOption? _selected;
  bool _isLocked = false;

  final _player = AudioPlayer();
  bool _isPlayingAudio = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final round = await ApiClient.instance.fetchLessonListenWordRound(widget.lessonId);
      if (!mounted) return;
      setState(() {
        _items = round.items;
        _index = 0;
        _correctCount = 0;
        _selected = null;
        _isLocked = false;
        _isLoading = false;
      });
      // Nothing left for this exercise to test -- skip it instead of
      // stalling the lesson on a dead end.
      if (round.items.isEmpty) finishExercise();
      if (round.items.isNotEmpty) _playAudio();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось загрузить упражнение';
      });
    }
  }

  Future<void> _playAudio() async {
    if (_index >= _items.length) return;
    final url = _items[_index].wordAudioUrl;
    if (url == null || url.isEmpty) return;
    try {
      await _player.stop();
      if (!mounted) return;
      setState(() => _isPlayingAudio = true);
      await _player.play(UrlSource(ApiClient.instance.mediaUrl(url)));
      _player.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _isPlayingAudio = false);
      });
    } catch (_) {
      if (mounted) setState(() => _isPlayingAudio = false);
    }
  }

  Future<void> _choose(ListenWordOption option) async {
    if (_isLocked || _index >= _items.length) return;
    final item = _items[_index];
    final correct = option.wordId == item.wordId;
    setState(() {
      _selected = option;
      _isLocked = true;
      if (correct) _correctCount++;
    });

    // The result itself is no longer read here: whether the lesson is
    // complete is decided once, at the end, by the lesson's own results
    // screen. Still awaited, so the answer is saved before the lesson
    // moves on to the next exercise.
    final submit = ApiClient.instance
        .submitLessonAnswer(widget.lessonId, 'listen_word', wordId: item.wordId, isCorrect: correct)
        .then<void>((_) {})
        .catchError((_) {
      // A failed score update must never interrupt the flow item by item.
    });
    await Future.wait([submit, Future.delayed(const Duration(milliseconds: 700))]);

    if (!mounted) return;
    setState(() {
      _index++;
      _selected = null;
      _isLocked = false;
    });
    if (_index < _items.length) {
      _playAudio();
    } else {
      // Last item answered -- the lesson runner takes over straight away.
      finishExercise();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Для этого упражнения пока нет слов', textAlign: TextAlign.center),
        ),
      );
    }

    final isRoundComplete = _index >= _items.length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'Правильно: $_correctCount/${_items.length}',
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: isRoundComplete
                ? const LessonExerciseHandoff()
                : Column(
                    // Carries the current item's own (correct) word_id for
                    // integration tests to read -- otherwise a test would
                    // have no way to know which of the shuffled options is
                    // correct without racing the backend's own random
                    // selection/shuffle with a second, separate call. Same
                    // convention as BuildWordScreen/BuildPhraseScreen.
                    key: ValueKey('listen-word-active-${_items[_index].wordId}'),
                    children: [
                      _ListenPrompt(isPlaying: _isPlayingAudio, onReplay: _playAudio),
                      const SizedBox(height: 24),
                      Expanded(
                        child: SingleChildScrollView(
                          child: _OptionsList(item: _items[_index], selected: _selected, onSelect: _choose),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The compact "what to listen to" control: big enough to be the obvious
/// first action, but only one row tall -- the options below are the real
/// content of the screen.
class _ListenPrompt extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onReplay;
  const _ListenPrompt({required this.isPlaying, required this.onReplay});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onReplay,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isPlaying
                        ? [scheme.primary.withValues(alpha: 0.7), scheme.primary]
                        : [scheme.primary, Colors.indigo.shade900],
                  ),
                ),
                child: Icon(isPlaying ? Icons.graphic_eq_rounded : Icons.volume_up_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Прослушать ещё раз',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
                ),
              ),
              Icon(Icons.replay_rounded, color: scheme.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionsList extends StatelessWidget {
  final ListenWordItem item;
  final ListenWordOption? selected;
  final ValueChanged<ListenWordOption> onSelect;
  const _OptionsList({required this.item, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final isRevealed = selected != null;
    return Column(
      children: [
        for (final option in item.options) ...[
          _OptionTile(
            option: option,
            isSelected: selected == option,
            isRevealed: isRevealed,
            isCorrectOption: option.wordId == item.wordId,
            onTap: () => onSelect(option),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  final ListenWordOption option;
  final bool isSelected;
  final bool isRevealed;
  final bool isCorrectOption;
  final VoidCallback onTap;

  const _OptionTile({
    required this.option,
    required this.isSelected,
    required this.isRevealed,
    required this.isCorrectOption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color background = Theme.of(context).colorScheme.surface;
    Color border = Colors.grey.shade300;
    Color textColor = Colors.black87;
    Widget? trailing;

    if (isRevealed) {
      if (isCorrectOption) {
        background = Colors.green.shade50;
        border = Colors.green.shade400;
        textColor = Colors.green.shade800;
        trailing = Icon(Icons.check_circle, color: Colors.green.shade600, size: 22);
      } else if (isSelected) {
        background = Colors.red.shade50;
        border = Colors.red.shade300;
        textColor = Colors.red.shade800;
        trailing = Icon(Icons.cancel, color: Colors.red.shade400, size: 22);
      } else {
        textColor = Colors.black38;
      }
    } else if (isSelected) {
      background = Theme.of(context).colorScheme.primaryContainer;
      border = Theme.of(context).colorScheme.primary;
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: isRevealed ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          key: ValueKey('listen-word-option-${option.wordId}'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 1.4)),
          child: Row(
            children: [
              Expanded(
                child: Text(option.word, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
