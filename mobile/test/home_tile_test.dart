// A tile of «Мои награды» on Главная: title, figure, short line and the tap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/widgets/home_tiles.dart';

void main() {
  testWidgets('a tile shows its figure and opens on tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: HomeTile(
            icon: const Icon(Icons.star),
            title: 'Пропуск',
            big: '4 ур.',
            sub: 'Энергии: 120',
            progress: 0.5,
            onTap: () => taps++,
          ),
        ),
      ),
    ));
    expect(find.text('4 ур.'), findsOneWidget);
    expect(find.text('Энергии: 120'), findsOneWidget);
    await tester.tap(find.text('Пропуск'));
    expect(taps, 1);
  });
}
