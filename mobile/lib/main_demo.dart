// Demo build: the same app on made-up data, no server needed. Entry point only for
// `flutter build apk -t lib/main_demo.dart`; the real app (main.dart) does not know about it.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'demo/demo_server.dart';
import 'main.dart' as app;

Future<void> main() async {
  // A signed-in demo account, kept only inside the demo app's own storage.
  await const FlutterSecureStorage().write(key: 'guyo_user_token', value: 'demo');
  await http.runWithClient(app.main, demoClient);
}
