import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/exercise.dart';
import '../widgets/audio_button.dart';
import 'lesson_exercise_flow.dart';

/// One letter button/slot's contents, with a unique instance id so two
/// identical letters (e.g. HELLO's two L's) are always distinguishable and
/// independently tappable -- never matched or removed by letter text alone.
class _Tile {
  final String id;
  final String letter;
  const _Tile(this.id, this.letter);
}

/// "Собери слово", as one of a Lesson's exercises: shows a lesson word's
/// translation, then the player taps individual letter buttons (this word's
/// own letters, plus a few wrong ones -- both already decided by the
/// backend) to build the original word one letter at a time, tapping a
/// placed letter to undo it.
///
/// This screen never creates, copies, or persists any Word -- it only calls
/// GET /lessons/{id}/exercises/build-word (via ApiClient.
/// fetchLessonBuildWordRound), which returns exactly this lesson's fixed
/// word set, each with its letters pre-shuffled. Correctness (which letter
/// belongs at which position) is a small, UI-independent comparison against
/// BuildWordItem.correctWord -- nothing here is tied to where the letter
/// buttons happen to sit on screen. Every attempt's outcome is reported to
/// the backend via submitLessonAnswer, which is the ONLY place a word's
/// score actually changes.
class BuildWordScreen extends StatefulWidget {
  final int lessonId;
  final int lessonNumber;
  const BuildWordScreen({super.key, required this.lessonId, required this.lessonNumber});

  @override
  State<BuildWordScreen> createState() => _BuildWordScreenState();
}

class _BuildWordScreenState extends State<BuildWordScreen> with LessonExerciseFlow {
  bool _isLoading = true;
  String? _errorMessage;
  BuildWordRound? _round;

  int _currentIndex = 0;
  int _correctCount = 0;
  List<_Tile> _pool = [];
  List<_Tile?> _slots = [];
  List<Color?> _slotColors = [];
  bool _isLocked = false; // true briefly while a correct answer celebrates before advancing
  bool _hasChecked = false; // true once "Проверить" has been pressed for the current letters

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _round = null;
      _currentIndex = 0;
      _correctCount = 0;
    });
    try {
      final round = await ApiClient.instance.fetchLessonBuildWordRound(widget.lessonId);
      if (!mounted) return;
      setState(() {
        _round = round;
        _isLoading = false;
      });
      if (round.items.isNotEmpty) {
        _loadItem(0);
      } else {
        // Nothing left for this exercise to test -- skip it instead of
        // stalling the lesson on a dead end.
        finishExercise();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось загрузить упражнение';
      });
    }
  }

  void _loadItem(int index) {
    final item = _round!.items[index];
    final tiles = [
      for (var i = 0; i < item.letters.length; i++) _Tile('$index-$i-${item.letters[i]}', item.letters[i]),
    ];
    setState(() {
      _currentIndex = index;
      _pool = tiles;
      _slots = List<_Tile?>.filled(item.correctWord.length, null);
      _slotColors = List<Color?>.filled(item.correctWord.length, null);
      _isLocked = false;
      _hasChecked = false;
    });
  }

  void _tapPoolTile(_Tile tile) {
    if (_isLocked) return;
    final emptyIndex = _slots.indexWhere((s) => s == null);
    if (emptyIndex == -1) return;
    setState(() {
      _slots[emptyIndex] = tile;
      _pool = _pool.where((t) => t.id != tile.id).toList();
      _slotColors = List<Color?>.filled(_slots.length, null);
      _hasChecked = false;
    });
  }

  void _tapSlotTile(int slotIndex) {
    if (_isLocked) return;
    final tile = _slots[slotIndex];
    if (tile == null) return;
    setState(() {
      _slots[slotIndex] = null;
      _pool = [..._pool, tile];
      _slotColors = List<Color?>.filled(_slots.length, null);
      _hasChecked = false;
    });
  }

  /// Runs only when "Проверить" is pressed -- one attempt per word. The
  /// result (colored per letter) always shows, then the round always moves
  /// on to the next word, whether this attempt was right or wrong; only
  /// `_correctCount` depends on the outcome.
  Future<void> _evaluate() async {
    if (_slots.contains(null) || _hasChecked || _isLocked) return;
    final item = _round!.items[_currentIndex];
    final caseSensitive = _round!.caseSensitive;
    var allCorrect = true;
    final colors = <Color?>[];
    for (var i = 0; i < _slots.length; i++) {
      final guess = _slots[i]!.letter;
      final correct = item.correctWord[i];
      final matches = caseSensitive ? guess == correct : guess.toLowerCase() == correct.toLowerCase();
      colors.add(matches ? Colors.green.shade600 : Colors.red.shade600);
      if (!matches) allCorrect = false;
    }
    setState(() {
      _slotColors = colors;
      _hasChecked = true;
      _isLocked = true;
      if (allCorrect) _correctCount++;
    });

    // Awaited (not fire-and-forget) alongside the celebratory delay: the
    // Awaited before the word's turn ends so the score is actually saved
    // before the lesson moves on -- the next exercise's own round is built
    // from these scores, and the results screen at the end reads them too.
    final submit = ApiClient.instance
        .submitLessonAnswer(widget.lessonId, 'build_word', wordId: item.wordId, isCorrect: allCorrect)
        .then<void>((_) {})
        .catchError((_) {
      // The score update failed to save -- the round still advances; there's
      // nothing actionable to show mid-round for a single failed save.
    });
    await Future.wait([submit, Future.delayed(const Duration(milliseconds: 700))]);

    if (!mounted) return;
    _advance();
  }

  void _advance() {
    final round = _round!;
    if (_currentIndex + 1 < round.items.length) {
      _loadItem(_currentIndex + 1);
    } else {
      setState(() => _currentIndex = round.items.length); // past the last index marks completion
      // Last word built -- the lesson runner takes over straight away.
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

    final round = _round;
    if (round == null || round.items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Для этого упражнения пока нет слов', textAlign: TextAlign.center),
        ),
      );
    }

    if (_currentIndex >= round.items.length) {
      return const LessonExerciseHandoff();
    }

    final item = round.items[_currentIndex];

    // SafeArea(bottom) keeps the letter pool clear of the phone's own
    // on-screen navigation buttons; the slots sit inside Expanded+Center
    // so they float in the middle of the remaining space instead of being
    // shoved all the way down against the pool by a bare Spacer.
    return SafeArea(
      top: false,
      child: Padding(
        // Carries the current item's correct word for integration tests to
        // read (a Key has no visual/behavioral effect) -- otherwise a test
        // would have no way to know the target word without racing the
        // backend's own random selection with a second, separate call.
        key: ValueKey('build-word-active-${item.wordId}-${item.correctWord}'),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Слово ${_currentIndex + 1} из ${round.items.length}'
              '${_correctCount > 0 ? '  ·  Правильно: $_correctCount' : ''}',
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      item.translation,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (item.translationAudioUrl != null && item.translationAudioUrl!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    AudioButton(url: ApiClient.instance.mediaUrl(item.translationAudioUrl!)),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Container(
                  key: const ValueKey('build-word-slots'),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _slots.length; i++)
                        _LetterSlot(
                          letter: _slots[i]?.letter,
                          color: _slotColors[i],
                          onTap: () => _tapSlotTile(i),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('build-word-check-button'),
                onPressed: (!_slots.contains(null) && !_hasChecked && !_isLocked) ? _evaluate : null,
                child: const Text('Проверить'),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('build-word-pool'),
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tile in _pool)
                    _LetterButton(key: ValueKey(tile.id), letter: tile.letter, onTap: () => _tapPoolTile(tile)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LetterSlot extends StatelessWidget {
  final String? letter;
  final Color? color;
  final VoidCallback onTap;
  const _LetterSlot({required this.letter, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final filled = letter != null;
    return InkWell(
      onTap: filled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: color ?? Colors.grey.shade400, width: color != null ? 2 : 1),
          borderRadius: BorderRadius.circular(8),
          color: color?.withValues(alpha: 0.12),
        ),
        child: Text(
          letter ?? '',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color),
        ),
      ),
    );
  }
}

class _LetterButton extends StatelessWidget {
  final String letter;
  final VoidCallback onTap;
  const _LetterButton({super.key, required this.letter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(letter, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
