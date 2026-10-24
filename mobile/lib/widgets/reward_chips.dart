import 'package:flutter/material.dart';

import '../models/reward_spec.dart';
import 'game_icons.dart';

/// A compact row of reward pictures with their amounts.
class RewardChips extends StatelessWidget {
  final List<RewardSpec> rewards;
  final Color color;
  final double size;
  const RewardChips({super.key, required this.rewards, this.color = Colors.black87, this.size = 20});

  @override
  Widget build(BuildContext context) {
    if (rewards.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final r in rewards) _chip(r),
    ]);
  }

  Widget _chip(RewardSpec r) {
    final style = TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size * 0.7);
    switch (r.type) {
      case 'chest':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          ChestImage(r.key ?? 'wood', size: size * 1.3),
          if (r.amount > 1) Text('×${r.amount}', style: style),
        ]);
      case 'diamonds':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          DiamondIcon(size: size),
          const SizedBox(width: 3),
          Text(compactNumber(r.amount), style: style),
        ]);
      case 'rating_points':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.star_rounded, size: size, color: const Color(0xFFFFB300)),
          const SizedBox(width: 2),
          Text('${r.amount}', style: style),
        ]);
      default:
        return Text('⚡ ${r.amount} XP', style: style);
    }
  }
}
