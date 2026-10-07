import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// The 🔥 that actually burns -- the animated fire emoji from Google's
/// Noto Animated Emoji (CC BY 4.0), the same kind of looping emoji
/// Telegram chats show. Bundled, so it plays offline and instantly.
class AnimatedFire extends StatelessWidget {
  final double size;
  const AnimatedFire({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        'assets/animations/fire.json',
        repeat: true,
        fit: BoxFit.contain,
        // A static 🔥 rather than nothing if the file ever fails to load.
        errorBuilder: (_, _, _) => Center(child: Text('🔥', style: TextStyle(fontSize: size * 0.8))),
      ),
    );
  }
}
