// The season recap: parsed from the server's JSON and shown on its screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/widgets/game_icons.dart';
import 'package:guyo_app/models/season_summary.dart';
import 'package:guyo_app/screens/season_summary_screen.dart';

Map<String, dynamic> _json() => {
      'season_id': 3,
      'season_name': 'Октябрь 2026',
      'season_name_tg': null,
      'season_name_uz': null,
      'starts_at': '2026-09-30T19:00:00Z',
      'ends_at': '2026-10-31T19:00:00Z',
      'xp': 640,
      'level': 7,
      'max_level': 20,
      'words_learned': 58,
      'active_days': 19,
      'rewards_claimed': 9,
      'rank_name': 'Серебро',
      'season_points': 1200,
      'badges': ['crown', 'flame'],
      'titles': [
        {'text': 'Чемпион октября', 'text_tg': null, 'text_uz': null},
      ],
    };

void main() {
  captureTests();
  test('parses the recap', () {
    final s = SeasonSummary.fromJson(_json());
    expect(s.level, 7);
    expect(s.wordsLearned, 58);
    expect(s.badges, ['crown', 'flame']);
    expect(s.titles.single.text, 'Чемпион октября');
  });

  testWidgets('shows the numbers, the rank and a share button', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: SeasonSummaryScreen(initial: SeasonSummary.fromJson(_json()))));
    await tester.pump();
    expect(find.textContaining('640 энергии', findRichText: true), findsOneWidget);
    expect(find.byType(EnergyIcon), findsOneWidget);
    expect(find.text('58'), findsOneWidget);
    expect(find.text('Серебро'), findsOneWidget);
    expect(find.text('Чемпион октября'), findsOneWidget);
    expect(find.byKey(const ValueKey('summary-share')), findsOneWidget);
  });
}

void captureTests() {
  testWidgets('the summary card can be captured as a picture', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: SeasonSummaryScreen(initial: SeasonSummary.fromJson(_json()))));
    await tester.pump();
    final boundary = find.byType(RepaintBoundary).evaluate().map((e) => e.widget.key).whereType<GlobalKey>().first;
    final bytes = await tester.runAsync(() => captureCard(boundary, pixelRatio: 1));
    expect(bytes, isNotNull);
    expect(bytes!.sublist(1, 4), [0x50, 0x4E, 0x47]); // "PNG"
  });
}
