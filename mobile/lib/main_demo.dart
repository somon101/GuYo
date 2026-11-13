// Demo build: the same app on made-up data, no server needed. Entry point only for
// `flutter build apk -t lib/main_demo.dart`; the real app (main.dart) does not know about it.
// Sign in with any login and password (demo / demo).
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'demo/demo_server.dart';
import 'main.dart' as app;

Future<void> main() async {
  // Everything -- including binding Flutter to the phone -- runs inside ONE zone that carries
  // the fake client. Taps and timers come back through the zone the binding was made in, so a
  // binding made outside it would send requests to the real (maybe dead) server and hang.
  await http.runWithClient(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await app.main();
  }, demoClient);
}
