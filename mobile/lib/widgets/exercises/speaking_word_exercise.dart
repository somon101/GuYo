import '../../l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../models/lesson.dart';
import '../../services/answer_sound.dart';
import '../../theme/app_colors.dart';
import '../remote_image.dart';
import '../skeleton.dart';
import '../../services/answer_signals.dart';

enum _MicState { idle, recording, processing, result }

/// "Произнеси слово", as ONE self-contained widget: shows [item], the user
/// taps the mic and says it, an on-device speech recognizer
/// (package:speech_to_text -- no backend/API key/audio upload involved)
/// turns that into text, and the match against [item.word] is decided
/// right here (Levenshtein similarity, tolerant of small mis-hearing but
/// not of a genuinely different word). The SAME widget a Lesson host and
/// a Quest host both render for this exercise type.
///
/// If speech recognition isn't available on this device at all, this
/// shows that plainly with its own retry button rather than pretending to
/// work. [onUnavailable] additionally fires once, the first time that is
/// confirmed, for a host that wants to react (a Lesson skips straight to
/// the next exercise rather than stalling on a dead end); a host that
/// doesn't care (Quest has no "next exercise" to skip to) simply omits it.
class SpeakingWordExercise extends StatefulWidget {
  final SpeakingWordItem item;
  final int matchThreshold;
  final ValueChanged<bool> onAnswer;
  final VoidCallback? onUnavailable;

  const SpeakingWordExercise({
    super.key,
    required this.item,
    required this.matchThreshold,
    required this.onAnswer,
    this.onUnavailable,
  });

  @override
  State<SpeakingWordExercise> createState() => _SpeakingWordExerciseState();
}

class _SpeakingWordExerciseState extends State<SpeakingWordExercise> {
  /// Tries per word: a wrong word can be said again this many times in all
  /// before it counts as wrong.
  static const int _maxAttempts = 3;

  /// Longest a recording may run before it is stopped for the user --
  /// the recognizer normally ends far sooner, this only guarantees the
  /// mic can never stay stuck "on".
  static const Duration _recordingLimit = Duration(seconds: 12);

  // package:speech_to_text hands out ONE shared instance for the whole
  // app, and its initialize() only registers the status/error callbacks
  // the very first time. Every word gets a new widget, so this one binds
  // its own callbacks (see _bindCallbacks) -- otherwise they would still
  // point at the first, long-gone widget and a failed recognition would
  // leave this one stuck in "recording" for good.
  final SpeechToText _speech = SpeechToText();
  bool _speechChecked = false;
  bool _speechAvailable = false;

  _MicState _micState = _MicState.idle;
  String _recognizedText = '';
  bool? _isCorrect;
  int _attempt = 1;
  bool _answered = false;

  // One number per recording, so a late result or callback from an
  // earlier recording can't touch the current one.
  int _session = 0;
  bool _sessionHandled = false;
  Timer? _recordingTimer;

  // Android keeps sending the previous recording's tail for a moment (its
  // "done", or a "recognizer busy/client" error) and a new recording can
  // fail to start while the old one is still being released. So a new
  // recording only counts events once the recognizer has said it is
  // listening, gets one quiet automatic restart if it fails right away,
  // and never starts sooner than [_restartGap] after the last one ended.
  static const Duration _restartGap = Duration(milliseconds: 450);
  static const Duration _earlyFailure = Duration(milliseconds: 1500);
  bool _listeningSeen = false;
  bool _restarted = false;
  DateTime _sessionStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSessionEnd = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    AnswerSignals.itemShown();
    _initSpeech();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    if (_micState == _MicState.recording) _speech.cancel();
    if (_speech.statusListener == _onStatus) _speech.statusListener = null;
    if (_speech.errorListener == _onError) _speech.errorListener = null;
    super.dispose();
  }

  void _bindCallbacks() {
    _speech.statusListener = _onStatus;
    _speech.errorListener = _onError;
  }

  Future<void> _initSpeech() async {
    bool available;
    try {
      available = await _speech.initialize(onStatus: _onStatus, onError: _onError);
    } catch (_) {
      available = false;
    }
    if (!mounted) return;
    _bindCallbacks();
    final wasChecked = _speechChecked;
    setState(() {
      _speechChecked = true;
      _speechAvailable = available;
    });
    if (!available && !wasChecked) widget.onUnavailable?.call();
  }

  void _onStatus(String status) {
    if (!mounted || _micState != _MicState.recording || _sessionHandled) return;
    if (status == SpeechToText.listeningStatus) {
      _listeningSeen = true;
      return;
    }
    // "done" is only sent once the recognizer has fully finished (after
    // its final result, if it had one) -- so here, anything still
    // unhandled means nothing usable was heard. Before this recording
    // has even started listening, a "done" is the previous one's tail.
    if (status == SpeechToText.doneStatus && _listeningSeen) {
      final session = _session;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _handleRecognized(session, _recognizedText);
      });
    }
  }

  void _onError(SpeechRecognitionError error) {
    if (!mounted || _micState != _MicState.recording || _sessionHandled) return;
    final early = !_listeningSeen || DateTime.now().difference(_sessionStartedAt) < _earlyFailure;
    if (early && !_restarted && _recognizedText.isEmpty) {
      // Most likely the recognizer was still busy with the last recording
      // (or this is that one's leftover error): start again, quietly.
      _restarted = true;
      _restart(_session);
      return;
    }
    _handleRecognized(_session, _recognizedText);
  }

  Future<void> _restart(int session) async {
    try {
      await _speech.cancel();
    } catch (_) {}
    await Future.delayed(_restartGap);
    if (!mounted || session != _session || _sessionHandled) return;
    _listeningSeen = false;
    await _listen(session);
  }

  Future<void> _onMicTap() async {
    switch (_micState) {
      case _MicState.idle:
        await _startListening();
      case _MicState.recording:
        // Tapping again stops: whatever was heard so far is the answer.
        _handleRecognized(_session, _recognizedText);
      case _MicState.processing:
      case _MicState.result:
        break;
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable || _micState != _MicState.idle || _answered) return;
    _bindCallbacks();
    final session = ++_session;
    _sessionHandled = false;
    _listeningSeen = false;
    _restarted = false;
    setState(() {
      _micState = _MicState.recording;
      _recognizedText = '';
      _isCorrect = null;
    });
    _recordingTimer?.cancel();
    _recordingTimer = Timer(_recordingLimit, () {
      if (mounted && session == _session) _handleRecognized(session, _recognizedText);
    });

    // Let the previous recording be fully released first.
    if (_speech.isListening) {
      try {
        await _speech.cancel();
      } catch (_) {}
    }
    final sinceLast = DateTime.now().difference(_lastSessionEnd);
    if (sinceLast < _restartGap) await Future.delayed(_restartGap - sinceLast);
    if (!mounted || session != _session || _sessionHandled) return;
    await _listen(session);
  }

  Future<void> _listen(int session) async {
    _sessionStartedAt = DateTime.now();
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          if (!mounted || session != _session || _sessionHandled) return;
          setState(() => _recognizedText = result.recognizedWords);
          if (result.finalResult) _handleRecognized(session, result.recognizedWords);
        },
        listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
      );
    } catch (_) {
      if (!mounted || session != _session || _sessionHandled) return;
      if (!_restarted) {
        _restarted = true;
        await _restart(session);
        return;
      }
      _sessionHandled = true;
      _recordingTimer?.cancel();
      _lastSessionEnd = DateTime.now();
      setState(() => _micState = _MicState.idle);
      _showHint(tr('Не удалось включить микрофон, попробуйте ещё раз'));
    }
  }

  /// Ends recording [session] with what was heard. Runs at most once per
  /// recording, whichever comes first: the final result, the user's stop
  /// tap, an error, the recognizer going quiet, or the time limit.
  void _handleRecognized(int session, String recognized) {
    if (!mounted || session != _session || _sessionHandled) return;
    _sessionHandled = true;
    _recordingTimer?.cancel();
    _lastSessionEnd = DateTime.now();
    // Cancel, not stop: the answer is already decided, and a stop would
    // make the recognizer send one more round of events.
    if (_speech.isListening) _speech.cancel();

    if (recognized.trim().isEmpty) {
      // A technical non-detection (silence, noise, a recognizer error) --
      // not a demonstrated wrong answer, so nothing is scored and the mic
      // is simply ready again.
      setState(() => _micState = _MicState.idle);
      _showHint(tr('Речь не распознана, попробуйте ещё раз'));
      return;
    }

    final correct = _similarityPercent(recognized, widget.item.word) >= widget.matchThreshold;
    setState(() {
      _recognizedText = recognized;
      _isCorrect = correct;
      _micState = _MicState.result;
    });
    AnswerSound.play(correct);
    if (correct) {
      Future.delayed(const Duration(milliseconds: 1100), () => _finish(true));
    } else if (_attempt >= _maxAttempts) {
      Future.delayed(const Duration(milliseconds: 1800), () => _finish(false));
    }
    // Otherwise: wrong with tries left -- "Ещё раз" / "Дальше" decide.
  }

  void _retry() {
    if (_answered) return;
    setState(() {
      _attempt++;
      _micState = _MicState.idle;
      _recognizedText = '';
      _isCorrect = null;
    });
  }

  /// Reports this word exactly once.
  void _finish(bool correct) {
    if (!mounted || _answered) return;
    _answered = true;
    AnswerSignals.given(_recognizedText);
    widget.onAnswer(correct);
  }

  void _showHint(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    if (!_speechChecked) return const Skeleton(child: SkeletonBox(height: 260, radius: AppShapes.cardRadius));
    if (!_speechAvailable) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_off_rounded, size: 44, color: AppColors.muted),
            const SizedBox(height: 16),
            Text(
              tr('Распознавание речи недоступно'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              tr('Проверьте, что микрофон разрешён приложению и на устройстве установлен сервис распознавания речи.'),
              style: TextStyle(color: AppColors.secondaryText),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _initSpeech, child: Text(tr('Проверить снова'))),
          ],
        ),
      );
    }

    final canRetry = _micState == _MicState.result && _isCorrect == false && _attempt < _maxAttempts && !_answered;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WordCard(item: widget.item),
        const SizedBox(height: 28),
        _MicButton(state: _micState, onTap: _onMicTap),
        const SizedBox(height: 18),
        _StateLabel(
          state: _micState,
          recognizedText: _recognizedText,
          isCorrect: _isCorrect,
          target: widget.item.word,
          attempt: _attempt,
          maxAttempts: _maxAttempts,
        ),
        if (canRetry) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                key: const ValueKey('speaking-word-next'),
                onPressed: () => _finish(false),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12)),
                child: Text(tr('Дальше')),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: const ValueKey('speaking-word-retry'),
                onPressed: _retry,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12)),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: Text(tr('Ещё раз')),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Normalized similarity 0-100 between [recognized] and [target], based on
/// Levenshtein edit distance -- tolerant of the small variations real
/// speech recognition produces, but not of a genuinely different word.
int _similarityPercent(String recognized, String target) {
  String normalize(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), '');
  final a = normalize(recognized);
  final b = normalize(target);
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 100;
  final distance = _levenshtein(a, b);
  final maxLen = a.length > b.length ? a.length : b.length;
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppShapes.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppShapes.rowRadius),
              child: RemoteImage(
                url: item.imageUrl!,
                width: 300,
                height: 120,
                fit: BoxFit.cover,
                fallbackBuilder: () => const SizedBox(height: 0),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            item.word,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
            textAlign: TextAlign.center,
          ),
          if (hasTranscription)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(item.transcription!, style: const TextStyle(fontSize: 15, color: AppColors.secondaryText)),
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
    final isRecording = widget.state == _MicState.recording;
    final isBusy = widget.state == _MicState.processing;

    final Color color;
    final IconData icon;
    switch (widget.state) {
      case _MicState.idle:
        color = AppColors.primary;
        icon = Icons.mic_rounded;
      case _MicState.recording:
        color = AppColors.danger;
        icon = Icons.stop_rounded;
      case _MicState.processing:
        color = AppColors.rewardText;
        icon = Icons.hourglass_top_rounded;
      case _MicState.result:
        color = AppColors.muted;
        icon = Icons.mic_none_rounded;
    }

    return GestureDetector(
      onTap: (widget.state == _MicState.idle || widget.state == _MicState.recording) ? widget.onTap : null,
      child: SizedBox(
        width: 120,
        height: 120,
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
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.18)),
                    ),
                  );
                },
              ),
            Container(
              key: const ValueKey('speaking-word-mic-button'),
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: isBusy
                  ? SkeletonPulse(child: Icon(icon, color: Colors.white, size: 38))
                  : Icon(icon, color: Colors.white, size: 38),
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
  final int attempt;
  final int maxAttempts;
  const _StateLabel({
    required this.state,
    required this.recognizedText,
    required this.isCorrect,
    required this.target,
    required this.attempt,
    required this.maxAttempts,
  });

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _MicState.idle:
        return Text(
          attempt > 1 ? tr('Попытка {0} из {1} · нажмите и скажите ещё раз', [attempt, maxAttempts]) : tr('Нажмите и произнесите слово'),
          style: const TextStyle(color: AppColors.secondaryText, fontSize: 14),
          textAlign: TextAlign.center,
        );
      case _MicState.recording:
        return Column(
          children: [
            Text(
              recognizedText.isEmpty ? tr('Слушаю…') : recognizedText,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(tr('Нажмите, чтобы остановить'), style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText)),
          ],
        );
      case _MicState.processing:
        return Text(tr('Проверяю…'), style: TextStyle(color: AppColors.secondaryText, fontSize: 14));
      case _MicState.result:
        final correct = isCorrect ?? false;
        final color = correct ? AppColors.success : AppColors.danger;
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color, size: 20),
                const SizedBox(width: 6),
                Text(
                  correct ? tr('Правильно') : tr('Неправильно'),
                  style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15),
                ),
              ],
            ),
            if (!correct) ...[
              const SizedBox(height: 4),
              Text(
                tr('Услышано: «{0}», нужно: «{1}»', [recognizedText, target]),
                style: const TextStyle(fontSize: 13, color: AppColors.secondaryText),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );
    }
  }
}
