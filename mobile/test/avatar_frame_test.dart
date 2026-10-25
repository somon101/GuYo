import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/season_pass.dart';
import 'package:guyo_app/screens/cosmetics_screen.dart';
import 'package:guyo_app/widgets/cosmetic_art.dart';
import 'package:guyo_app/widgets/user_avatar.dart';

void main() {
  test('every frame key has colours', () {
    for (final k in ['gold', 'aurora', 'fire', 'ocean', 'emerald', 'royal', 'rose', 'ice', 'unknown']) {
      expect(frameColors(k).length, greaterThanOrEqualTo(3));
    }
  });

  testWidgets('an avatar keeps its size with or without a frame', (tester) async {
    for (final frame in [null, 'gold', '12']) {
      await tester.pumpWidget(MaterialApp(home: Center(child: UserAvatar(avatarUrl: null, login: 'Nigina', size: 60, frame: frame))));
      expect(tester.getSize(find.byType(UserAvatar).first), const Size(60, 60));
    }
  });

  test('catalog keys are plain digits', () {
    expect(isCatalogKey('12'), isTrue);
    expect(isCatalogKey('gold'), isFalse);
    expect(isCatalogKey(null), isFalse);
  });

  test('the collection parses frames, and older servers without them', () {
    final c = CosmeticCollection.fromJson({
      'badges': [],
      'titles': [],
      'frames': [
        {'id': 3, 'kind': 'frame', 'key': 'fire', 'label': 'Огненная', 'season_name': null},
      ],
      'equipped_frame_id': 3,
    });
    expect(c.frames.single.key, 'fire');
    expect(c.equippedFrameId, 3);
    expect(CosmeticCollection.fromJson({'badges': [], 'titles': []}).frames, isEmpty);
  });

  testWidgets('frames are listed and can be worn', (tester) async {
    final c = CosmeticCollection.fromJson({
      'badges': [],
      'titles': [],
      'frames': [
        {'id': 3, 'kind': 'frame', 'key': 'fire', 'label': 'Огненная', 'season_name': null},
      ],
    });
    await tester.pumpWidget(MaterialApp(home: CosmeticsScreen(initial: c)));
    await tester.pump();
    expect(find.text('Рамки аватара'), findsOneWidget);
    expect(find.byKey(const ValueKey('frame-3')), findsOneWidget);
    expect(find.text('Надеть'), findsOneWidget);
  });
}
