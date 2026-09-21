import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/exercise.dart';
import '../models/lesson.dart';
import '../models/quest.dart';
import '../models/word.dart';
import '../widgets/audio_button.dart';

/// One quest attempt: fetches a ONE-target-word round, renders whichever
/// of the 5 exercise types the quest uses, and reports exactly one
/// {word_id, is_correct} back -- same "backend decides the round and
/// points, client only compares" principle the Lesson screens already
/// follow. Deliberately NOT a multi-round chain like a Lesson: a quest is
/// over the moment this one word is answered.
class QuestAttemptScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  final int questId;
  final String questName;
  const QuestAttemptScreen({super.key, required this.dictionary, required this.questId, required this.questName});

  @override
  State<QuestAttemptScreen> createState() => _QuestAttemptScreenState();
}

class _QuestAttemptScreenState extends State<QuestAttemptScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  QuestRound? _round;
  QuestAnswerResult? _result;

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
      _result = null;
    });
    try {
      final round = await ApiClient.instance.fetchQuestRound(widget.questId, widget.dictionary.id);
      if (!mounted) return;
      setState(() {
        _round = round;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось загрузить квест';
      });
    }
  }

  Future<void> _submit(bool isCorrect) async {
    final round = _round;
    if (round == null || _result != null) return;
    try {
      final result = await ApiClient.instance.submitQuestAnswer(
        widget.questId,
        widget.dictionary.id,
        wordId: round.wordId,
        isCorrect: isCorrect,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Не удалось сохранить результат');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.questName)),
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: _buildBody())),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _round == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Повторить')),
          ],
        ),
      );
    }
    final round = _round!;
    final result = _result;
    if (result != null) {
      return _QuestResultView(result: result, onDone: () => Navigator.of(context).pop());
    }
    switch (round.exerciseKey) {
      case 'true_or_false':
        return _TrueOrFalseQuest(payload: round.payload, onAnswer: _submit);
      case 'build_word':
        return _BuildWordQuest(payload: round.payload, onAnswer: _submit);
      case 'speaking_word':
        return _SpeakingWordQuest(payload: round.payload, onAnswer: _submit);
      case 'listen_word':
        return _ListenWordQuest(payload: round.payload, onAnswer: _submit);
      case 'matching':
        return _MatchingQuest(payload: round.payload, onAnswer: _submit);
      default:
        return const Center(child: Text('Неизвестный тип упражнения'));
    }
  }
}

class _QuestResultView extends StatelessWidget {
  final QuestAnswerResult result;
  final VoidCallback onDone;
  const _QuestResultView({required this.result, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final correct = result.isCorrect;
    final color = correct ? Colors.green : Colors.red;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(correct ? Icons.check_circle : Icons.cancel, color: color.shade600, size: 64),
          const SizedBox(height: 16),
          Text(
            correct ? 'Квест выполнен!' : 'Не в этот раз',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text('Очки закрепления слова: ${result.score}', style: const TextStyle(color: Colors.black54)),
          if (result.rewardGranted > 0) ...[
            const SizedBox(height: 6),
            Text(
              '+${result.rewardGranted} рейтинговых очков',
              style: TextStyle(color: Colors.amber.shade800, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: onDone, child: const Text('Готово')),
        ],
      ),
    );
  }
}

// --- Правда или ложь ---------------------------------------------------------

class _TrueOrFalseQuest extends StatelessWidget {
  final Map<String, dynamic> payload;
  final ValueChanged<bool> onAnswer;
  const _TrueOrFalseQuest({required this.payload, required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    final round = TrueOrFalseRound.fromJson(payload);
    final item = round.items.first;
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasImage) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        ApiClient.instance.mediaUrl(item.imageUrl!),
                        height: 140,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(height: 0),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(item.original, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                      if (item.wordAudioUrl != null) ...[
                        const SizedBox(width: 8),
                        AudioButton(url: ApiClient.instance.mediaUrl(item.wordAudioUrl!), size: 22),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(item.shownTranslation, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: () => onAnswer(item.isCorrect == false), child: const Text('Ложь')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(onPressed: () => onAnswer(item.isCorrect == true), child: const Text('Правда')),
            ),
          ],
        ),
      ],
    );
  }
}

// --- Собери слово --------------------------------------------------------------

class _BuildWordQuest extends StatefulWidget {
  final Map<String, dynamic> payload;
  final ValueChanged<bool> onAnswer;
  const _BuildWordQuest({required this.payload, required this.onAnswer});

  @override
  State<_BuildWordQuest> createState() => _BuildWordQuestState();
}

class _Tile {
  final String id;
  final String letter;
  const _Tile(this.id, this.letter);
}

class _BuildWordQuestState extends State<_BuildWordQuest> {
  late final BuildWordRound _round;
  late final BuildWordItem _item;
  List<_Tile> _pool = [];
  List<_Tile?> _slots = [];
  List<Color?> _slotColors = [];
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _round = BuildWordRound.fromJson(widget.payload);
    _item = _round.items.first;
    _pool = [for (var i = 0; i < _item.letters.length; i++) _Tile('$i-${_item.letters[i]}', _item.letters[i])];
    _slots = List<_Tile?>.filled(_item.correctWord.length, null);
    _slotColors = List<Color?>.filled(_item.correctWord.length, null);
  }

  void _tapPool(_Tile tile) {
    if (_locked) return;
    final emptyIndex = _slots.indexWhere((s) => s == null);
    if (emptyIndex == -1) return;
    setState(() {
      _slots[emptyIndex] = tile;
      _pool = _pool.where((t) => t.id != tile.id).toList();
      _slotColors = List<Color?>.filled(_slots.length, null);
    });
  }

  void _tapSlot(int i) {
    if (_locked) return;
    final tile = _slots[i];
    if (tile == null) return;
    setState(() {
      _slots[i] = null;
      _pool = [..._pool, tile];
      _slotColors = List<Color?>.filled(_slots.length, null);
    });
  }

  void _check() {
    if (_slots.contains(null) || _locked) return;
    var allCorrect = true;
    final colors = <Color?>[];
    for (var i = 0; i < _slots.length; i++) {
      final guess = _slots[i]!.letter;
      final correct = _item.correctWord[i];
      final matches = _round.caseSensitive ? guess == correct : guess.toLowerCase() == correct.toLowerCase();
      colors.add(matches ? Colors.green.shade600 : Colors.red.shade600);
      if (!matches) allCorrect = false;
    }
    setState(() {
      _slotColors = colors;
      _locked = true;
    });
    Future.delayed(const Duration(milliseconds: 500), () => widget.onAnswer(allCorrect));
  }

  @override
  Widget build(BuildContext context) {
    final hasTranslationAudio = _item.translationAudioUrl != null && _item.translationAudioUrl!.isNotEmpty;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(child: Text(_item.translation, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
              if (hasTranslationAudio) ...[
                const SizedBox(width: 8),
                AudioButton(url: ApiClient.instance.mediaUrl(_item.translationAudioUrl!)),
              ],
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _slots.length; i++)
                  _LetterSlot(letter: _slots[i]?.letter, color: _slotColors[i], onTap: () => _tapSlot(i)),
              ],
            ),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: (!_slots.contains(null) && !_locked) ? _check : null,
            child: const Text('Проверить'),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [for (final tile in _pool) _LetterButton(key: ValueKey(tile.id), letter: tile.letter, onTap: () => _tapPool(tile))],
        ),
      ],
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
    return InkWell(
      onTap: letter != null ? onTap : null,
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
        child: Text(letter ?? '', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
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
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
          child: Text(letter, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

// --- Произнеси слово ------------------------------------------------------------

enum _MicState { idle, recording, processing, result }

class _SpeakingWordQuest extends StatefulWidget {
  final Map<String, dynamic> payload;
  final ValueChanged<bool> onAnswer;
  const _SpeakingWordQuest({required this.payload, required this.onAnswer});

  @override
  State<_SpeakingWordQuest> createState() => _SpeakingWordQuestState();
}

class _SpeakingWordQuestState extends State<_SpeakingWordQuest> {
  late final SpeakingWordRound _round;
  final SpeechToText _speech = SpeechToText();
  bool _speechChecked = false;
  bool _speechAvailable = false;
  _MicState _state = _MicState.idle;
  String _recognized = '';
  bool? _isCorrect;

  @override
  void initState() {
    super.initState();
    _round = SpeakingWordRound.fromJson(widget.payload);
    _initSpeech();
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if ((status == 'notListening' || status == 'done') && mounted && _state == _MicState.recording) {
          setState(() => _state = _MicState.idle);
        }
      },
      onError: (_) {
        if (mounted && _state == _MicState.recording) setState(() => _state = _MicState.idle);
      },
    );
    if (!mounted) return;
    setState(() {
      _speechChecked = true;
      _speechAvailable = available;
    });
  }

  Future<void> _start() async {
    if (!_speechAvailable || _state != _MicState.idle) return;
    setState(() {
      _state = _MicState.recording;
      _recognized = '';
    });
    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        if (!mounted) return;
        setState(() => _recognized = result.recognizedWords);
        if (result.finalResult) _onFinal(result.recognizedWords);
      },
    );
  }

  Future<void> _onFinal(String recognized) async {
    await _speech.stop();
    if (!mounted) return;
    if (recognized.trim().isEmpty) {
      setState(() => _state = _MicState.idle);
      return;
    }
    setState(() => _state = _MicState.processing);
    final item = _round.items.first;
    final match = _similarityPercent(recognized, item.word);
    final correct = match >= _round.matchThreshold;
    setState(() {
      _isCorrect = correct;
      _state = _MicState.result;
    });
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    widget.onAnswer(correct);
  }

  @override
  Widget build(BuildContext context) {
    if (!_speechChecked) return const Center(child: CircularProgressIndicator());
    if (!_speechAvailable) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_off_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('Распознавание речи недоступно', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _initSpeech, child: const Text('Проверить снова')),
          ],
        ),
      );
    }
    final item = _round.items.first;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.word, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          if (item.transcription != null) Text(item.transcription!, style: const TextStyle(color: Colors.black45)),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: _state == _MicState.idle ? _start : null,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _state == _MicState.recording ? Colors.red.shade500 : Theme.of(context).colorScheme.primary,
              ),
              child: _state == _MicState.processing
                  ? const Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator(color: Colors.white))
                  : const Icon(Icons.mic_rounded, color: Colors.white, size: 42),
            ),
          ),
          const SizedBox(height: 16),
          if (_state == _MicState.result)
            Text(
              _isCorrect == true ? 'Правильно' : 'Неправильно (услышано: «$_recognized»)',
              style: TextStyle(color: _isCorrect == true ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            )
          else
            Text(
              _state == _MicState.recording ? (_recognized.isEmpty ? 'Слушаю…' : _recognized) : 'Нажмите и произнесите слово',
              style: const TextStyle(color: Colors.black54),
            ),
        ],
      ),
    );
  }
}

int _similarityPercent(String recognized, String target) {
  String normalize(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), '');
  final a = normalize(recognized);
  final b = normalize(target);
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 100;
  final distance = _levenshtein(a, b);
  final maxLen = max(a.length, b.length);
  return ((1.0 - (distance / maxLen)) * 100).clamp(0, 100).round();
}

int _levenshtein(String a, String b) {
  final la = a.length, lb = b.length;
  var prev = List<int>.generate(lb + 1, (j) => j);
  for (var i = 1; i <= la; i++) {
    final current = List<int>.filled(lb + 1, 0);
    current[0] = i;
    for (var j = 1; j <= lb; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [current[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
    }
    prev = current;
  }
  return prev[lb];
}

// --- Услышь слово ----------------------------------------------------------------

class _ListenWordQuest extends StatefulWidget {
  final Map<String, dynamic> payload;
  final ValueChanged<bool> onAnswer;
  const _ListenWordQuest({required this.payload, required this.onAnswer});

  @override
  State<_ListenWordQuest> createState() => _ListenWordQuestState();
}

class _ListenWordQuestState extends State<_ListenWordQuest> {
  late final ListenWordRound _round;
  final _player = AudioPlayer();
  ListenWordOption? _selected;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _round = ListenWordRound.fromJson(widget.payload);
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    final url = _round.items.first.wordAudioUrl;
    if (url == null) return;
    try {
      await _player.play(UrlSource(ApiClient.instance.mediaUrl(url)));
    } catch (_) {}
  }

  void _tap(ListenWordOption option) {
    if (_locked) return;
    final item = _round.items.first;
    final correct = option.wordId == item.wordId;
    setState(() {
      _selected = option;
      _locked = true;
    });
    Future.delayed(const Duration(milliseconds: 500), () => widget.onAnswer(correct));
  }

  @override
  Widget build(BuildContext context) {
    final item = _round.items.first;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filled(onPressed: _play, icon: const Icon(Icons.volume_up_rounded, size: 32)),
                const SizedBox(height: 8),
                const Text('Прослушайте и выберите слово', style: TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final option in item.options)
              OutlinedButton(
                onPressed: _locked ? null : () => _tap(option),
                style: OutlinedButton.styleFrom(
                  backgroundColor: _selected?.wordId == option.wordId
                      ? (option.wordId == item.wordId ? Colors.green.shade50 : Colors.red.shade50)
                      : null,
                ),
                child: Text(option.word),
              ),
          ],
        ),
      ],
    );
  }
}

// --- Сопоставление -----------------------------------------------------------------
// Simplified for a single-target quest: the target word (always first --
// see backend/app/quests/rounds.py's build_matching_round) plus a few
// sibling translations as multiple-choice options, rather than the full
// multi-pair board "Сопоставление" uses in a Lesson (which has no single
// "target" word to score against).

class _MatchingQuest extends StatefulWidget {
  final Map<String, dynamic> payload;
  final ValueChanged<bool> onAnswer;
  const _MatchingQuest({required this.payload, required this.onAnswer});

  @override
  State<_MatchingQuest> createState() => _MatchingQuestState();
}

class _MatchingQuestState extends State<_MatchingQuest> {
  late final GuyoWord _target;
  late final List<GuyoWord> _options;
  GuyoWord? _selected;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    final words = (widget.payload['words'] as List<dynamic>).map((e) => GuyoWord.fromJson(e as Map<String, dynamic>)).toList();
    _target = words.first;
    _options = [...words]..shuffle();
  }

  void _tap(GuyoWord option) {
    if (_locked) return;
    final correct = option.id == _target.id;
    setState(() {
      _selected = option;
      _locked = true;
    });
    Future.delayed(const Duration(milliseconds: 500), () => widget.onAnswer(correct));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_target.word, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                if (_target.transcription != null)
                  Text(_target.transcription!, style: const TextStyle(color: Colors.black45)),
                const SizedBox(height: 8),
                const Text('Выберите перевод', style: TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final option in _options)
              OutlinedButton(
                onPressed: _locked ? null : () => _tap(option),
                style: OutlinedButton.styleFrom(
                  backgroundColor: _selected?.id == option.id
                      ? (option.id == _target.id ? Colors.green.shade50 : Colors.red.shade50)
                      : null,
                ),
                child: Text(option.translation),
              ),
          ],
        ),
      ],
    );
  }
}
