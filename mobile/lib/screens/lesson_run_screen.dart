import '../l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/exercise_scoring.dart';
import '../services/lesson_preparation.dart';
import '../services/lesson_scoring.dart';
import '../services/pending_answers.dart';
import '../services/session_cache.dart';
import '../models/lesson.dart';
import '../models/lesson_rounds.dart';
import '../theme/app_colors.dart';
import 'build_word_screen.dart';
import 'lesson_exercise_flow.dart';
import 'lesson_results_screen.dart';
import 'listen_word_screen.dart';
import 'matching_screen.dart';
import 'speaking_word_screen.dart';
import 'true_or_false_screen.dart';
import '../models/mini_phrase.dart';
import '../widgets/mini_phrases/mini_phrase_session.dart';

/// The human-readable name of each exercise type, for the run's title bar.
Map<String, String> get lessonExerciseLabels => {
  'true_or_false': tr('Правда или ложь'),
  'matching': tr('Сопоставление'),
  'build_word': tr('Собери слово'),
  'speaking_word': tr('Произнеси слово'),
  'listen_word': tr('Услышь слово'),
};

/// Everything the run needs from outside -- the backend and the screens --
/// behind one seam, so a test can drive the whole sequence without either.
abstract class LessonRunDriver {
  /// Freezes this pass's words (POST /lessons/{id}/pass).
  Future<void> startPass(int lessonId);

  /// Makes a pass played to the end count (its answers were held back).
  Future<void> finishPass(int lessonId);

  /// Every exercise's round for this pass, plus the media they use --
  /// fetched once, up front, so the pass then runs without a request or a
  /// loading screen between exercises.
  Future<LessonRounds> prepareRounds(int lessonId, List<String> exerciseKeys);

  /// The exercise itself, given its prepared round. It ends by calling
  /// finishExercise().
  Widget buildExercise(int lessonId, int lessonNumber, String key, LessonRounds rounds);

  Future<Lesson> fetchLesson(int lessonId);

  /// The finished pass's statistics; null when they can't be loaded -- the
  /// results then show without them.
  Future<LessonPassStats?> fetchPassStats(int lessonId);

  /// Shows the one results screen; true means "Повторить урок".
  ///
  /// [refresh] is the server's own version of the pass, when it is still on its
  /// way (see LessonResultsRefresh): the screen opens on the numbers the phone
  /// worked out and swaps these in when they arrive, so this never waits for
  /// the network to show a result the device already knows.
  Future<bool?> showResults(
    BuildContext context,
    Lesson lesson,
    LessonPassStats? stats, {
    Future<LessonResultsRefresh?>? refresh,
  });
}

class ApiLessonRunDriver implements LessonRunDriver {
  const ApiLessonRunDriver();

  @override
  Future<void> startPass(int lessonId) => ApiClient.instance.startLessonPass(lessonId);

  @override
  Future<void> finishPass(int lessonId) => ApiClient.instance.finishLessonPass(lessonId);

  @override
  Future<LessonRounds> prepareRounds(int lessonId, List<String> exerciseKeys) =>
      LessonRounds.prepare(lessonId, exerciseKeys);

  @override
  Widget buildExercise(int lessonId, int lessonNumber, String key, LessonRounds rounds) {
    return switch (key) {
      'true_or_false' =>
        TrueOrFalseScreen(lessonId: lessonId, lessonNumber: lessonNumber, initialRound: rounds.round(key)),
      'matching' => MatchingScreen(lessonId: lessonId, lessonNumber: lessonNumber, initialRound: rounds.round(key)),
      'build_word' =>
        BuildWordScreen(lessonId: lessonId, lessonNumber: lessonNumber, initialRound: rounds.round(key)),
      'speaking_word' =>
        SpeakingWordScreen(lessonId: lessonId, lessonNumber: lessonNumber, initialRound: rounds.round(key)),
      'listen_word' =>
        ListenWordScreen(lessonId: lessonId, lessonNumber: lessonNumber, initialRound: rounds.round(key)),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Future<Lesson> fetchLesson(int lessonId) => ApiClient.instance.fetchLesson(lessonId);

  @override
  Future<LessonPassStats?> fetchPassStats(int lessonId) async {
    try {
      return await ApiClient.instance.fetchLessonPassStats(lessonId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool?> showResults(
    BuildContext context,
    Lesson lesson,
    LessonPassStats? stats, {
    Future<LessonResultsRefresh?>? refresh,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LessonResultsScreen(lesson: lesson, stats: stats, refresh: refresh)),
    );
  }
}

/// One lesson, start to finish, on ONE screen.
///
/// Walks the lesson's `exerciseKeys` (decided by the backend when the
/// lesson was created) in order. Each exercise replaces the previous one
/// in place -- nothing is pushed or popped between them, so the lesson's
/// word list or any menu never shows in between. An exercise with nothing
/// to test is skipped. After the last one, the results screen is shown
/// once; "Повторить урок" there runs the sequence again right here,
/// anything else closes the lesson.
///
/// Every pass starts with POST /lessons/{id}/pass, which freezes the words
/// that pass covers, so every chosen word goes through every exercise.
/// If that call fails the pass still runs (on the backend's older, live
/// set) -- a lesson must never stall on it.
///
/// Right after that, every exercise's round and its pictures and sounds
/// are prepared at once (LessonRounds): the one wait of a pass is up front,
/// behind a skeleton, and exercises then follow each other with no request
/// and no loading screen in between.
///
/// Scoring, progress and the exercises themselves are untouched: each
/// exercise still submits its own answers exactly as before.
/// Where rounds prepared ahead for a lesson wait for its first pass.
String lessonRoundsCacheKey(int lessonId) => 'lesson-rounds-$lessonId';

/// Prepares [lesson] in the background, so opening it starts instantly AND
/// works with no network. Does nothing if it is already prepared.
///
/// "Prepared" means everything: the rounds of every exercise, the pictures and
/// recordings they use, and the scoring rules -- not merely that the lesson
/// opens quickly (see services/lesson_preparation.dart).
Future<void> prepareLessonAhead(Lesson lesson) async {
  if (LessonPreparation.isReady(lesson.id, lesson.exerciseKeys)) return;
  final key = lessonRoundsCacheKey(lesson.id);
  try {
    final rounds = SessionCache.get<LessonRounds>(key) ?? await LessonRounds.prepare(lesson.id, lesson.exerciseKeys);
    SessionCache.put(key, rounds);
    await LessonPreparation.finish(
      rounds,
      extraMedia: [for (final phrase in lesson.miniPhrases) if (phrase.audioUrl != null) phrase.audioUrl!],
    );
  } catch (_) {
    // Best effort -- the lesson simply prepares itself when opened.
  }
}

class LessonRunScreen extends StatefulWidget {
  final int lessonId;
  final int lessonNumber;
  final List<String> exerciseKeys;

  /// The lesson as its caller has it, when it has one.
  ///
  /// Used as the fallback "before" for scoring a pass offline: the device's own
  /// copy is the first choice (it carries anything this phone already scored),
  /// but a lesson opened straight from a card must be scorable even if that copy
  /// is missing.
  final Lesson? lesson;

  /// Explained and assembled after the word exercises, before the results,
  /// on every pass (chosen by the backend when the lesson was created).
  final List<MiniPhrase> miniPhrases;
  final LessonRunDriver driver;

  const LessonRunScreen({
    super.key,
    required this.lessonId,
    required this.lessonNumber,
    required this.exerciseKeys,
    this.lesson,
    this.miniPhrases = const [],
    this.driver = const ApiLessonRunDriver(),
  });

  LessonRunScreen.forLesson(Lesson lesson, {Key? key, LessonRunDriver driver = const ApiLessonRunDriver()})
      : this(
          key: key,
          lessonId: lesson.id,
          lessonNumber: lesson.number,
          exerciseKeys: lesson.exerciseKeys,
          lesson: lesson,
          miniPhrases: lesson.miniPhrases,
          driver: driver,
        );

  @override
  State<LessonRunScreen> createState() => _LessonRunScreenState();
}

class _LessonRunScreenState extends State<LessonRunScreen> {
  int _pass = 0;
  int _index = 0;
  bool _showingExercise = false;
  bool _showingMiniPhrases = false;
  // Refreshed after each pass: empty once the lesson is completed.
  late List<MiniPhrase> _miniPhrases = widget.miniPhrases;
  bool _failed = false;
  Completer<void>? _current;
  LessonRounds _rounds = const LessonRounds({});
  bool _reachedResults = false;

  /// Lesson preparation (see services/lesson_preparation.dart): shown while a
  /// lesson that has never been prepared on this device is made ready -- its
  /// exercises, pictures, recordings and scoring rules -- so that it then runs
  /// with no network at all. A lesson prepared earlier never sees this.
  bool _preparing = false;
  PrepStep _prepStep = const PrepStep(PrepStage.rounds, 0);
  String? _prepError;

  /// The lesson as it was when this pass started, and when that was: what an
  /// offline pass is scored against (see services/lesson_scoring.dart).
  Lesson? _before;
  DateTime? _passStartedAt;

  /// The pass being handed over to the server right now, if any: the next pass
  /// of the same lesson waits for it before opening (see [_openPass]), because
  /// the server would otherwise hold the new pass's answers against the pass
  /// whose ending has not landed yet.
  Future<void>? _handingOver;

  @override
  void initState() {
    super.initState();
    ApiClient.instance.logEvent('lesson_opened', lessonId: widget.lessonId);
    unawaited(_run());
  }

  @override
  void dispose() {
    // Left without finishing: nothing more is held for this pass.
    if (ApiClient.instance.deferredLessonId == widget.lessonId) ApiClient.instance.deferredLessonId = null;
    // Left before the results screen: worth seeing where people give up.
    if (!_reachedResults) {
      ApiClient.instance.logEvent('lesson_left', lessonId: widget.lessonId, data: {
        'exercise': _index + 1,
        'of': widget.exerciseKeys.length,
      });
    }
    super.dispose();
  }

  Future<void> _run() async {
    final driver = widget.driver;
    setState(() {
      _pass++;
      _index = 0;
      _showingExercise = false;
      _failed = false;
      _prepError = null;
    });
    // Rounds prepared ahead of time (the Уроки list prepares the next
    // lesson in the background) start the first pass with no wait at all;
    // the pass is still started on the server, just without blocking.
    // A repeat pass always fetches fresh: it re-tests only what's left.
    final ahead = _pass == 1 ? SessionCache.take<LessonRounds>(lessonRoundsCacheKey(widget.lessonId)) : null;

    // Answers only count once the pass is played to the end -- but only
    // when the server really started this pass (it also drops whatever an
    // earlier unfinished pass held). If starting failed, the start is QUEUED
    // instead: the pass then runs here and the server is told to open it the
    // moment there is a connection, before any of its answers.
    _passStartedAt = DateTime.now();
    // The lesson as it stands right now -- with anything this device already
    // scored but the server has not confirmed yet (LessonScoreOverlay) -- is
    // what an offline pass is scored against. The device's own copy first, then
    // whatever the screen that opened this lesson was holding.
    final cachedLesson = ApiClient.instance.cachedLesson(widget.lessonId) ?? widget.lesson;
    final rules = ApiClient.instance.cachedExerciseScoring() ?? ExerciseScoring.fallback;
    _before = cachedLesson == null ? null : LessonScoreOverlay.applied(cachedLesson, rules);
    debugPrint('[guyo] pass ${widget.lessonId} starts: scoring rules ${rules.points.length}, '
        'lesson copy ${cachedLesson == null ? 'MISSING' : 'ok'}');

    // From here on everything this lesson answers is held on the server until
    // the pass is finished -- whether the pass has actually opened yet or is
    // still on its way there (see _openPass, which keeps that order).
    ApiClient.instance.deferredLessonId = widget.lessonId;
    // The pass opens BEHIND the first exercise rather than in front of it: every
    // word of it is already on the device, so there is nothing to wait for --
    // and with no network this used to be a five-second wait on a breathing logo
    // before the first card appeared.
    unawaited(_openPass());

    LessonRounds rounds;
    // A repeat pass re-tests only the words still short of their level, so its
    // word set is a NEW one -- fetched fresh, exactly as before. Its pictures,
    // recordings and rules are already on the device from the first pass.
    final ready = _pass == 1 ? (ahead ?? LessonRounds.fromCache(widget.lessonId, widget.exerciseKeys)) : null;
    if (_pass > 1) {
      // A repeat re-tests only what is left, so it asks for a fresh set -- but
      // it must never walk into exercises that would each sit on a skeleton
      // (that is exactly what happens with no network: every round request comes
      // back empty and every exercise then waits for its own). The rounds
      // prepared for the first pass are used instead -- re-testing the same
      // words is what a repeat is anyway -- and if there are none, the pass says
      // so rather than hanging.
      LessonRounds? fresh;
      try {
        fresh = await driver.prepareRounds(widget.lessonId, widget.exerciseKeys);
      } catch (_) {
        fresh = null;
      }
      final cached = LessonRounds.fromCache(widget.lessonId, widget.exerciseKeys);
      if ((fresh == null || fresh.hasNothing) && cached != null) {
        rounds = cached;
        LessonPreparation.warmMedia(rounds);
      } else if (fresh == null || fresh.hasNothing) {
        if (mounted) {
          setState(() {
            _preparing = false;
            _prepError = tr('Не удалось подготовить урок. Проверьте интернет.');
          });
        }
        return;
      } else {
        rounds = fresh;
      }
    } else if (ready != null) {
      // Prepared on this device some time ago (or a moment ago in the Уроки
      // list): the pass starts at once -- no preparation screen, no skeleton --
      // and its recordings play from the downloaded files.
      rounds = ready;
      LessonPreparation.warmMedia(rounds);
    } else {
      // Never prepared here: fetch everything the lesson needs, behind a
      // progress screen, so that from now on it runs offline.
      if (mounted) setState(() => _preparing = true);
      try {
        if (mounted) setState(() => _prepStep = const PrepStep(PrepStage.rounds, 0.03));
        rounds = await driver.prepareRounds(widget.lessonId, widget.exerciseKeys);
        // One more try for whatever did not come back. A lesson is prepared ONCE
        // and then has to work with no connection, so a round missing now is a
        // round that would hang on its own skeleton later -- offline, in the
        // middle of the lesson, which is exactly what this must prevent.
        if (rounds.hasMissing) {
          rounds = rounds.mergedWith(
            await LessonRounds.prepare(widget.lessonId, rounds.missingKeys),
          );
        }
        // Still nothing (or nothing at all): there is no lesson to run, whatever
        // the separate failures looked like. Saying so is what keeps the user out
        // of exercises that would wait for a round that cannot come -- a lesson is
        // prepared online, before it is played.
        if (rounds.hasNothing || rounds.hasMissing) {
          if (mounted) {
            setState(() {
              _preparing = false;
              _prepError = tr('Не удалось подготовить урок. Проверьте интернет.');
            });
          }
          return;
        }
        // Then the pictures, the recordings and the scoring rules -- the parts
        // a pass would otherwise load lazily, which is exactly what must not
        // happen once the lesson is meant to run offline.
        await LessonPreparation.finish(
          rounds,
          // Everything this lesson may show or play, not just what the exercises
          // use: the results screen plays each word's own recording and shows
          // its picture, and that has to work with no network as well.
          extraMedia: [
            for (final phrase in _miniPhrases) if (phrase.audioUrl != null) phrase.audioUrl!,
            for (final word in (widget.lesson ?? _before)?.words ?? const <LessonWord>[]) ...[
              if (word.wordAudioUrl != null) word.wordAudioUrl!,
              if (word.translationAudioUrl != null) word.translationAudioUrl!,
              if (word.imageUrl != null) word.imageUrl!,
            ],
          ],
          onProgress: (step) {
            if (mounted) setState(() => _prepStep = step);
          },
        );
      } catch (_) {
        // No network (a lesson is created online, so this is the "not
        // prepared yet and can't be now" case): say so plainly and let the
        // user retry rather than dropping into exercises that would each fail.
        if (mounted) {
          setState(() {
            _preparing = false;
            _prepError = tr('Не удалось подготовить урок. Проверьте интернет.');
          });
        }
        return;
      }
      if (mounted) setState(() => _preparing = false);
    }
    _rounds = rounds;

    for (var i = 0; i < widget.exerciseKeys.length; i++) {
      if (!mounted) return;
      final key = widget.exerciseKeys[i];
      if (!rounds.hasWork(key)) continue;
      setState(() {
        _index = i;
        _showingExercise = false;
      });
      final done = Completer<void>();
      _current = done;
      setState(() => _showingExercise = true);
      await done.future;
    }

    if (!mounted) return;
    setState(() => _showingExercise = false);

    // The mini-phrases this lesson opens: reinforcement after the words.
    if (_miniPhrases.isNotEmpty) {
      final done = Completer<void>();
      _current = done;
      setState(() => _showingMiniPhrases = true);
      await done.future;
      if (!mounted) return;
      setState(() => _showingMiniPhrases = false);
    }

    await _showResults();
  }

  /// Opens this pass on the server, behind the first exercise (see [_run]).
  ///
  /// The lesson never waits for it: every word of the pass is already on the
  /// device, so the first card is playable at once. What does wait is the
  /// network -- [ApiClient.openLessonPass] holds this pass's answers back until
  /// the opening has gone over (or has been queued, with no network), because an
  /// answer must never reach the server before the pass it belongs to.
  Future<void> _openPass() async {
    await ApiClient.instance.openLessonPass(
      widget.lessonId,
      () async {
        // Whatever the previous pass still owes the server goes first: its
        // ending must land before this pass opens, or the server would hold this
        // pass's answers against the pass that is still open.
        final previous = _handingOver;
        if (previous != null) {
          try {
            await previous;
          } catch (_) {
            // The previous pass's own hand-over never throws (it queues what is
            // left); and nothing about it can stop this pass from opening.
          }
        }
        await widget.driver.startPass(widget.lessonId);
      },
    );
  }

  /// The results, the moment the lesson is over.
  ///
  /// Nothing here waits for the network: the pass is scored on the device by the
  /// server's own rules ([_scoreHere]) and the screen opens on those numbers at
  /// once, while [_handOverPass] puts the pass on the server BEHIND it -- the
  /// server's own version then replaces what is on screen
  /// (see LessonResultsRefresh). Only a lesson this device has no copy of at all
  /// has to wait to be told anything.
  Future<void> _showResults() async {
    _reachedResults = true;

    // The pass scored HERE, out of the answers this device gave -- no request,
    // no waiting, works with no network at all.
    final scored = _scoreHere();
    // And the hand-over, which runs behind the screen below. The pass ITSELF goes
    // over first: the next pass of this lesson waits for that and nothing else
    // (see _openPass), never for the numbers fetched after it.
    final handedOver = _pushPassToServer();
    _handingOver = handedOver;
    final refresh = _handOverPass(handedOver);

    LessonPassStats? stats = scored?.stats;
    Lesson? shown = scored?.lesson ?? widget.lesson;

    if (shown == null) {
      // No copy of this lesson to score against (it was never fetched on this
      // device): the server's version is the only one there is, so this -- and
      // only this -- case waits for it.
      final incoming = await refresh;
      if (!mounted) return;
      if (incoming == null) {
        setState(() => _failed = true);
        return;
      }
      shown = incoming.lesson;
      stats = incoming.stats;
    }

    _miniPhrases = shown.miniPhrases;
    if (!mounted) return;
    debugPrint('[guyo] pass ${widget.lessonId}: results open on '
        '${scored == null ? 'the lesson the caller had' : 'this device\'s own score'}'
        '${stats == null ? '' : ' (${stats.totalAnswers} answers, ${stats.scoreGained} points, '
            '${stats.newlyLearned} newly learned)'}, the server\'s own numbers follow');
    final repeat = await widget.driver.showResults(context, shown, stats, refresh: refresh);
    if (!mounted) return;
    if (repeat == true) {
      unawaited(_run());
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Hands this pass over to the server and comes back with the server's own
  /// version of the lesson and of its statistics.
  ///
  /// Runs BEHIND the results screen (see [_showResults]): online this is the
  /// server counting the pass, offline the whole pass stays queued on the device
  /// and goes over the moment there is a connection again
  /// (ApiClient.flushPendingAnswers). Null means the server's numbers are not
  /// there yet; the screen then keeps the ones the phone worked out.
  ///
  /// [pushed] is the pass going over -- already on its way; this only reads what
  /// came of it and then fetches the server's own version.
  Future<LessonResultsRefresh?> _handOverPass(Future<bool> pushed) async {
    if (!await pushed) {
      // Still on the device: whatever is left keeps going in the background.
      unawaited(_syncInBackground());
      return null;
    }
    // The server's own numbers are the ones that last from here: drop this
    // device's local version FIRST, so what is fetched below is the server's.
    LessonScoreOverlay.forget(widget.lessonId);
    Lesson? fromServer;
    try {
      fromServer = await widget.driver.fetchLesson(widget.lessonId);
    } catch (_) {
      fromServer = null;
    }
    if (fromServer == null) {
      unawaited(_syncInBackground());
      return null;
    }
    LessonPassStats? stats;
    try {
      stats = await widget.driver.fetchPassStats(widget.lessonId);
    } catch (_) {
      stats = null;
    }
    return LessonResultsRefresh(fromServer, stats);
  }

  /// Puts this pass on the server -- its opening (when it could not be started
  /// at the time), every answer still on the device, and its ending, in that
  /// order -- and says whether the server counted it. False means the pass is
  /// still on the device, in order, waiting for a connection.
  Future<bool> _pushPassToServer() async {
    if (ApiClient.instance.deferredLessonId != widget.lessonId) return true;
    var synced = false;
    try {
      // FIRST everything this pass did, in order: the pass opening (if it
      // could not be started at the time), then every answer still on the
      // device. The server must have all of them BEFORE it counts the pass --
      // otherwise it counts a pass it only half-heard, which shows up as
      // answers missing and words that barely moved.
      //
      // BOUNDED: with no network every single answer would sit there timing out
      // one after another, and the results -- which the phone can already work
      // out for itself -- would wait for all of them. Three seconds is enough
      // for a real hand-over; whatever is left keeps going in the background
      // and the pass is scored on the device meanwhile.
      await ApiClient.instance
          .flushPendingAnswers()
          .timeout(const Duration(seconds: 3), onTimeout: () {});
      if (PendingAnswers.forLesson(widget.lessonId).isNotEmpty) {
        // Not everything could be handed over: the pass is NOT counted now.
        // The phone scores it instead, and the whole pass goes over later, in
        // order, starting with the answers that are still waiting.
        await PendingAnswers.addFinish(widget.lessonId);
      } else {
        await widget.driver.finishPass(widget.lessonId);
        synced = true;
      }
    } catch (_) {
      await PendingAnswers.addFinish(widget.lessonId);
    }
    // Only if this lesson is still the one being played: a lesson opened while
    // this pass was being handed over has its own id by now, and clearing that
    // would let its answers move scores outside its pass (see queueLessonAnswer).
    if (ApiClient.instance.deferredLessonId == widget.lessonId) ApiClient.instance.deferredLessonId = null;
    return synced;
  }

  /// The pass scored on the phone, or null when this lesson was never fetched
  /// (so there is nothing to score against).
  ///
  /// Only THIS pass's answers count: the queue is per lesson, so an earlier
  /// abandoned pass of the same lesson must not be folded into these numbers --
  /// exactly the way the backend measures its own pass from the moment it
  /// started.
  ScoredPass? _scoreHere() {
    final before = _before ?? ApiClient.instance.cachedLesson(widget.lessonId) ?? widget.lesson;
    if (before == null) {
      debugPrint('[guyo] pass ${widget.lessonId}: NO lesson copy -- cannot score it on the phone');
      return null;
    }
    final startedAt = _passStartedAt;
    final mine = [
      for (final answer in PendingAnswers.answersFor(widget.lessonId))
        if (startedAt == null ||
            (answer['at'] is int && (answer['at'] as int) >= startedAt.millisecondsSinceEpoch))
          answer,
    ];
    return LessonScoring.score(
      before: before,
      answers: mine,
      rules: ApiClient.instance.cachedExerciseScoring() ?? ExerciseScoring.fallback,
      startedAt: startedAt,
    );
  }

  /// Hands an offline pass to the server as soon as it can go. Silent: the
  /// screen the user is reading keeps the numbers it already showed, exactly as
  /// if the pass had been sent on time -- the server's own numbers are simply
  /// what the next screen reads (see ApiClient.flushPendingAnswers, which also
  /// drops this device's version of the lesson and fetches the server's).
  Future<void> _syncInBackground() async {
    try {
      await ApiClient.instance.flushPendingAnswers();
    } catch (_) {
      // Still offline: it stays queued for the next flush.
    }
  }

  void _onExerciseFinished() {
    final current = _current;
    if (current != null && !current.isCompleted) current.complete();
  }

  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('Прервать урок?')),
        content: Text(tr('Ответы уже сохранены. Урок можно продолжить позже.')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(tr('Продолжить'))),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(tr('Выйти'))),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.exerciseKeys;
    final key = keys.isEmpty ? null : keys[_index];
    final preparing = _preparing || _prepError != null;
    final title = preparing
        ? tr('Подготавливаем урок')
        : _showingMiniPhrases
            ? tr('Мини-фразы')
            : key == null
                ? tr('Урок {0}', [widget.lessonNumber])
                : (lessonExerciseLabels[key] ?? key);
    final progress = preparing
        ? _prepStep.progress
        : _showingMiniPhrases
            ? 1.0
            : keys.isEmpty
                ? 0.0
                : (_index + (_showingExercise ? 0 : 1)) / keys.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title),
              if (preparing)
                Text(
                  tr('Готовим для работы без интернета'),
                  style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText),
                )
              else if (_showingMiniPhrases)
                Text(
                  tr('Урок {0} · закрепление', [widget.lessonNumber]),
                  style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText),
                )
              else if (keys.isNotEmpty)
                Text(
                  tr('Урок {0} · упражнение {1} из {2}', [widget.lessonNumber, _index + 1, keys.length]),
                  style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText),
                ),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppColors.progressTrack,
              color: AppColors.primary,
            ),
          ),
        ),
        body: _buildBody(key),
      ),
    );
  }

  Widget _buildBody(String? key) {
    if (_prepError != null) return _preparationFailed();
    if (_preparing) return _PreparationView(step: _prepStep);
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Не удалось загрузить результаты урока'), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() => _failed = false);
                  _showResults();
                },
                child: Text(tr('Повторить')),
              ),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Выйти'))),
            ],
          ),
        ),
      );
    }
    if (_showingMiniPhrases) {
      return MiniPhraseSession(
        key: ValueKey('mini-phrases-$_pass'),
        phrases: _miniPhrases,
        lessonId: widget.lessonId,
        onDone: _onExerciseFinished,
      );
    }
    if (!_showingExercise || key == null) {
      return const LessonExerciseHandoff();
    }
    return LessonRunScope(
      onExerciseFinished: _onExerciseFinished,
      // A fresh key per exercise AND per pass: a repeated exercise must
      // start from a clean state, never reuse the previous round's.
      child: KeyedSubtree(
        key: ValueKey('$_pass-$_index'),
        child: widget.driver.buildExercise(widget.lessonId, widget.lessonNumber, key, _rounds),
      ),
    );
  }

  /// Preparation could not finish, which means there was no network: a lesson
  /// is created and prepared online, and only then runs without it. Says so
  /// plainly, with a way to try again -- rather than dropping into exercises
  /// that would each fail on their own.
  Widget _preparationFailed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 44, color: AppColors.muted),
            const SizedBox(height: 16),
            Text(
              _prepError!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 10),
            Text(
              tr('Урок создаётся и подготавливается с интернетом, а потом проходится без него.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.secondaryText),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _run,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: Text(tr('Повторить')),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Выйти'))),
          ],
        ),
      ),
    );
  }
}

/// «Подготавливаем урок»: what the runner shows while a lesson that has never
/// been prepared on this device is being made ready to run offline -- its
/// exercises, pictures, recordings and scoring rules. A lesson prepared earlier
/// never shows this: it opens straight into the first exercise.
class _PreparationView extends StatelessWidget {
  final PrepStep step;

  const _PreparationView({required this.step});

  String get _label => switch (step.stage) {
        PrepStage.rounds => tr('Готовим упражнения'),
        PrepStage.media => tr('Скачиваем озвучку и картинки'),
        PrepStage.rules => tr('Правила начисления'),
        PrepStage.done => tr('Урок готов'),
      };

  @override
  Widget build(BuildContext context) {
    final value = step.progress.clamp(0.0, 1.0);
    // The rounds step is five requests of unknown length, so it spins instead of
    // pretending to know how far along it is; everything after it is counted.
    final indeterminate = step.stage == PrepStage.rounds;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 124,
              height: 124,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 124,
                    height: 124,
                    child: CircularProgressIndicator(
                      value: indeterminate ? null : value,
                      strokeWidth: 7,
                      strokeCap: StrokeCap.round,
                      backgroundColor: AppColors.progressTrack,
                      color: AppColors.primary,
                    ),
                  ),
                  if (!indeterminate)
                    Text(
                      '${(value * 100).round()}%',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.primaryDark),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Text(
              tr('Готовим урок для офлайна'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 8),
            Text(
              _label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary),
            ),
            const SizedBox(height: 10),
            Text(
              tr('После этого урок открывается мгновенно и работает без интернета.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
