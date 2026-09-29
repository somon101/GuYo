import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/widgets/skeleton.dart';

void main() {
  final layouts = <String, Widget>{
    'list': const SkeletonList(),
    'list without avatars': const SkeletonList(avatar: false, rows: 4),
    'dashboard': const SkeletonDashboard(),
    'exercise': const SkeletonExercise(options: 4),
    'form': const SkeletonForm(),
    'pulse': const SkeletonPulse(child: Text('Готовим урок…')),
  };

  for (final entry in layouts.entries) {
    testWidgets('${entry.key} lays out on a narrow phone, with no spinner', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: entry.value)));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  }
}
