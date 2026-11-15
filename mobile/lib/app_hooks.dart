import 'package:flutter/widgets.dart';

/// Places a build may fill before the app starts (the demo build does, see main_demo.dart). Left
/// empty, the app is exactly as it always was: nothing here has a behaviour of its own.
class AppHooks {
  AppHooks._();

  /// Takes the place of the «Рейтинг» tab of the bottom bar: its icon, its name and its page.
  /// [page] gets a way to switch tabs (1 is «Уроки»).
  static ({IconData icon, String label, Widget Function(BuildContext context, void Function(int tab) goTo) page})? ratingTab;

  /// One more block on the profile page, right under the header with the numbers.
  static Widget Function(BuildContext context)? profileExtra;
}
