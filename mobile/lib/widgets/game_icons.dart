import 'package:flutter/material.dart';

import 'cosmetic_art.dart';

import '../l10n/l10n.dart';

/// The game's own pictures for the three things people collect. Use these
/// everywhere instead of stock icons or emoji, at any size (also tiny ones).
class DiamondIcon extends StatelessWidget {
  final double size;
  const DiamondIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => _GameIcon('assets/icons/diamond.png', size);
}

/// Season-pass energy (XP): the lightning bolt.
class EnergyIcon extends StatelessWidget {
  final double size;
  const EnergyIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => _GameIcon('assets/icons/energy.png', size);
}

/// Text where ⚡ ⭐ 💎 ❄ 🎁 are drawn as the game's own pictures instead of system emoji.
class IconText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  const IconText(this.text, {super.key, this.style, this.maxLines, this.overflow, this.textAlign});

  static const _marks = {'⚡': 'energy', '⭐': 'points', '💎': 'diamond', '❄': 'freeze', '🎁': 'gift'};

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final size = (base.fontSize ?? 14) * 1.2;
    final spans = <InlineSpan>[];
    final buf = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final name = _marks[ch];
      if (name == null) {
        if (ch != '\uFE0F') buf.write(ch);
        continue;
      }
      if (buf.isNotEmpty) {
        spans.add(TextSpan(text: buf.toString()));
        buf.clear();
      }
      spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: gameAsset(name, size)));
    }
    if (buf.isNotEmpty) spans.add(TextSpan(text: buf.toString()));
    return Text.rich(TextSpan(style: style, children: spans), maxLines: maxLines, overflow: overflow, textAlign: textAlign);
  }
}

/// Rating points: the golden star.
class PointsIcon extends StatelessWidget {
  final double size;
  const PointsIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => _GameIcon('assets/icons/points.png', size);
}

/// The "x2" ticket: doubles the prizes of opened chests while it runs.
class BoosterIcon extends StatelessWidget {
  final double size;

  /// What it doubles: 'chest' (prizes of chests), 'rating' (rating points), 'xp' (pass energy).
  final String kind;
  const BoosterIcon({super.key, this.size = 20, this.kind = 'chest'});

  @override
  Widget build(BuildContext context) => _GameIcon(
        kind == 'rating'
            ? 'assets/icons/booster_x2_rating.png'
            : kind == 'xp'
                ? 'assets/icons/booster_x2_xp.png'
                : 'assets/icons/booster.png',
        size,
      );
}

/// A gift box: a reward is waiting.
class GiftIcon extends StatelessWidget {
  final double size;
  const GiftIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => _GameIcon('assets/icons/gift.png', size);
}

class FreezeIcon extends StatelessWidget {
  final double size;
  const FreezeIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => _GameIcon('assets/icons/freeze.png', size);
}

class MergeIcon extends StatelessWidget {
  final double size;
  const MergeIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => _GameIcon('assets/icons/merge.png', size);
}

/// The picture for a collectible by its short name: diamond, freeze or merge.
Widget gameAsset(String name, double size) {
  if (name.startsWith('chest:')) return ChestImage(name.substring(6), size: size);
  if (name.startsWith('title:')) return TitleRibbon(artKey: name.substring(6), text: '', width: (size * 2.4).clamp(0, 240).toDouble());
  if (name.startsWith('booster:')) return BoosterIcon(size: size, kind: name.substring(8));
  if (name.startsWith('cosmetic:')) return CosmeticImage(name.substring(9), width: size, height: size);
  switch (name) {
    case 'freeze':
      return FreezeIcon(size: size);
    case 'merge':
      return MergeIcon(size: size);
    case 'points':
      return PointsIcon(size: size);
    case 'energy':
      return EnergyIcon(size: size);
    case 'diamond':
      return DiamondIcon(size: size);
    case 'gift':
      return GiftIcon(size: size);
    case 'booster':
      return BoosterIcon(size: size);
    default:
      return DiamondIcon(size: size);
  }
}

/// One of the four chests (wood, silver, purple, gold), closed or open.
class ChestImage extends StatelessWidget {
  final String chestKey;
  final bool open;
  final double size;
  const ChestImage(this.chestKey, {super.key, this.open = false, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final key = const ['wood', 'silver', 'purple', 'gold'].contains(chestKey) ? chestKey : 'wood';
    return _GameIcon('assets/chests/${key}_${open ? 'open' : 'closed'}.png', size);
  }
}

class _GameIcon extends StatelessWidget {
  final String asset;
  final double size;
  const _GameIcon(this.asset, this.size);

  @override
  Widget build(BuildContext context) {
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(32, 512);
    return Image.asset(
      asset,
      width: size,
      height: size,
      cacheWidth: px,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      excludeFromSemantics: true,
    );
  }
}

/// 999 -> "999", 1500 -> "1.5к", 104078 -> "104к", 1250000 -> "1.3 млн",
/// 2400000000 -> "2.4 млрд". Used for diamonds, so a big balance never breaks
/// a layout; rating points are shown in full and do not use this.
String compactNumber(num value) {
  final n = value.round();
  final negative = n < 0;
  final a = n.abs();
  String out;
  if (a < 1000) {
    out = '$a';
  } else if (a < 1000000) {
    out = _scaled(a / 1000, tr('к'));
  } else if (a < 1000000000) {
    out = _scaled(a / 1000000, ' ${tr('млн')}');
  } else {
    out = _scaled(a / 1000000000, ' ${tr('млрд')}');
  }
  return negative ? '-$out' : out;
}

String _scaled(double v, String suffix) {
  // One decimal under 10 ("1.5к"), whole numbers above ("104к"); never "1000к".
  var text = v < 10 ? v.toStringAsFixed(1) : v.floor().toString();
  if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
  if (text == '1000') return '1${suffix.trim().isEmpty ? '' : ''}$suffix';
  return '$text$suffix';
}

/// Decodes an asset at the size it will be drawn, ahead of time, so the first
/// frame that shows it does not stall. Never throws.
void precacheGame(BuildContext context, String asset, double size) {
  final px = (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(32, 512);
  // ignore: unawaited_futures
  precacheImage(ResizeImage(AssetImage(asset), width: px), context).catchError((_) {});
}
