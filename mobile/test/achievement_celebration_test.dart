// Covers the unlock celebration's new opening: the badge arrives shut inside
// the geode, four taps crack it open, and only then does the reward become
// readable and its button usable. Also covers the batch: the next achievement
// starts shut again, and the last button is the one that closes the screen.
//
// No backend here -- the screen is driven directly with achievements, exactly
// as `lesson_results_screen` hands them over after takeNewAchievements().
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/models/user_profile.dart';
import 'package:guyo_app/screens/achievement_celebration_screen.dart';

UserAchievement _achievement(int id, String title) => UserAchievement(
      id: id,
      title: title,
      description: 'Условие: $title',
      // No icon URL: the screen then draws the generic fallback badge, so the
      // test never touches the network.
      iconUrl: null,
      color: '#8B5CFF',
      conditionType: 'phrases_opened',
      conditionValue: 10,
      earned: true,
      earnedAt: null,
      currentValue: 10,
    );

/// Pushes the celebration the way the results screen does, so the final
/// «Отлично!» has somewhere to pop back to.
Future<void> _open(WidgetTester tester, List<UserAchievement> achievements) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AchievementCelebrationScreen(achievements: achievements)),
            ),
            child: const Text('открыть'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('открыть'));
  await tester.pump();
  // The route's own transition. Never pumpAndSettle: the light behind the
  // badge breathes for as long as the screen is open, which never settles.
  await tester.pump(const Duration(milliseconds: 600));
}

/// Four taps on the glass. Short pumps, because the cracks are supposed to be
/// seen one after another.
Future<void> _crackOpen(WidgetTester tester, {int taps = 4}) async {
  for (var i = 0; i < taps; i++) {
    await tester.tap(find.byKey(const ValueKey('achievement-geode')));
    await tester.pump(const Duration(milliseconds: 260));
  }
}

/// Runs the break and the reward's entrance to their end.
///
/// The first bare pump is not decoration: a controller that has just been
/// started gets its first tick on the NEXT frame (elapsed zero), so a single
/// long pump would look like the sequence never moved.
Future<void> _playOut(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 2000));
  await tester.pump();
}

/// How visible the reward is: the pill's own entrance opacity. The reward is
/// built from the first frame (so the layout never jumps), which is exactly
/// why "is it there yet" has to be asked as an opacity and not as a finder.
double _rewardOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(of: find.text('Достижение получено!'), matching: find.byType(Opacity)).first,
    )
    .opacity;

FilledButton _nextButton(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

void main() {
  testWidgets('the reward stays shut until the geode has been tapped open', (tester) async {
    await _open(tester, [_achievement(1, 'Первая фраза')]);

    expect(find.text('Нажмите, чтобы открыть'), findsOneWidget, reason: 'the gesture is taught');
    expect(_rewardOpacity(tester), 0, reason: 'nothing of the reward is readable yet');
    expect(_nextButton(tester, 'Отлично!').onPressed, isNull, reason: 'and its button cannot be pressed yet');

    await tester.tap(find.byKey(const ValueKey('achievement-geode')));
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.text('Осталось нажатий: 3'), findsOneWidget, reason: 'the countdown replaces the hint');
    expect(_rewardOpacity(tester), 0);

    await _crackOpen(tester, taps: 3);
    await _playOut(tester);

    expect(find.text('Первая фраза'), findsOneWidget);
    expect(find.text('Условие: Первая фраза'), findsOneWidget);
    expect(_rewardOpacity(tester), 1, reason: 'the reward is finally readable');
    expect(_nextButton(tester, 'Отлично!').onPressed, isNotNull, reason: 'and can be dismissed');
  });

  testWidgets('skipping opens the geode without touching the gesture', (tester) async {
    await _open(tester, [_achievement(1, 'Первая фраза')]);

    await tester.tap(find.byKey(const ValueKey('achievement-celebration-skip')));
    await _playOut(tester);

    expect(_rewardOpacity(tester), 1);
    expect(find.text('Первая фраза'), findsOneWidget);
  });

  testWidgets('each achievement of a batch is cracked open in turn, and the last closes the screen', (tester) async {
    await _open(tester, [_achievement(1, 'Первая фраза'), _achievement(2, 'Сто слов')]);

    await _crackOpen(tester);
    await _playOut(tester);
    expect(find.text('1 из 2'), findsOneWidget, reason: 'the batch is counted');
    expect(_nextButton(tester, 'Следующее').onPressed, isNotNull);

    await tester.tap(find.text('Следующее'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The next one arrives shut again: same geode, same gesture, its own badge.
    expect(find.text('Нажмите, чтобы открыть'), findsOneWidget);
    expect(_rewardOpacity(tester), 0, reason: 'the second reward is not readable either');
    expect(find.text('Сто слов'), findsOneWidget, reason: 'and it is the second achievement on screen');
    expect(_nextButton(tester, 'Отлично!').onPressed, isNull, reason: 'the last one, and still shut');
    expect(find.text('1 из 2'), findsNothing);

    await _crackOpen(tester);
    await _playOut(tester);
    expect(_rewardOpacity(tester), 1);
    expect(find.text('2 из 2'), findsOneWidget);

    await tester.tap(find.text('Отлично!'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AchievementCelebrationScreen), findsNothing, reason: 'the celebration is over');
    expect(find.text('Достижение получено!'), findsNothing);
  });
}
