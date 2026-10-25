import 'package:flutter/material.dart';

import '../models/reward_spec.dart';
import 'game_icons.dart';

/// Rewards as game "slots": a dark rounded tile with the picture and a small number plate on
/// its corner. No words. One line that scrolls sideways when it does not fit, so a card
/// never grows taller.
class RewardChips extends StatelessWidget {
  final List<RewardSpec> rewards;
  final Color color;
  final double size;
  final bool silver;

  /// [size] is the icon size of the old chips; the slot is a little bigger than it.
  const RewardChips({super.key, required this.rewards, this.color = Colors.black87, this.size = 20, this.silver = false});

  @override
  Widget build(BuildContext context) {
    if (rewards.isEmpty) return const SizedBox.shrink();
    final slot = size + 24;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(right: 8, bottom: 6, top: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final r in rewards) Padding(padding: const EdgeInsets.only(right: 8), child: RewardSlot(reward: r, side: slot, silver: silver)),
      ]),
    );
  }
}

/// One reward in a slot.
class RewardSlot extends StatelessWidget {
  final RewardSpec reward;
  final double side;
  final bool silver;
  const RewardSlot({super.key, required this.reward, this.side = 44, this.silver = false});

  @override
  Widget build(BuildContext context) {
    final frame = silver ? const Color(0xFFC8D2EB) : const Color(0xFFFFD54F);
    final icon = side - 12;
    Widget picture;
    String? plate;
    switch (reward.type) {
      case 'chest':
        picture = ChestImage(reward.key ?? 'wood', size: icon);
        if (reward.amount > 1) plate = '${reward.amount}';
        break;
      case 'diamonds':
        picture = DiamondIcon(size: icon);
        plate = compactNumber(reward.amount);
        break;
      case 'rating_points':
        picture = PointsIcon(size: icon);
        plate = '${reward.amount}';
        break;
      case 'booster':
        picture = BoosterIcon(size: icon);
        plate = boosterShort(reward.amount);
        break;
      default:
        picture = Icon(Icons.bolt_rounded, size: icon, color: const Color(0xFFFFC928));
        plate = '${reward.amount}';
    }
    return SizedBox(
      width: side,
      height: side,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const RadialGradient(center: Alignment(0, -0.3), radius: 0.9, colors: [Color(0x2EFFFFFF), Color(0x8C0A0628)]),
            border: Border.all(color: frame.withValues(alpha: 0.85), width: 2),
            boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 6, offset: Offset(0, 3))],
          ),
          alignment: Alignment.center,
          child: picture,
        ),
        if (plate != null)
          Positioned(
            right: -5,
            bottom: -5,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF1B1247),
                borderRadius: BorderRadius.circular(99),
                boxShadow: [BoxShadow(color: frame.withValues(alpha: 0.85), spreadRadius: 1.5)],
              ),
              child: Text(plate, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, height: 1.2)),
            ),
          ),
      ]),
    );
  }
}

/// "30" minutes -> "30м", 60 -> "1ч", 1440 -> "24ч".
String boosterShort(int minutes) {
  if (minutes >= 60 && minutes % 60 == 0) return '${minutes ~/ 60}ч';
  return '${minutes}м';
}
