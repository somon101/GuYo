// Guards the one thing that made every wide rank/achievement badge look
// crushed: decoding a remote image into a box by BOTH width and height.
//
// Flutter's own docs describe that case as "similar to BoxFit.fill" -- the
// bitmap is scaled to the two numbers given and the source aspect ratio is
// thrown away, before any `fit:` gets a chance to run. The rank artworks
// are ~1450x830, so a square decode squeezed them by about 40% sideways,
// which is exactly why the two square badges (Бронза, Грандмастер) looked
// right and the five wide ones did not.
//
// Runs headless, no backend needed:
//   flutter test test/remote_image_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/widgets/remote_image.dart';

Widget _wrap(Widget child, {double devicePixelRatio = 3}) {
  return MediaQuery(
    data: MediaQueryData(devicePixelRatio: devicePixelRatio),
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  );
}

ResizeImage _resizeImageOf(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  expect(
    image.image,
    isA<ResizeImage>(),
    reason: 'the decode must stay bounded -- that is why the cap exists at all',
  );
  return image.image as ResizeImage;
}

void main() {
  testWidgets('the decode fits the box instead of filling it, so nothing is deformed', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RemoteImage(
          url: '/media/ranks/icons/rank.png',
          width: 56,
          height: 56,
          fallbackBuilder: () => const SizedBox.shrink(),
        ),
      ),
    );

    final resize = _resizeImageOf(tester);
    expect(
      resize.policy,
      ResizeImagePolicy.fit,
      reason: 'ResizeImagePolicy.exact scales to both numbers and squashes a non-square badge',
    );
    expect(resize.allowUpscaling, isFalse, reason: 'a small icon must not be blown up into the box');
  });

  testWidgets('the decode budget follows the box it is drawn in', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RemoteImage(
          url: '/media/ranks/icons/rank.png',
          width: 56,
          height: 56,
          fallbackBuilder: () => const SizedBox.shrink(),
        ),
        devicePixelRatio: 3,
      ),
    );

    final resize = _resizeImageOf(tester);
    expect(resize.width, 168, reason: '56 logical pixels at a device pixel ratio of 3');
    expect(resize.height, 168);
  });

  testWidgets('a cover crop decodes with margin so the cropped axis stays sharp', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RemoteImage(
          url: '/media/avatars/a.jpg',
          width: 100,
          height: 100,
          fit: BoxFit.cover,
          fallbackBuilder: () => const SizedBox.shrink(),
        ),
        devicePixelRatio: 1,
      ),
    );

    final resize = _resizeImageOf(tester);
    // Fitting a cover crop exactly inside the box would leave the cropped
    // axis short of it and force an upscale; the margin avoids that
    // without going back to a deforming two-axis decode.
    expect(resize.policy, ResizeImagePolicy.fit);
    expect(resize.width, greaterThan(100));
    expect(resize.height, greaterThan(100));
  });

  testWidgets('an axis the parent sizes leaves that side of the budget open', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 300,
          child: RemoteImage(
            url: '/media/words/w.png',
            width: double.infinity,
            height: 150,
            fit: BoxFit.cover,
            fallbackBuilder: _empty,
          ),
        ),
      ),
    );

    final resize = _resizeImageOf(tester);
    expect(resize.width, isNull, reason: 'an infinite width is not a budget');
    expect(resize.height, isNotNull);
  });

  testWidgets('an empty url renders the fallback and never builds an Image', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RemoteImage(
          url: '',
          width: 40,
          height: 40,
          fallbackBuilder: () => const Icon(Icons.folder_outlined),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
  });
}

Widget _empty() => const SizedBox.shrink();
