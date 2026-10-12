import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// The burning 🔥 of the streak. [lit] is false while today's streak day
/// isn't earned yet (no lesson, practice round or quest finished today):
/// then it is a still, grey, faded flame. Switching to lit plays the flame
/// catching fire -- colour floods in with a little jump.
class AnimatedFire extends StatelessWidget {
  final double size;
  final bool lit;
  const AnimatedFire({super.key, required this.size, this.lit = true});

  static List<double> _matrix(double t) {
    // t = 0: greyscale; t = 1: original colours.
    const grey = [0.2126, 0.7152, 0.0722];
    double m(int row, int col) => (row == col ? 1.0 : 0.0) * t + grey[col] * (1 - t);
    return [
      m(0, 0), m(0, 1), m(0, 2), 0, 0,
      m(1, 0), m(1, 1), m(1, 2), 0, 0,
      m(2, 0), m(2, 1), m(2, 2), 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

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
    // Starts at the current state (no animation on first show) and
    // animates only when `lit` changes.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: lit ? 1 : 0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      child: fire,
      builder: (context, t, child) {
        if (t >= 1) return child!;
        final jump = 1 + 0.18 * math.sin(math.pi * t);
        return Opacity(
          opacity: 0.45 + 0.55 * t,
          child: Transform.scale(
            scale: jump,
            child: ColorFiltered(colorFilter: ColorFilter.matrix(_matrix(t)), child: child),
          ),
        );
      },
    );
  }
}
