import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../api/api_client.dart';
import '../models/lesson.dart';
import 'lesson_complete_screen.dart';

enum _MicState { idle, recording, processing, result }

/// "Произнеси слово", as one of a Lesson's exercises: shows one of the
/// lesson's own words, the user taps the mic and says it, an on-device
/// speech recognizer (package:speech_to_text -- Android's own built-in
/// engine, no backend/API key/audio upload involved) turns that into text,
/// and the app compares the recognized text to the target word right here
/// -- the exact same "backend decides the round and points, client does
/// the comparison and reports only {word_id, is_correct}" principle every
/// other exercise already follows.
///
/// If speech recognition isn't available on this device (unsupported
/// hardware, no recognizer installed, permission permanently denied), the
/// screen says so plainly instead of pretending to work -- it never
/// fabricates a result.
class SpeakingWordScreen extends StatefulWidget {
  final int lessonId;
  final int lessonNumber;
  const SpeakingWordScreen({super.key, required this.lessonId, required this.lessonNumber});

  @override
  State<SpeakingWordScreen> createState() => _SpeakingWordScreenState();
}

class _SpeakingWordScreenState extends State<SpeakingWordScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  SpeakingWordRound? _round;
  int _index = 0;
  int _correctCount = 0;
  bool _lessonCompleted = false;

  final SpeechToText _speech = SpeechToText();
  bool _speechChecked = false;
  bool _speechAvailable = false;

  _MicState _micState = _MicState.idle;
  String _recognizedText = '';
  bool? _isCorrect;

  @override
  void initState() {
    super.initState();
    _load();
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
        // "notListening"/"done" mean the engine stopped on its own (e.g.
        // silence timeout) -- if that happened before onResult ever gave a
        // final result, treat it the same as a failed recognition attempt
        // rather than leaving the mic stuck showing "recording".
        if ((status == 'notListening' || status == 'done') && mounted && _micState == _MicState.recording) {
          setState(() => _micState = _MicState.idle);
        }
      },
      onError: (_) {
        if (mounted && _micState == _MicState.recording) {
          setState(() => _micState = _MicState.idle);
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _speechChecked = true;
      _speechAvailable = available;
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final round = await ApiClient.instance.fetchLessonSpeakingWordRound(widget.lessonId);
      if (!mounted) return;
      setState(() {
        _round = round;
        _index = 0;
        _correctCount = 0;
        _isLoading = false;
      });
      _resetItemState();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось загрузить упражнение';
      });
    }
  }

  void _resetItemState() {
    setState(() {
      _micState = _MicState.idle;
      _recognizedText = '';
      _isCorrect = null;
    });
  }

  Future<void> _startListening() async {
    if (!_speechAvailable || _micState != _MicState.idle) return;
    setState(() {
      _micState = _MicState.recording;
      _recognizedText = '';
    });
    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        if (!mounted) return;
        setState(() => _recognizedText = result.recognizedWords);
        if (result.finalResult) _onFinalResult(result.recognizedWords);
      },
    );
  }

  Future<void> _onFinalResult(String recognized) async {
    await _speech.stop();
    if (!mounted) return;

    if (recognized.trim().isEmpty) {
      // A technical non-detection (silence, background noise) -- not a
      // demonstrated wrong answer, so this doesn't score anything. The
      // user can just tap the mic again.
      setState(() => _micState = _MicState.idle);
      _showSnack('Речь не распознана, попробуйте ещё раз');
      return;
    }

    setState(() => _micState = _MicState.processing);
    final item = _round!.items[_index];
    final matchPercent = _similarityPercent(recognized, item.word);
    final correct = matchPercent >= _round!.matchThreshold;

    setState(() {
      _isCorrect = correct;
      _micState = _MicState.result;
      if (correct) _correctCount++;
    });

    final submit = ApiClient.instance
        .submitLessonAnswer(widget.lessonId, 'speaking_word', wordId: item.wordId, isCorrect: correct)
        .then((res) {
      if (res.lessonCompleted) _lessonCompleted = true;
    }).catchError((_) {});
    await Future.wait([submit, Future.delayed(const Duration(milliseconds: 1100))]);

    if (!mounted) return;
    _advance();
  }

  void _advance() {
    final round = _round!;
    if (_index + 1 < round.items.length) {
      setState(() => _index++);
      _resetItemState();
    } else {
      setState(() => _index = round.items.length); // past the last index marks completion
    }
  }

  void _showSnack(String text) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || !_speechChecked) {
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
    if (!_speechAvailable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic_off_rounded, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'Распознавание речи недоступно',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Проверьте, что микрофон разрешён приложению и на устройстве установлен сервис распознавания речи.',
                style: TextStyle(color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _initSpeech, child: const Text('Проверить снова')),
            ],
          ),
        ),
      );
    }

    if (_index >= round.items.length) {
      return _RoundCompleteView(
        correctCount: _correctCount,
        total: round.items.length,
        lessonCompleted: _lessonCompleted,
        onPlayAgain: _load,
        onBackToLesson: () => _lessonCompleted
            ? Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => LessonCompleteScreen(lessonNumber: widget.lessonNumber)),
              )
            : Navigator.of(context).pop(),
      );
    }

    final item = round.items[_index];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'Слово ${_index + 1} из ${round.items.length}'
            '${_correctCount > 0 ? '  ·  Правильно: $_correctCount' : ''}',
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _WordCard(item: item),
                    const SizedBox(height: 36),
                    _MicButton(state: _micState, onTap: _startListening),
                    const SizedBox(height: 20),
                    _StateLabel(state: _micState, recognizedText: _recognizedText, isCorrect: _isCorrect, target: item.word),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Normalized similarity 0-100 between [recognized] and [target], based on
/// Levenshtein edit distance -- tolerant of the small variations real
/// speech recognition produces (a dropped/extra letter, minor
/// mis-hearing), but not of a genuinely different word, since edit
/// distance grows with how different the words actually are. Deliberately
/// simple and fully reproducible: no ML "pronunciation score" is invented
/// here, since speech_to_text itself doesn't provide one.
int _similarityPercent(String recognized, String target) {
  String normalize(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), '');
  final a = normalize(recognized);
  final b = normalize(target);
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 100;

  final distance = _levenshtein(a, b);
  final maxLen = a.length > b.length ? a.length : b.length;
  final ratio = 1.0 - (distance / maxLen);
  return (ratio * 100).clamp(0, 100).round();
}

int _levenshtein(String a, String b) {
  final la = a.length, lb = b.length;
  var prev = List<int>.generate(lb + 1, (j) => j);
  for (var i = 1; i <= la; i++) {
    final current = List<int>.filled(lb + 1, 0);
    current[0] = i;
    for (var j = 1; j <= lb; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [
        current[j - 1] + 1, // insertion
        prev[j] + 1, // deletion
        prev[j - 1] + cost, // substitution
      ].reduce((x, y) => x < y ? x : y);
    }
    prev = current;
  }
  return prev[lb];
}

class _WordCard extends StatelessWidget {
  final SpeakingWordItem item;
  const _WordCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    final hasTranscription = item.transcription != null && item.transcription!.isNotEmpty;
    return Container(
      key: ValueKey('speaking-word-card-${item.wordId}'),
      constraints: const BoxConstraints(maxWidth: 340),
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
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(height: 0),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            item.word,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          if (hasTranscription)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(item.transcription!, style: const TextStyle(fontSize: 15, color: Colors.black45)),
            ),
        ],
      ),
    );
  }
}

class _MicButton extends StatefulWidget {
  final _MicState state;
  final VoidCallback onTap;
  const _MicButton({required this.state, required this.onTap});

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRecording = widget.state == _MicState.recording;
    final isBusy = widget.state == _MicState.processing;

    final Color color;
    final IconData icon;
    switch (widget.state) {
      case _MicState.idle:
        color = scheme.primary;
        icon = Icons.mic_rounded;
      case _MicState.recording:
        color = Colors.red.shade500;
        icon = Icons.mic_rounded;
      case _MicState.processing:
        color = Colors.amber.shade700;
        icon = Icons.hourglass_top_rounded;
      case _MicState.result:
        color = Colors.grey.shade400;
        icon = Icons.mic_none_rounded;
    }

    return GestureDetector(
      onTap: (widget.state == _MicState.idle) ? widget.onTap : null,
      child: SizedBox(
        width: 128,
        height: 128,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isRecording)
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  final scale = 1.0 + _pulse.value * 0.25;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.18)),
                    ),
                  );
                },
              ),
            Container(
              key: const ValueKey('speaking-word-mic-button'),
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: isBusy
                  ? const Padding(
                      padding: EdgeInsets.all(28),
                      child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                    )
                  : Icon(icon, color: Colors.white, size: 42),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateLabel extends StatelessWidget {
  final _MicState state;
  final String recognizedText;
  final bool? isCorrect;
  final String target;
  const _StateLabel({required this.state, required this.recognizedText, required this.isCorrect, required this.target});

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _MicState.idle:
        return const Text('Нажмите и произнесите слово', style: TextStyle(color: Colors.black54, fontSize: 14));
      case _MicState.recording:
        return Text(
          recognizedText.isEmpty ? 'Слушаю…' : recognizedText,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        );
      case _MicState.processing:
        return const Text('Проверяю…', style: TextStyle(color: Colors.black54, fontSize: 14));
      case _MicState.result:
        final correct = isCorrect ?? false;
        final color = correct ? Colors.green : Colors.red;
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(correct ? Icons.check_circle : Icons.cancel, color: color.shade600, size: 20),
                const SizedBox(width: 6),
                Text(
                  correct ? 'Правильно' : 'Неправильно',
                  style: TextStyle(fontWeight: FontWeight.w700, color: color.shade800, fontSize: 15),
                ),
              ],
            ),
            if (!correct) ...[
              const SizedBox(height: 4),
              Text(
                'Услышано: «$recognizedText», нужно: «$target»',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );
    }
  }
}

class _RoundCompleteView extends StatelessWidget {
  final int correctCount;
  final int total;
  final bool lessonCompleted;
  final VoidCallback onPlayAgain;
  final VoidCallback onBackToLesson;

  const _RoundCompleteView({
    required this.correctCount,
    required this.total,
    required this.lessonCompleted,
    required this.onPlayAgain,
    required this.onBackToLesson,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 56),
          const SizedBox(height: 12),
          const Text('Упражнение завершено!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Правильно: $correctCount из $total', style: const TextStyle(color: Colors.black54)),
          if (lessonCompleted) ...[
            const SizedBox(height: 8),
            const Text('Урок пройден!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: onBackToLesson, icon: const Icon(Icons.arrow_back), label: const Text('К уроку')),
          const SizedBox(height: 8),
          if (!lessonCompleted)
            OutlinedButton.icon(onPressed: onPlayAgain, icon: const Icon(Icons.refresh), label: const Text('Играть ещё раз')),
        ],
      ),
    );
  }
}
