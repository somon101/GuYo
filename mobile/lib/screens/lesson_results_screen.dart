import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/lesson.dart';
import '../models/user_profile.dart';
import '../services/answer_sound.dart';
import '../theme/app_colors.dart';
import 'achievement_celebration_screen.dart';
import 'lesson_results_flow.dart';
import 'lesson_results_source.dart';

/// Set when «Начать урок N» is pressed on the results: the lessons list, as it gets the screen
/// back, opens the next lesson at once. Good for a few seconds only, so a results screen closed
/// from elsewhere never starts a lesson later by surprise.
DateTime? _nextLessonAskedAt;

/// True once, right after «Начать урок N» was pressed.
bool takeNextLessonRequest() {
  final at = _nextLessonAskedAt;
  _nextLessonAskedAt = null;
  return at != null && DateTime.now().difference(at) < const Duration(seconds: 5);
}

/// How the end of a lesson is built. The app shows [LessonResultsScreen]; a build may put its own
/// screen here before the app starts (the demo build does), the lesson flow does not care which.
/// The screen must pop `true` to repeat the lesson and `false` (or nothing) otherwise.
Widget Function(Lesson lesson, LessonPassStats? stats) lessonResultsBuilder =
    (lesson, stats) => LessonResultsFlow(lesson: lesson, stats: stats, source: AppResultsSource());

/// The end of a lesson (variant C, «дорожка уроков»): not a report but a step forward. The
/// headline says what happened, three chips give the numbers (words held, accuracy, time), and a
/// little road shows the lesson just done lighting up and the next one opening, with the next
/// step as the one big button.
///
/// - All words learned: «Урок N пройден», the next lesson's node wakes up, the main button is
///   «Начать урок N+1» and the quiet one «На сегодня хватит».
/// - Some words still short: never a «failure». «Осталось слов: K», the lesson's node shows
///   «4/6», the next one stays locked, the main button is «Добить слова» (the repeat covers only
///   those words) and the quiet one «Позже».
///
/// Never computes "is this word learned" itself: `lesson.words` is a FRESH fetch taken right
/// after the exercises, so it is exactly what the backend says.
///
/// Pops `true` for a repeat (the caller re-runs the sequence), `false`/nothing otherwise.
class LessonResultsScreen extends StatefulWidget {
  final Lesson lesson;

  /// The pass's statistics; null (couldn't be loaded) just hides the accuracy and the time.
  final LessonPassStats? stats;
  const LessonResultsScreen({super.key, required this.lesson, this.stats});

  @override
  State<LessonResultsScreen> createState() => _LessonResultsScreenState();
}

class _LessonResultsScreenState extends State<LessonResultsScreen> with SingleTickerProviderStateMixin {
  /// Achievements this lesson earned, fetched WHILE the results are on screen so the celebration
  /// can be shown the instant the user leaves -- never as a dialog on top of the results.
  Future<List<UserAchievement>>? _newAchievements;

  /// The opening: the headline and chips, the lesson's node lighting up, the next node waking,
  /// the card, the buttons. Short: nobody should wait to press the button.
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
  bool _chimed = false;
  bool _leaving = false;

  int get _learned => widget.lesson.words.where((w) => w.isLearned).length;
  int get _total => widget.lesson.words.length;
  bool get _passed => widget.lesson.isCompleted || (_total > 0 && _learned == _total);

  @override
  void initState() {
    super.initState();
    _newAchievements = takeNewAchievements();
    _intro.addListener(_onTick);
    _intro.forward();
  }

  /// One chime and a light tap as the lesson's node lights up (only when it does).
  void _onTick() {
    if (_chimed || _intro.value < 0.3) return;
    _chimed = true;
    if (_passed) {
      HapticFeedback.mediumImpact();
      unawaited(AnswerSound.play(true).catchError((_) {}));
    } else {
      HapticFeedback.selectionClick();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Leaves the results: any achievement earned this lesson is celebrated first, on a screen of
  /// its own, and only then does the lesson flow continue.
  Future<void> _leave({required bool repeat, bool next = false}) async {
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
    if (next) _nextLessonAskedAt = DateTime.now();
    Navigator.of(context).pop(repeat);
  }

  Animation<double> _at(double begin, double end) => CurvedAnimation(parent: _intro, curve: Interval(begin, end, curve: Curves.easeOutCubic));

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    final stats = widget.stats;
    final hasStats = stats != null && stats.totalAnswers > 0;
    final passed = _passed;
    final left = _total - _learned;
    final next = lesson.number + 1;

    return PopScope(
      // The system back gesture means the same as the quiet button: leave, no repeat.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave(repeat: false));
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
                  icon: Icon(Icons.close_rounded, color: AppColors.secondaryText),
                  onPressed: () => _leave(repeat: false),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(children: [
                    const SizedBox(height: 4),
                    _Reveal(
                      animation: _at(0.0, 0.2),
                      child: Text(
                        passed ? tr('Урок {0} пройден', [lesson.number]) : tr('Осталось слов: {0}', [left]),
                        key: const ValueKey('lesson-results-title'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 30, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AppColors.primaryDark),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Reveal(
                      animation: _at(0.08, 0.28),
                      child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                        _Chip(key: const ValueKey('chip-words'), text: tr('Слова: {0} из {1}', [_learned, _total])),
                        if (hasStats) _Chip(key: const ValueKey('chip-accuracy'), text: '${stats.accuracy}% ${tr('точность')}'),
                        if (hasStats) _Chip(key: const ValueKey('chip-time'), text: _clock(stats.durationSeconds)),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    AnimatedBuilder(
                      animation: _intro,
                      builder: (_, _) => _Road(
                        previous: lesson.number > 1 ? lesson.number - 1 : null,
                        current: lesson.number,
                        next: next,
                        passed: passed,
                        progressLabel: '$_learned/$_total',
                        lit: Interval(0.28, 0.5, curve: Curves.easeOutBack).transform(_intro.value),
                        woke: passed ? Interval(0.55, 0.75, curve: Curves.easeOutBack).transform(_intro.value) : 0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Reveal(
                      animation: _at(0.7, 0.88),
                      child: Container(
                        key: const ValueKey('lesson-results-next-card'),
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.cardBorder)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            passed ? tr('Урок {0} открыт', [next]) : tr('Урок {0} откроется после этих слов', [next]),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            passed ? tr('Новые слова уже ждут') : tr('Это меньше минуты: повтор возьмёт только их'),
                            style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
                          ),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
              _Reveal(
                animation: _at(0.82, 1.0),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (passed)
                    ChunkyButton(
                      key: const ValueKey('lesson-results-next'),
                      label: tr('Начать урок {0}', [next]),
                      color: _indigo,
                      shade: _indigoShade,
                      onTap: () => _leave(repeat: false, next: true),
                    )
                  else
                    ChunkyButton(
                      key: const ValueKey('lesson-results-repeat'),
                      label: tr('Добить слова: {0}', [left]),
                      color: _amber,
                      shade: _amberShade,
                      onTap: () => _leave(repeat: true),
                    ),
                  const SizedBox(height: 4),
                  TextButton(
                    key: const ValueKey('lesson-results-later'),
                    onPressed: () => _leave(repeat: false),
                    child: Text(
                      (passed ? tr('На сегодня хватит') : tr('Позже')).toUpperCase(),
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.secondaryText),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// Button colours: clear on a white screen, lighter than a dark forest green (the owner's remark).
const Color _green = Color(0xFF22A866);
const Color _greenShade = Color(0xFF178A57);
const Color _amber = Color(0xFFF08C1A);
const Color _amberShade = Color(0xFFC06A0A);
const Color _indigo = Color(0xFF5B66E8);
const Color _indigoShade = Color(0xFF434DC4);

String _clock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({super.key, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.cardBorder)),
        child: Text(text, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
      );
}

/// Fades and lifts its child in as [animation] runs.
class _Reveal extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const _Reveal({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (_, c) => Opacity(
          opacity: animation.value.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, 14 * (1 - animation.value)), child: c),
        ),
      );
}

/// The little road: the lesson before (done), this one, the next. [lit] 0..1 lights this
/// lesson's node (when passed), [woke] 0..1 opens the next one.
class _Road extends StatelessWidget {
  final int? previous;
  final int current;
  final int next;
  final bool passed;
  final String progressLabel;
  final double lit;
  final double woke;
  const _Road({required this.previous, required this.current, required this.next, required this.passed, required this.progressLabel, required this.lit, required this.woke});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final p0 = Offset(w * 0.2, 170), p1 = Offset(w * 0.5, 105), p2 = Offset(w * 0.8, 40);
        Widget at(Offset p, Widget child) => Positioned(left: p.dx - 31, top: p.dy - 31, width: 62, height: 62, child: child);
        final done = passed && lit > 0.02;
        return Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _DotsPainter(points: [if (previous != null) p0, p1, p2], color: AppColors.progressTrack))),
          if (previous != null) at(p0, _Node(label: '$previous', color: _green, shade: _greenShade)),
          at(
            p1,
            Transform.scale(
              scale: done ? 0.85 + 0.15 * lit : 1,
              child: done
                  ? _Node(key: const ValueKey('road-current-done'), label: '$current', color: _green, shade: _greenShade)
                  : passed
                      ? _Node(label: '$current', color: AppColors.progressTrack, shade: AppColors.cardBorder, text: AppColors.secondaryText)
                      : _RingNode(key: const ValueKey('road-current-part'), label: progressLabel),
            ),
          ),
          at(
            p2,
            woke > 0.02
                ? Transform.scale(scale: 0.85 + 0.15 * woke, child: _Node(key: const ValueKey('road-next-open'), label: '$next', color: _indigo, shade: _indigoShade))
                : _Node(key: const ValueKey('road-next-locked'), label: '$next', color: AppColors.progressTrack, shade: AppColors.cardBorder, text: AppColors.secondaryText),
          ),
        ]);
      }),
    );
  }
}

class _Node extends StatelessWidget {
  final String label;
  final Color color;
  final Color shade;
  final Color text;
  const _Node({super.key, required this.label, required this.color, required this.shade, this.text = Colors.white});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: shade, offset: const Offset(0, 5))]),
        child: Text(label, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: text)),
      );
}

/// This lesson when some words are still short: an amber ring with «4/6» inside.
class _RingNode extends StatelessWidget {
  final String label;
  const _RingNode({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.canvas, shape: BoxShape.circle, border: Border.all(color: _amber, width: 5)),
        child: FittedBox(child: Padding(padding: const EdgeInsets.all(6), child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _amber)))),
      );
}

/// Round dots along the straight runs between the nodes.
class _DotsPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  const _DotsPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i], b = points[i + 1];
      final n = ((b - a).distance / 20).floor();
      for (var k = 2; k < n - 1; k++) {
        canvas.drawCircle(Offset.lerp(a, b, k / n)!, 4.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.points.length != points.length || old.color != color;
}

/// The big bottom button of the lesson flow: a flat face on a darker edge, which it sinks onto
/// while pressed. Capitals, one line.
class ChunkyButton extends StatefulWidget {
  final String label;
  final Color color;
  final Color shade;
  final VoidCallback onTap;
  const ChunkyButton({super.key, required this.label, required this.color, required this.shade, required this.onTap});

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: SizedBox(
        height: 58,
        child: Stack(children: [
          Positioned(left: 0, right: 0, top: 4, bottom: 0, child: DecoratedBox(decoration: BoxDecoration(color: widget.shade, borderRadius: BorderRadius.circular(16)))),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 70),
            left: 0,
            right: 0,
            top: _down ? 4 : 0,
            bottom: _down ? 0 : 4,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(16)),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(widget.label.toUpperCase(), maxLines: 1, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: Colors.white)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
