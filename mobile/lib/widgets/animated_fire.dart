import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// The 🔥 that actually burns -- the animated fire emoji from Google's
/// Noto Animated Emoji (CC BY 4.0), the same kind of looping emoji
/// Telegram chats show. Bundled, so it plays offline and instantly.
class AnimatedFire extends StatelessWidget {
  final double size;

  /// False while today's streak day isn't earned yet (no lesson, practice
  /// round or quest finished today): a still, grey, faded flame.
  final bool lit;
  const AnimatedFire({super.key, required this.size, this.lit = true});

  static const _grey = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final fire = SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        'assets/animations/fire.json',
        repeat: true,
        animate: lit,
        fit: BoxFit.contain,
        // A static 🔥 rather than nothing if the file ever fails to load.
        errorBuilder: (_, _, _) => Center(child: Text('🔥', style: TextStyle(fontSize: size * 0.8))),
      ),
    );
    if (lit) return fire;
    return Opacity(opacity: 0.45, child: ColorFiltered(colorFilter: _grey, child: fire));
  }
}
