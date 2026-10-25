import 'package:flutter/material.dart';

import 'game_icons.dart';

/// A chest picture with its count in a small plate on the bottom-right corner
/// of the chest (about 80% across, 73% down).
class CountedChest extends StatelessWidget {
  final String chestKey;
  final Color color;
  final int count;
  final double size;
  const CountedChest({super.key, required this.chestKey, required this.color, required this.count, this.size = 60});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.none, children: [
          ChestImage(chestKey, size: size),
          Positioned(
            left: size * 0.8,
            top: size * 0.73,
            child: FractionalTranslation(
              translation: const Offset(-0.5, -0.5),
              child: Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF1B1247),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [
                    BoxShadow(color: color, spreadRadius: 2),
                    const BoxShadow(color: Color(0x80000000), blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: Text(
                  '$count',
                  key: ValueKey('count-$chestKey'),
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size >= 56 ? 13 : 11, height: 1),
                ),
              ),
            ),
          ),
        ]),
      );
}

/// The one big green "open" button, like a game's play button.
class GreenButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  const GreenButton({super.key, required this.label, required this.onTap, this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 10)});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF0F6B1D), width: 2),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF9DFF72), Color(0xFF3FD43A), Color(0xFF1EA82C)], stops: [0, 0.48, 1]),
            boxShadow: const [
              BoxShadow(color: Color(0xFF0F6B1D), offset: Offset(0, 4)),
              BoxShadow(color: Color(0x59000000), blurRadius: 12, offset: Offset(0, 8)),
            ],
          ),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 0.6,
              shadows: [Shadow(color: Color(0xFF0F6B1D), offset: Offset(0, 2)), Shadow(color: Color(0x99003C00), blurRadius: 6)],
            ),
          ),
        ),
      ),
    );
  }
}
