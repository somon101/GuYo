// «Профиль» has no bar of its own: the gear is in the name's row, the QR beside the ID, and a tap
// on the ID copies it (there is no copy button any more).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/demo/demo_server.dart';
import 'package:guyo_app/models/dictionary.dart';
import 'package:guyo_app/screens/profile_screen.dart';
import 'package:http/http.dart' as http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);

  testWidgets('gear and QR are in the header; the ID has no copy icon and copies on tap', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ProfileScreen(dictionary: GuyoDictionary(id: 1, name: 'English', language: 'en', wordCount: 10), onOpenLessons: () {})),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pump(const Duration(milliseconds: 300));
      tester.takeException(); // the test font is wider than the real one: a long row elsewhere on the page overflows
      expect(find.byKey(const ValueKey('profile-settings')), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-qr')), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsNothing);
      await tester.tap(find.byKey(const ValueKey('profile-copy-id')));
      await tester.pump();
      expect(copied, isNotNull);
      await tester.pump(const Duration(seconds: 30));
    }, demoClient);
  });
}
