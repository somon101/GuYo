import 'package:flutter/material.dart';

import 'game_icons.dart';

/// The small wobbling gift on a card's corner: a reward is waiting. With [count] above one a
/// red dot with the number sits on it.
class GiftBadge extends StatefulWidget {
  final int count;
  final double size;
  const GiftBadge({super.key, this.count = 0, this.size = 40});

  @override
  State<GiftBadge> createState() => _GiftBadgeState();
}

class _GiftBadgeState extends State<GiftBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Transform.rotate(
          angle: (_c.value - 0.5) * 0.24,
          child: Transform.scale(
            scale: 1 + 0.14 * _c.value,
            child: Stack(clipBehavior: Clip.none, children: [
              GiftIcon(size: widget.size),
              if (widget.count > 1)
                Positioned(
                  right: -4,
                  bottom: -2,
                  child: Container(
                    key: const ValueKey('gift-count'),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(9), border: Border.all(color: const Color(0xFF12151F), width: 1.5)),
                    child: Text('${widget.count}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                  ),
                ),
            ]),
          ),
        ),
      );
}
