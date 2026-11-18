import 'package:flutter/material.dart';

import '../models/lesson.dart';
import '../screens/lesson_results_flow.dart';
import 'demo_state.dart';

export '../screens/lesson_results_flow.dart' show ResultsSfx;

/// The sounds of the results path, under the name the demo and its tests have always used.
typedef DemoSfx = ResultsSfx;

/// The people just above the player in the rating (position 2 is the first of them, and so on).
const List<String> _rivals = ['Aziz', 'Madina', 'Rustam', 'Nilufar', 'Jasur', 'Zarina', 'Sardor', 'Malika'];

/// The numbers of the end of a lesson on made-up data (demo build only, see main_demo.dart): the
/// points are worked out from the lesson, the pass, the rating place, the streak and the chest of the
/// day live in [DemoState].
class DemoResultsSource extends ResultsSource {
  static const int levelSize = 400;

  @override
  Future<ResultsOutcome> outcome(Lesson lesson, LessonPassStats? stats) async {
    final ds = DemoState.instance;
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
    return ResultsOutcome(
      number: lesson.number,
      left: left,
      passed: passed,
      showStreak: fullPath,
      showChest: fullPath,
      total: points,
      pLesson: pLesson,
      pAccuracy: pAccuracy,
      pSpeed: pSpeed,
      afterLesson: 27,
      goalFrom: goalFrom,
      goalTo: goalTo,
      goalOf: goalOf,
      levelFrom: levelFrom,
      levelTo: levelTo,
      xpFrom: xpFrom,
      xpTo: xpTo,
      sizeFrom: levelSize,
      sizeTo: levelSize,
      rankFrom: rankFrom,
      rankTo: rankTo,
      rival: rival,
      rivalGap: 29,
    );
  }

  @override
  StreakView streak() {
    final ds = DemoState.instance;
    final grew = ds.streakDate != DemoState.today();
    final before = ds.streak;
    if (grew) {
      ds.streak = before + 1;
      ds.streakDate = DemoState.today();
      ds.save();
    }
    return StreakView(before: grew ? before : before - 1, grew: grew);
  }

  @override
  Future<DailyPrize?> openDailyChest() async {
    final ds = DemoState.instance;
    // One prize, as with every chest (the demo picks from a few sizes of diamonds).
    final amount = 10 + (DateTime.now().day % 4) * 5;
    ds.diamonds += amount;
    ds.chestDate = DemoState.today();
    ds.save();
    return DailyPrize('diamonds', amount);
  }

  @override
  VoidCallback? get newDay => () {
        final ds = DemoState.instance;
        ds.chestDate = '';
        ds.streakDate = '';
        ds.save();
      };
}

/// The end of a lesson for the demo build.
Widget demoResultsFlow(Lesson lesson, LessonPassStats? stats) =>
    LessonResultsFlow(lesson: lesson, stats: stats, source: DemoResultsSource());
