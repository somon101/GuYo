// The greeting's sky object must follow the DEVICE's clock and must be
// configurable without touching the widget. Both are checkable without a
// backend or an app build, so they are checked here -- this whole file
// runs in well under a second.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/theme/time_of_day.dart';

void main() {
  group('the standard boundaries', () {
    const scheme = TimeOfDayScheme.standard;

    // Every hour of the day, so a boundary cannot be moved by accident.
    const expected = <int, DayPart>{
      0: DayPart.night,
      4: DayPart.night,
      5: DayPart.morning,
      10: DayPart.morning,
      11: DayPart.day,
      16: DayPart.day,
      17: DayPart.evening,
      21: DayPart.evening,
      22: DayPart.night,
      23: DayPart.night,
    };

    expected.forEach((hour, part) {
      test('$hour:00 is ${part.name}', () {
        expect(scheme.partAt(DateTime(2026, 9, 25, hour, 30)), part);
      });
    });

    test('midnight and the last minute of the day are both night', () {
      expect(scheme.partAt(DateTime(2026, 9, 25, 0, 0)), DayPart.night);
      expect(scheme.partAt(DateTime(2026, 9, 25, 23, 59)), DayPart.night);
    });

    test('every part has a look, so none can render blank', () {
      for (final part in DayPart.values) {
        expect(dayPartLooks[part], isNotNull, reason: '${part.name} has no sky');
      }
    });

    test('the four parts look different from each other', () {
      final skies = DayPart.values.map((p) => dayPartLooks[p]!.skyTop).toSet();
      expect(skies.length, DayPart.values.length, reason: 'two parts share a sky');
    });
  });

  test('the boundaries are configurable without touching the widget', () {
    // A scheme with different hours AND fewer parts -- the point is that
    // changing this list is all it takes.
    const nightOwl = TimeOfDayScheme([
      DayPartWindow(DayPart.night, 0),
      DayPartWindow(DayPart.day, 9),
      DayPartWindow(DayPart.night, 20),
    ]);

    expect(nightOwl.partAt(DateTime(2026, 9, 25, 8, 59)), DayPart.night);
    expect(nightOwl.partAt(DateTime(2026, 9, 25, 9, 0)), DayPart.day);
    expect(nightOwl.partAt(DateTime(2026, 9, 25, 19, 59)), DayPart.day);
    expect(nightOwl.partAt(DateTime(2026, 9, 25, 20, 0)), DayPart.night);
  });

  testWidgets('the icon follows the moment it is given, not the server', (tester) async {
    Future<DayPart> partShownAt(DateTime moment) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DayPartIcon(now: moment)),
        ),
      );
      return tester.widget<DaySkyBadge>(find.byType(DaySkyBadge)).part;
    }

    expect(await partShownAt(DateTime(2026, 9, 25, 7, 0)), DayPart.morning);
    expect(await partShownAt(DateTime(2026, 9, 25, 13, 0)), DayPart.day);
    expect(await partShownAt(DateTime(2026, 9, 25, 19, 0)), DayPart.evening);
    expect(await partShownAt(DateTime(2026, 9, 25, 23, 0)), DayPart.night);
  });

  testWidgets('with no moment given it reads this device clock', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DayPartIcon())));
    // DateTime.now() is the device's own local wall clock -- whatever part
    // that is right now, the widget must agree with the scheme about it.
    final expected = TimeOfDayScheme.standard.partAt(DateTime.now());
    expect(tester.widget<DaySkyBadge>(find.byType(DaySkyBadge)).part, expected);
  });

  testWidgets('every part paints at the greeting size without throwing', (tester) async {
    for (final part in DayPart.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: DaySkyBadge(part: part, size: 22)),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: '${part.name} failed to paint');
      expect(find.bySemanticsLabel(dayPartLooks[part]!.label), findsOneWidget);
    }
  });
}
