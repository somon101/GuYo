// Demo build: the same app on made-up data, no server needed. Entry point only for
// `flutter build apk -t lib/main_demo.dart`; the real app (main.dart) does not know about it.
// Sign in with any login and password (demo / demo).
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'demo/demo_server.dart';
import 'main.dart' as app;

Future<void> main() async {
  // Must come first: nothing may talk to the phone before Flutter is bound to it.
  WidgetsFlutterBinding.ensureInitialized();
  await http.runWithClient(app.main, demoClient);
}
