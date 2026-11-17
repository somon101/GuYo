import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/lesson.dart';
import '../models/user_profile.dart';
import '../screens/achievement_celebration_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_fire.dart';
import '../widgets/game_icons.dart';
import 'demo_state.dart';

// The end of a lesson as the owner approved it (demo only, see main_demo.dart):
//
//  - after every passed lesson: the results ("Плитки": the points, the day's goal, the pass, the rating);
//  - after the FIRST passed lesson of the day only: then the streak, then the chest of the day,
//    which is handed out and opened right here (it is no longer taken from «Мои сундуки»);
//  - the second and later lessons of the same day: the results alone; the next day the whole path again;
//  - a lesson with words still short: the same results ("Осталось N слов"), «Добить слова» repeats
//    only those words, «Позже» leaves.
//
// The speed is the owner's pick «Чуть быстрее» (0.75 of the mockup's rhythm); the sounds are the
// «Прежний» set (small tones, rebuilt as assets/sounds/demo-*.wav) plus the app's own chest sound.

/// Speed of every timer and transition below: 1 is the first mockup's rhythm, 0.75 is «Чуть быстрее».
const double _k = 0.75;

Duration _ms(num base) => Duration(milliseconds: (base * _k).round());

/// The soft, fresh colours of these screens (the owner's pick: the green and yellow of «Лайм»,
/// the lilac of «Мята»); each has a light and a dark value.
class _C {
  _C._();
  static bool get _d => AppColors.dark;
  static Color get green => _d ? const Color(0xFF7BDA5E) : const Color(0xFF62C94A);
  static Color get greenEdge => _d ? const Color(0xFF4FA936) : const Color(0xFF47A72F);
  static Color get onGreen => _d ? const Color(0xFF10300A) : const Color(0xFF123D0A);
  static Color get greenText => _d ? const Color(0xFF8EE878) : const Color(0xFF3A8A27);
  static Color get greenSoft => _d ? const Color(0x297BDA5E) : const Color(0x3362C94A);
  static Color get yellow => _d ? const Color(0xFFFFDB5E) : const Color(0xFFFFD23F);
  static Color get yellowEdge => _d ? const Color(0xFFC9A02A) : const Color(0xFFE0AE1A);
  static Color get onYellow => _d ? const Color(0xFF3A2A00) : const Color(0xFF4A3500);
  static Color get lilac => _d ? const Color(0xFF8E97FF) : const Color(0xFF7B85F4);
  static Color get onLilac => _d ? const Color(0xFF0C0E16) : Colors.white;
  static Color get ink => AppColors.primaryDark;
  static Color get muted => AppColors.secondaryText;
  static Color get track => AppColors.progressTrack;
  static Color get tile => AppColors.surface;
  static Color get line => AppColors.cardBorder;
  static const Color fire = Color(0xFFF26A1B);
}

/// The small sounds of this path. A few players are used in turn, so a quick run of ticks never
/// waits for the one before it; a player that fails three times switches the sounds off for good
/// (a sound is decoration, it must never hold the screen).
class DemoSfx {
  DemoSfx._();

  /// Tests turn the sounds off (there is no audio on the test host).
  static bool enabled = true;

  static final List<AudioPlayer> _pool = [];
  static int _next = 0;
  static int _fails = 0;
  static const Duration _timeout = Duration(seconds: 2);

  static void play(String name) => _go('sounds/demo-$name.wav');

  static void playAsset(String path) => _go(path);

  static void _go(String asset) {
    if (!enabled) return;
    try {
      if (_pool.length < 4) {
        _pool.add(AudioPlayer()
          ..setReleaseMode(ReleaseMode.stop)
          ..setPlayerMode(PlayerMode.lowLatency));
      }
      final player = _pool[_next++ % _pool.length];
      unawaited(() async {
        try {
          await player.stop();
          await player.play(AssetSource(asset)).timeout(_timeout);
          _fails = 0;
        } catch (_) {
          if (++_fails >= 3) enabled = false;
        }
      }());
    } catch (_) {
      enabled = false;
    }
  }
}

mixin _Timers<T extends StatefulWidget> on State<T> {
  final List<Timer> _timers = [];

  /// Runs [f] after [base] ms of the mockup's rhythm (scaled by [_k]); never after the screen is gone.
  void later(num base, VoidCallback f) {
    _timers.add(Timer(_ms(base), () {
      if (mounted) f();
    }));
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }
}

/// The people just above the player in the rating (position 2 is the first of them, and so on).
const List<String> _rivals = ['Aziz', 'Madina', 'Rustam', 'Nilufar', 'Jasur', 'Zarina', 'Sardor', 'Malika'];

/// Everything the results show, worked out once when the screen opens.
class _Outcome {
  final int number;
  final int left;
  final bool passed;
  final bool fullPath;
  final int total;
  final int pLesson, pAccuracy, pSpeed;
  final int goalFrom, goalTo, goalOf;
  final int levelFrom, levelTo, xpFrom, xpTo;
  final int rankFrom, rankTo;
  final String rival;
  const _Outcome({
    required this.number,
    required this.left,
    required this.passed,
    required this.fullPath,
    required this.total,
    required this.pLesson,
    required this.pAccuracy,
    required this.pSpeed,
    required this.goalFrom,
    required this.goalTo,
    required this.goalOf,
    required this.levelFrom,
    required this.levelTo,
    required this.xpFrom,
    required this.xpTo,
    required this.rankFrom,
    required this.rankTo,
    required this.rival,
  });

  static const int levelSize = 400;

  /// Works the numbers out and, for a passed lesson, moves the demo's state on (the pass, the place
  /// in the rating). Called once per screen.
  factory _Outcome.of(Lesson lesson, LessonPassStats? stats, DemoState ds) {
    final learned = lesson.words.where((w) => w.isLearned).length;
    final total = lesson.words.length;
    final passed = lesson.isCompleted || (total > 0 && learned == total);
    final left = total - learned;
    final accuracy = stats != null && stats.totalAnswers > 0 ? stats.accuracy : 90;
    final seconds = stats != null && stats.totalAnswers > 0 ? stats.durationSeconds : 150;
    final pLesson = passed ? 30 : 0;
    final pAccuracy = !passed ? 0 : accuracy >= 90 ? 10 : accuracy >= 70 ? 6 : 3;
    final pSpeed = !passed ? 0 : seconds <= 150 ? 8 : seconds <= 240 ? 5 : 2;
    final points = passed ? pLesson + pAccuracy + pSpeed : ((stats?.correctAnswers ?? 7) * 3).clamp(6, 60);

    final goalOf = ds.goal;
    final goalTo = ds.wordsToday.clamp(0, goalOf);
    final goalFrom = (goalTo - (stats?.newlyLearned ?? 0)).clamp(0, goalTo);

    final levelFrom = ds.passLevel;
    final xpFrom = ds.passXp;
    var levelTo = levelFrom;
    var xpTo = xpFrom;
    if (passed) {
      xpTo = xpFrom + points;
      if (xpTo >= levelSize) {
        levelTo = levelFrom + 1;
        xpTo -= levelSize;
      }
    }

    final rankFrom = ds.rankPos;
    final rankTo = passed && rankFrom > 1 ? rankFrom - 1 : rankFrom;
    final rival = rankFrom > 1 ? _rivals[(rankFrom - 2).clamp(0, _rivals.length - 1)] : '';

    // The streak and the chest of the day come after the FIRST passed lesson of a day, i.e. while the
    // chest of the day has not been taken today.
    final fullPath = passed && ds.chestDate != DemoState.today();

    if (passed) {
      ds.passLevel = levelTo;
      ds.passXp = xpTo;
      ds.rankPos = rankTo;
      ds.save();
    }
    return _Outcome(
      number: lesson.number,
      left: left,
      passed: passed,
      fullPath: fullPath,
      total: points,
      pLesson: pLesson,
      pAccuracy: pAccuracy,
      pSpeed: pSpeed,
      goalFrom: goalFrom,
      goalTo: goalTo,
      goalOf: goalOf,
      levelFrom: levelFrom,
      levelTo: levelTo,
      xpFrom: xpFrom,
      xpTo: xpTo,
      rankFrom: rankFrom,
      rankTo: rankTo,
      rival: rival,
    );
  }
}

enum _Step { score, streak, chest }

/// The end of a lesson for the demo build. Pops `true` to repeat the lesson, `false` otherwise.
class DemoResultsFlow extends StatefulWidget {
  final Lesson lesson;
  final LessonPassStats? stats;
  const DemoResultsFlow({super.key, required this.lesson, this.stats});

  @override
  State<DemoResultsFlow> createState() => _DemoResultsFlowState();
}

class _DemoResultsFlowState extends State<DemoResultsFlow> {
  late final _Outcome _o = _Outcome.of(widget.lesson, widget.stats, DemoState.instance);
  _Step _step = _Step.score;
  bool _leaving = false;

  /// Achievements this lesson earned are fetched while the results show, and celebrated on leaving.
  Future<List<UserAchievement>>? _newAchievements;

  @override
  void initState() {
    super.initState();
    _newAchievements = takeNewAchievements();
  }

  Future<void> _leave({bool repeat = false}) async {
    if (_leaving) return;
    _leaving = true;
    final pending = _newAchievements;
    if (pending != null) {
      final achievements = await pending.timeout(const Duration(seconds: 2), onTimeout: () => const <UserAchievement>[]);
      if (achievements.isNotEmpty && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AchievementCelebrationScreen(achievements: achievements)));
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(repeat);
  }

  void _go(_Step step) => setState(() => _step = step);

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (_step) {
      _Step.score => _ScoreStep(
          key: const ValueKey('step-score'),
          o: _o,
          onContinue: () => _o.fullPath ? _go(_Step.streak) : _leave(),
          onRepeat: () => _leave(repeat: true),
          onLater: () => _leave(),
        ),
      _Step.streak => _StreakStep(key: const ValueKey('step-streak'), onContinue: () => _go(_Step.chest)),
      _Step.chest => _ChestStep(key: const ValueKey('step-chest'), onDone: () => _leave()),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
            child: Column(children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  key: const ValueKey('lesson-results-close'),
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  icon: Icon(Icons.close_rounded, color: _C.muted),
                  onPressed: () => _leave(),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: _ms(350),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(a), child: child),
                  ),
                  child: body,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Pieces shared by the steps

class _Reveal extends StatelessWidget {
  final bool shown;
  final Widget child;
  const _Reveal({required this.shown, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: shown ? 1 : 0,
        duration: _ms(400),
        child: AnimatedSlide(offset: shown ? Offset.zero : const Offset(0, 0.08), duration: _ms(400), curve: Curves.easeOut, child: child),
      );
}

class _Bar extends StatelessWidget {
  final double value;
  final Color color;
  final bool animate;
  const _Bar({required this.value, required this.color, this.animate = true});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: SizedBox(
          height: 10,
          child: Stack(children: [
            Positioned.fill(child: ColoredBox(color: _C.track)),
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: value.clamp(0.0, 1.0)),
                duration: animate ? _ms(1100) : Duration.zero,
                curve: const Cubic(0.3, 0.9, 0.3, 1),
                builder: (_, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v,
                  child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99))),
                ),
              ),
            ),
          ]),
        ),
      );
}

enum _Kind { green, yellow, ghost }

/// The big flat button of the lesson screens: a coloured face on a darker edge that sinks when pressed.
class _BigButton extends StatefulWidget {
  final String label;
  final _Kind kind;
  final VoidCallback onTap;
  final bool shown;
  const _BigButton({super.key, required this.label, required this.kind, required this.onTap, this.shown = true});

  @override
  State<_BigButton> createState() => _BigButtonState();
}

class _BigButtonState extends State<_BigButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final ghost = widget.kind == _Kind.ghost;
    final face = switch (widget.kind) { _Kind.green => _C.green, _Kind.yellow => _C.yellow, _Kind.ghost => Colors.transparent };
    final edge = switch (widget.kind) { _Kind.green => _C.greenEdge, _Kind.yellow => _C.yellowEdge, _Kind.ghost => Colors.transparent };
    final text = switch (widget.kind) { _Kind.green => _C.onGreen, _Kind.yellow => _C.onYellow, _Kind.ghost => _C.muted };
    final h = ghost ? 38.0 : 54.0;
    return IgnorePointer(
      ignoring: !widget.shown,
      child: AnimatedOpacity(
        opacity: widget.shown ? 1 : 0,
        duration: _ms(350),
        child: AnimatedSlide(
          offset: widget.shown ? Offset.zero : const Offset(0, 0.3),
          duration: _ms(350),
          curve: Curves.easeOut,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _down = true),
            onTapCancel: () => setState(() => _down = false),
            onTapUp: (_) => setState(() => _down = false),
            onTap: () {
              DemoSfx.play('pop');
              HapticFeedback.selectionClick();
              widget.onTap();
            },
            child: Container(
              height: h + (ghost ? 0 : 4),
              alignment: Alignment.topCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                margin: EdgeInsets.only(top: !ghost && _down ? 4 : 0),
                height: h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: face,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: ghost || _down ? null : [BoxShadow(color: edge, offset: const Offset(0, 4))],
                ),
                child: Text(
                  ghost ? widget.label : widget.label.toUpperCase(),
                  style: TextStyle(color: text, fontSize: ghost ? 13.5 : 15.5, fontWeight: FontWeight.w800, letterSpacing: ghost ? 0 : 0.4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _eyebrow() => TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1, color: _C.muted);

// ---------------------------------------------------------------------------------------------
// Step 1: the results

class _ScoreStep extends StatefulWidget {
  final _Outcome o;
  final VoidCallback onContinue;
  final VoidCallback onRepeat;
  final VoidCallback onLater;
  const _ScoreStep({super.key, required this.o, required this.onContinue, required this.onRepeat, required this.onLater});

  @override
  State<_ScoreStep> createState() => _ScoreStepState();
}

class _ScoreStepState extends State<_ScoreStep> with SingleTickerProviderStateMixin, _Timers<_ScoreStep> {
  _Outcome get o => widget.o;
  late final AnimationController _count = AnimationController(vsync: this, duration: _ms(750));
  int _lastTick = -1;
  final List<bool> _shown = [false, false, false, false];
  late double _goalFill = o.goalOf == 0 ? 0 : o.goalFrom / o.goalOf;
  late String _goalText = '${o.goalFrom} / ${o.goalOf}';
  late double _passFill = o.xpFrom / _Outcome.levelSize;
  bool _passAnimate = true;
  late int _level = o.levelFrom;
  late String _xpText = '${o.xpFrom} / ${_Outcome.levelSize}';
  late String _rankText = '#${o.rankFrom}';
  bool _pill = false;
  bool _btn = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _count.addListener(_onCount);
    // The rhythm of the mockup (milliseconds before the speed factor): the number counts up,
    // the four blocks appear one by one, the goal fills, the pass fills (and may level up),
    // the place in the rating moves, and the button is there well before the last of it ends.
    later(250, () => _count.forward());
    var t = 450.0;
    for (var i = 0; i < 4; i++) {
      final index = i;
      later(t, () {
        setState(() => _shown[index] = true);
        DemoSfx.play('tile');
        if (index == 0 && o.passed) HapticFeedback.mediumImpact();
      });
      t += 180;
    }
    t += 150;
    if (o.goalTo != o.goalFrom) {
      later(t, () {
        setState(() {
          _goalFill = o.goalOf == 0 ? 0 : o.goalTo / o.goalOf;
          _goalText = '${o.goalTo} / ${o.goalOf}';
        });
        if (o.goalTo >= o.goalOf && o.goalFrom < o.goalOf) later(700, () => DemoSfx.play('goal'));
      });
      t += 800;
    }
    later(t, _fillPass);
    final tr = t + (o.passed ? 1500 : 600);
    later(tr, () {
      setState(() {
        _rankText = '#${o.rankTo}';
        _pill = o.rankFrom > 1;
      });
      DemoSfx.play(o.passed ? 'rank' : 'soft');
    });
    later((tr + 700) < 2600 ? tr + 700 : 2600, () => setState(() => _btn = true));
  }

  void _fillPass() {
    if (!o.passed) {
      setState(() => _passFill = o.xpFrom / _Outcome.levelSize);
      return;
    }
    if (o.levelTo > o.levelFrom) {
      setState(() => _passFill = 1);
      later(1150, () {
        setState(() {
          _passAnimate = false;
          _passFill = 0;
          _level = o.levelTo;
          _xpText = '0 / ${_Outcome.levelSize}';
        });
        DemoSfx.play('rise');
        HapticFeedback.mediumImpact();
        later(60, () {
          setState(() {
            _passAnimate = true;
            _passFill = o.xpTo / _Outcome.levelSize;
            _xpText = '${o.xpTo} / ${_Outcome.levelSize}';
          });
        });
      });
    } else {
      setState(() {
        _passFill = o.xpTo / _Outcome.levelSize;
        _xpText = '${o.xpTo} / ${_Outcome.levelSize}';
      });
    }
  }

  void _onCount() {
    final v = (Curves.easeOutCubic.transform(_count.value) * o.total).round();
    if (v != _lastTick && v > 0 && v % 4 == 0) DemoSfx.play('tick');
    _lastTick = v;
  }

  /// A long press on the points block: the next lesson shows the whole path again, as on a new day
  /// (a demo helper: nobody can wait for tomorrow).
  void _newDay() {
    final ds = DemoState.instance;
    ds.chestDate = '';
    ds.streakDate = '';
    ds.save();
    HapticFeedback.mediumImpact();
    setState(() => _hint = tr('Следующий урок снова покажет весь путь'));
    later(4000, () => setState(() => _hint = null));
  }

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  Widget _tile({required Widget child, Color? color, VoidCallback? onLongPress}) => GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color ?? _C.tile,
            borderRadius: BorderRadius.circular(20),
            border: color == null ? Border.all(color: _C.line) : null,
          ),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _C.muted);
    final big = TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: _C.ink, height: 1.1);
    final goalDone = o.goalOf > 0 && o.goalTo >= o.goalOf;
    final sub = _hint ??
        (o.passed
            ? tr('{0} урок + {1} точность + {2} скорость', [o.pLesson, o.pAccuracy, o.pSpeed])
            : tr('{0} за ответы, ещё +{1} после урока', [o.total, 27]));
    final pillText = o.passed ? tr('Вы обошли {0}', [o.rival]) : tr('до {0}: {1}', [o.rival, 29]);

    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 8),
            Center(
              child: Text(
                (o.passed ? tr('Урок {0} пройден', [o.number]) : tr('Урок {0}: осталось слов: {1}', [o.number, o.left])).toUpperCase(),
                textAlign: TextAlign.center,
                style: _eyebrow(),
              ),
            ),
            const SizedBox(height: 14),
            _Reveal(
              shown: _shown[0],
              child: _tile(
                color: _C.lilac,
                onLongPress: _newDay,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('очков за урок'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _C.onLilac.withValues(alpha: 0.85))),
                  AnimatedBuilder(
                    animation: _count,
                    builder: (_, _) => Text(
                      '+${(Curves.easeOutCubic.transform(_count.value) * o.total).round()}',
                      key: const ValueKey('score-total'),
                      style: TextStyle(fontSize: 64, fontWeight: FontWeight.w800, letterSpacing: -3, height: 1.05, color: _C.onLilac, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
                  Text(sub, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _C.onLilac.withValues(alpha: 0.85))),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: _Reveal(
                  shown: _shown[1],
                  child: _tile(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('Цель дня'), style: label),
                      const SizedBox(height: 4),
                      Text(_goalText, style: big),
                      const SizedBox(height: 8),
                      _Bar(value: _goalFill, color: goalDone ? _C.green : _C.yellow),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Reveal(
                  shown: _shown[2],
                  child: _tile(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('Пропуск'), style: label),
                      const SizedBox(height: 4),
                      Text(tr('Ур. {0}', [_level]), style: big),
                      const SizedBox(height: 8),
                      _Bar(value: _passFill, color: _C.lilac, animate: _passAnimate),
                      const SizedBox(height: 6),
                      Text(_xpText, style: label),
                    ]),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            _Reveal(
              shown: _shown[3],
              child: _tile(
                child: Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Рейтинг'), style: label),
                    const SizedBox(height: 2),
                    Text(_rankText, style: big),
                  ]),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: _pill ? 1 : 0,
                    duration: _ms(400),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: _C.greenSoft, borderRadius: BorderRadius.circular(99)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (o.passed) Icon(Icons.arrow_upward_rounded, size: 14, color: _C.greenText),
                        if (o.passed) const SizedBox(width: 2),
                        Text(pillText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _C.greenText)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      if (o.passed)
        _BigButton(key: const ValueKey('score-continue'), label: tr('Продолжить'), kind: _Kind.green, shown: _btn, onTap: widget.onContinue)
      else ...[
        _BigButton(key: const ValueKey('score-repeat'), label: tr('Добить слова: {0}', [o.left]), kind: _Kind.yellow, shown: _btn, onTap: widget.onRepeat),
        const SizedBox(height: 4),
        _BigButton(key: const ValueKey('score-later'), label: tr('Позже'), kind: _Kind.ghost, shown: _btn, onTap: widget.onLater),
      ],
    ]);
  }
}

// ---------------------------------------------------------------------------------------------
// Step 2: the streak

class _StreakStep extends StatefulWidget {
  final VoidCallback onContinue;
  const _StreakStep({super.key, required this.onContinue});

  @override
  State<_StreakStep> createState() => _StreakStepState();
}

class _StreakStepState extends State<_StreakStep> with _Timers<_StreakStep> {
  final DemoState _ds = DemoState.instance;
  late final bool _grew = _ds.streakDate != DemoState.today();
  late final int _before = _ds.streak; // days in a row before this lesson counted today
  late int _shownDays = _before;
  late bool _todayOn = !_grew;
  bool _btn = false;

  @override
  void initState() {
    super.initState();
    if (_grew) {
      _ds.streak = _before + 1;
      _ds.streakDate = DemoState.today();
      _ds.save();
      later(600, () {
        setState(() => _shownDays = _before + 1);
        DemoSfx.play('pop');
      });
      later(1100, () {
        setState(() => _todayOn = true);
        DemoSfx.play('goal');
      });
    }
    later(_grew ? 1700 : 600, () => setState(() => _btn = true));
  }

  @override
  Widget build(BuildContext context) {
    final todayIdx = DateTime.now().weekday - 1;
    // Days of this week already counted: those before today inside the streak that ended yesterday.
    final yesterdayStreak = _grew ? _before : _ds.streak - 1;
    final letters = [tr('Пн'), tr('Вт'), tr('Ср'), tr('Чт'), tr('Пт'), tr('Сб'), tr('Вс')];
    return Column(children: [
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const AnimatedFire(size: 104),
              SizedBox(
                height: 80,
                child: AnimatedSwitcher(
                  duration: _ms(550),
                  transitionBuilder: (child, a) {
                    final incoming = child.key == ValueKey<int>(_shownDays);
                    final offset = Tween<Offset>(begin: incoming ? const Offset(0, 1) : const Offset(0, -1), end: Offset.zero).animate(a);
                    return ClipRect(child: SlideTransition(position: offset, child: FadeTransition(opacity: a, child: child)));
                  },
                  child: Text(
                    '$_shownDays',
                    key: ValueKey<int>(_shownDays),
                    style: TextStyle(fontSize: 72, fontWeight: FontWeight.w800, letterSpacing: -3, height: 1.1, color: _C.ink),
                  ),
                ),
              ),
              Text(tr('дней подряд'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: _C.ink)),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < 7; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _Day(
                      letter: letters[i],
                      on: i < todayIdx ? (todayIdx - i) <= yesterdayStreak : (i == todayIdx && _todayOn),
                      today: i == todayIdx,
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              Text(
                tr('Завтра будет {0}. Зайдите хотя бы на один урок.', [_ds.streak + 1]),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.4, color: _C.muted),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 10),
      _BigButton(key: const ValueKey('streak-continue'), label: tr('Продолжить'), kind: _Kind.green, shown: _btn, onTap: widget.onContinue),
    ]);
  }
}

class _Day extends StatelessWidget {
  final String letter;
  final bool on;
  final bool today;
  const _Day({required this.letter, required this.on, required this.today});

  @override
  Widget build(BuildContext context) => Column(children: [
        AnimatedContainer(
          duration: _ms(350),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? _C.fire : _C.track,
            border: today ? Border.all(color: _C.fire, width: 2) : null,
          ),
          child: on ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : null,
        ),
        const SizedBox(height: 6),
        Text(letter, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _C.muted)),
      ]);
}

// ---------------------------------------------------------------------------------------------
// Step 3: the chest of the day, handed out and opened right here

class _ChestStep extends StatefulWidget {
  final VoidCallback onDone;
  const _ChestStep({super.key, required this.onDone});

  @override
  State<_ChestStep> createState() => _ChestStepState();
}

class _ChestStepState extends State<_ChestStep> with SingleTickerProviderStateMixin, _Timers<_ChestStep> {
  final DemoState _ds = DemoState.instance;
  late final AnimationController _wobble = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  bool _open = false;
  bool _prize = false;
  bool _btn = false;

  /// One prize, as with every chest (the demo picks from a few sizes of diamonds).
  late final int _amount = 10 + (DateTime.now().day % 4) * 5;

  void _openChest() {
    if (_open) return;
    setState(() => _open = true);
    _wobble.stop();
    DemoSfx.playAsset('sounds/chest-open.mp3');
    HapticFeedback.heavyImpact();
    // The chest is taken the moment it is opened; the diamonds are the prize.
    _ds.diamonds += _amount;
    _ds.chestDate = DemoState.today();
    _ds.save();
    later(350, () {
      setState(() => _prize = true);
      DemoSfx.play('prize');
    });
    later(700, () => setState(() => _btn = true));
  }

  @override
  void dispose() {
    _wobble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tr('Сундук дня').toUpperCase(), style: _eyebrow()),
              const SizedBox(height: 6),
              Text(_prize ? tr('Забрано') : tr('Он ваш'), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: _C.ink)),
              const SizedBox(height: 18),
              GestureDetector(
                key: const ValueKey('daily-chest-image'),
                onTap: _openChest,
                child: AnimatedBuilder(
                  animation: _wobble,
                  builder: (_, child) {
                    final v = _wobble.value;
                    // A few quick tilts, then a pause, again and again until it is opened.
                    final angle = v < 0.7 ? 0.087 * (1 - v / 0.7) * (v * 18 % 2 < 1 ? 1 : -1) : 0.0;
                    return Transform.rotate(angle: angle, child: child);
                  },
                  child: AnimatedScale(
                    scale: _open ? 0.8 : 1,
                    duration: _ms(500),
                    curve: Curves.easeOutBack,
                    child: AnimatedOpacity(
                      opacity: _open ? 0.55 : 1,
                      duration: _ms(500),
                      child: ChestImage('wood', open: _open, size: 150),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              AnimatedOpacity(
                opacity: _prize ? 1 : 0,
                duration: _ms(450),
                child: AnimatedScale(
                  scale: _prize ? 1 : 0.8,
                  duration: _ms(450),
                  curve: Curves.easeOutBack,
                  child: Container(
                    key: const ValueKey('daily-chest-prize'),
                    width: 110,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: _C.tile, borderRadius: BorderRadius.circular(18), border: Border.all(color: _C.line)),
                    child: Column(children: [
                      const DiamondIcon(size: 46),
                      const SizedBox(height: 4),
                      Text('+$_amount', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _C.ink)),
                      Text(tr('алмазов'), style: TextStyle(fontSize: 12, color: _C.muted)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 10),
      if (_open)
        _BigButton(key: const ValueKey('chest-done'), label: tr('К урокам'), kind: _Kind.green, shown: _btn, onTap: widget.onDone)
      else
        _BigButton(key: const ValueKey('chest-open'), label: tr('Открыть'), kind: _Kind.yellow, onTap: _openChest),
    ]);
  }
}
