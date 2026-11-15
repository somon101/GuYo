// The «Рейтинг» header: the title on its own line and a full-width switch under it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/screens/rating_screen.dart';

void main() {
  testWidgets('title is one line; friends and global are tappable', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var friends = 0, global = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LeaderboardHeader(title: 'Рейтинг', onOpenFriends: () => friends++, onOpenGlobal: () => global++)),
    ));
    expect(tester.getSize(find.text('Рейтинг')).height, lessThan(50));
    await tester.tap(find.byKey(const ValueKey('rating-mine')));
    await tester.tap(find.byKey(const ValueKey('rating-friends')));
    await tester.tap(find.byKey(const ValueKey('rating-global')));
    expect([friends, global], [1, 1]);
  });
}
