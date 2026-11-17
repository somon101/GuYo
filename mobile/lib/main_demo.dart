// Demo build: the same app on made-up data, no server needed. Entry point only for
// `flutter build apk -t lib/main_demo.dart`; the real app (main.dart) does not know about it.
// Sign in with any login and password (demo / demo).
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_hooks.dart';
import 'demo/demo_feed.dart';
import 'demo/demo_results_flow.dart';
import 'l10n/l10n.dart';
import 'demo/demo_server.dart';
import 'demo/demo_state.dart';
import 'main.dart' as app;
import 'screens/lesson_results_screen.dart' show lessonResultsBuilder;

Future<void> main() async {
  // Everything -- including binding Flutter to the phone -- runs inside ONE zone that carries
  // the fake client. Taps and timers come back through the zone the binding was made in, so a
  // binding made outside it would send requests to the real (maybe dead) server and hang.
  await http.runWithClient(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await DemoState.instance.load(); // progress kept between launches
    // The end of a lesson shows the path the owner approved (results, streak, chest of the day).
    lessonResultsBuilder = (lesson, stats) => DemoResultsFlow(lesson: lesson, stats: stats);
    // «Лента» takes the place of «Рейтинг» (the rating opens from its switch), and the profile shows the team.
    AppHooks.ratingTab = (icon: Icons.favorite_rounded, label: tr('Лента'), page: (context, goTo) => DemoFeedTab(goTo: goTo));
    AppHooks.profileExtra = (context) => const DemoMyTeamCard();
    await app.main();
  }, demoClient);
}
