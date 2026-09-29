import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/user_profile.dart';
import 'package:guyo_app/screens/achievements_screen.dart';

UserAchievement _a(int id,
    {String? title, String? description, int? goal, bool earned = false, int? current, String type = 'words_learned'}) {
  return UserAchievement.fromJson({
    'id': id,
    'title': title,
    'description': description,
    'icon_url': null,
    'color': '#5862DD',
    'condition_type': title == null ? null : type,
    'condition_value': goal,
    'earned': earned,
    'earned_at': earned ? '2026-09-21T10:00:00Z' : null,
    'current_value': current,
  });
}

void main() {
  final achievements = [
    _a(1, title: 'Первые слова', description: 'Выучить 5 слов', goal: 5, earned: true),
    _a(2, title: 'Очень длинное название достижения на две строки', description: 'Выучить сто слов в разных темах и не сдаваться никогда', goal: 100, current: 42),
    _a(3), // hidden
    _a(4, title: 'Серия', description: '7 дней подряд', goal: 7, current: 3),
  ];

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AchievementsScreen(achievements: achievements)));
    await tester.pump();
  }

  testWidgets('shows a three-per-row badge wall with goals and a summary', (tester) async {
    await pump(tester, const Size(360, 800));
    expect(find.text('Получено 1 из 4'), findsOneWidget);
    expect(find.text('Первые слова'), findsOneWidget);
    expect(find.text('Скрытое'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
    // Three per row; the hidden one sorts last, onto the second row.
    final y1 = tester.getTopLeft(find.byKey(const ValueKey('achievement-1'))).dy;
    final y2 = tester.getTopLeft(find.byKey(const ValueKey('achievement-2'))).dy;
    final y3 = tester.getTopLeft(find.byKey(const ValueKey('achievement-3'))).dy;
    expect(y1, y2);
    expect(y3, greaterThan(y1));
  });

  testWidgets('tapping a badge in progress shows its progress', (tester) async {
    await pump(tester, const Size(360, 800));
    await tester.tap(find.byKey(const ValueKey('achievement-2')));
    await tester.pumpAndSettle();
    expect(find.text('42 из 100'), findsOneWidget);
  });

  testWidgets('tapping an earned badge shows when it was earned', (tester) async {
    await pump(tester, const Size(360, 800));
    await tester.tap(find.byKey(const ValueKey('achievement-1')));
    await tester.pumpAndSettle();
    expect(find.text('Получено 21 сентября 2026'), findsOneWidget);
  });

  testWidgets('fits a narrow phone without overflow', (tester) async {
    await pump(tester, const Size(320, 640));
    expect(tester.takeException(), isNull);
  });

  test('earned first, then by type in admin order, then by goal; hidden last', () {
    final sorted = sortAchievements([
      _a(10, title: 'Серия 7', goal: 7, type: 'streak_days'),
      _a(11, title: 'Фразы 50', goal: 50, type: 'phrases_opened'),
      _a(12, title: 'Уроки 1', goal: 1, type: 'lessons_completed', earned: true),
      _a(13), // hidden
      _a(14, title: 'Фразы 5', goal: 5, type: 'phrases_opened', earned: true),
      _a(15, title: 'Фразы 10', goal: 10, type: 'phrases_opened'),
      _a(16, title: 'Серия 3', goal: 3, type: 'streak_days', earned: true),
    ]);
    expect(sorted.map((a) => a.id).toList(), [14, 12, 16, 15, 11, 10, 13]);
  });
}
