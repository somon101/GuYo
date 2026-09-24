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
        expect(dayPartLooks[part], isNotNull, reason: '${part.name} has no icon');
      }
    });

    test('the four parts look different from each other', () {
      final icons = DayPart.values.map((p) => dayPartLooks[p]!.icon).toSet();
      expect(icons.length, DayPart.values.length, reason: 'two parts share an icon');
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
    Future<IconData> iconAt(DateTime moment) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DayPartIcon(now: moment))),
      );
      return tester.widget<Icon>(find.byType(Icon)).icon!;
    }

    final morning = await iconAt(DateTime(2026, 9, 25, 7, 0));
    final day = await iconAt(DateTime(2026, 9, 25, 13, 0));
    final evening = await iconAt(DateTime(2026, 9, 25, 19, 0));
    final night = await iconAt(DateTime(2026, 9, 25, 23, 0));

    expect(morning, dayPartLooks[DayPart.morning]!.icon);
    expect(day, dayPartLooks[DayPart.day]!.icon);
    expect(evening, dayPartLooks[DayPart.evening]!.icon);
    expect(night, dayPartLooks[DayPart.night]!.icon);
    expect({morning, day, evening, night}.length, 4);
  });

  testWidgets('with no moment given it reads this device clock', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DayPartIcon())));
    // DateTime.now() is the device's own local wall clock -- whatever part
    // that is right now, the widget must agree with the scheme about it.
    final expectedIcon = dayPartLooks[TimeOfDayScheme.standard.partAt(DateTime.now())]!.icon;
    expect(tester.widget<Icon>(find.byType(Icon)).icon, expectedIcon);
  });
}
