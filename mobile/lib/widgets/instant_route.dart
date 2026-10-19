import 'package:flutter/material.dart';

/// A route with no transition: the screen is simply there, and closing it is
/// just as instant. Used around a lesson (open, results, back), where the
/// slide-in only made the switch feel slow.
Route<T> instantRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, _, __) => builder(context),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}
