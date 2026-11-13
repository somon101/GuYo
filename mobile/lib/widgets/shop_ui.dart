import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'game_icons.dart';

/// Pieces of the «Магазин» screen: the balance header, the bright product
/// cards with glossy art and golden price buttons.

/// Small four-point sparkles scattered over a surface.
class Sparkles extends CustomPainter {
  final Color color;
  final int seed;
  const Sparkles(this.color, [this.seed = 3]);

  @override
  void paint(Canvas c, Size s) {
    final rnd = math.Random(seed);
    for (var i = 0; i < 9; i++) {
      final p = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
      final r = 2.5 + rnd.nextDouble() * 4.5;
      final path = Path()
        ..moveTo(p.dx, p.dy - r)
        ..quadraticBezierTo(p.dx, p.dy, p.dx + r, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + r)
        ..quadraticBezierTo(p.dx, p.dy, p.dx - r, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - r);
      c.drawPath(path, Paint()..color = color.withValues(alpha: 0.35 + rnd.nextDouble() * 0.45));
    }
  }

  @override
  bool shouldRepaint(Sparkles old) => old.color != color || old.seed != seed;
}

/// Just the icon, scaled to fill a square of [size] (no ball behind it).
class Gem extends StatelessWidget {
  final List<Color> colors;
  final Widget child;
  final double size;
  const Gem({super.key, required this.colors, required this.child, this.size = 76});

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: FittedBox(child: child));
}

/// The art for one shop product, chosen by its type and quantity.
Widget productArt(String itemType, int quantity) {
  if (itemType == 'streak_merge') {
    return const Gem(
      size: 84,
      colors: [Color(0xFFFFC46B), Color(0xFFE5375F)],
      child: MergeIcon(size: 84),
    );
  }
  const flake = FreezeIcon(size: 84);
  if (quantity <= 1) {
    return const Gem(size: 84, colors: [Color(0xFF8EE3FF), Color(0xFF2E6BFF)], child: flake);
  }
  return SizedBox(
    width: 100,
    height: 84,
    child: Stack(alignment: Alignment.center, children: [
      const Positioned(
        left: 0,
        top: 16,
        child: Gem(size: 46, colors: [Color(0xFFC3C9FF), Color(0xFF6A6BFF)], child: FreezeIcon(size: 46)),
      ),
      const Positioned(
        right: 0,
        top: 16,
        child: Gem(size: 46, colors: [Color(0xFFC3C9FF), Color(0xFF6A6BFF)], child: FreezeIcon(size: 46)),
      ),
      const Gem(size: 72, colors: [Color(0xFFA9B1FF), Color(0xFF4B3FE0)], child: FreezeIcon(size: 72)),
      Positioned(
        right: 6,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFFFD54F), borderRadius: BorderRadius.circular(10)),
          child: Text('×$quantity', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF5A3A00))),
        ),
      ),
    ]),
  );
}

/// Card colours per product type.
List<Color> productColors(String itemType, int quantity) {
  if (itemType == 'streak_merge') return const [Color(0xFFFF9A4D), Color(0xFFE63E78)];
  if (quantity > 1) return const [Color(0xFF8F7BFF), Color(0xFF5B2EE0)];
  return const [Color(0xFF4FC3FF), Color(0xFF2F6BFF)];
}

class PriceButton extends StatelessWidget {
  final int price;
  final bool enabled;
  final VoidCallback? onTap;
  const PriceButton({super.key, required this.price, this.enabled = true, this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Ink(
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: enabled ? const [Color(0xFFFFE17A), Color(0xFFFFB02E)] : const [Color(0xFFE9E7F2), Color(0xFFD6D3E6)],
              ),
              boxShadow: enabled
                  ? [BoxShadow(color: const Color(0xFFFFB02E).withValues(alpha: 0.45), blurRadius: 10, offset: const Offset(0, 4))]
                  : null,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Opacity(opacity: enabled ? 1 : 0.5, child: const DiamondIcon(size: 22)),
              const SizedBox(width: 6),
              Text(compactNumber(price), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: enabled ? const Color(0xFF4A2D00) : const Color(0xFF8C89A6))),
            ]),
          ),
        ),
      );
}

class ShopCard extends StatelessWidget {
  final String name;
  final String description;
  final String itemType;
  final int quantity;
  final int price;
  final bool affordable;
  final String? tag;
  final VoidCallback? onBuy;
  const ShopCard({
    super.key,
    required this.name,
    required this.description,
    required this.itemType,
    required this.quantity,
    required this.price,
    this.affordable = true,
    this.tag,
    this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final colors = productColors(itemType, quantity);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(children: [
        SizedBox(
          height: 88,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(child: CustomPaint(painter: Sparkles(Colors.white, name.length + 5))),
            productArt(itemType, quantity),
            if (tag != null)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFFFFD54F), borderRadius: BorderRadius.circular(10)),
                  child: Text(tag!, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFF5A3A00))),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Text(name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 15.5)),
        const SizedBox(height: 2),
        Expanded(
          child: Text(
            description,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.88)),
          ),
        ),
        PriceButton(price: price, enabled: affordable, onTap: onBuy),
      ]),
    );
  }
}

/// The balance card at the top (new style): diamonds, and the freezes and merges held.
class ShopHeader extends StatelessWidget {
  final int diamonds;
  final int freezes;
  final int merges;
  const ShopHeader({super.key, required this.diamonds, required this.freezes, required this.merges});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(26)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Ваши бриллианты'), style: TextStyle(color: AppColors.secondaryText, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(children: [
                  const DiamondIcon(size: 30),
                  const SizedBox(width: 8),
                  Text(compactNumber(diamonds), key: const ValueKey('shop-balance'), style: TextStyle(color: AppColors.primaryDark, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.1)),
                ]),
              ),
            ]),
          ),
          _HeldChip(icon: const FreezeIcon(size: 22), count: freezes),
          const SizedBox(width: 8),
          _HeldChip(icon: const MergeIcon(size: 22), count: merges),
        ]),
      );
}

class _HeldChip extends StatelessWidget {
  final Widget icon;
  final int count;
  const _HeldChip({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          icon,
          const SizedBox(width: 5),
          Text('$count', style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800)),
        ]),
      );
}

/// One pack in a shop row: the picture, «×N» and the price. Dimmed when it can't be afforded.
class ShopPack extends StatelessWidget {
  final String itemType;
  final int quantity;
  final int price;
  final bool affordable;
  final String? tag;
  final VoidCallback onTap;
  const ShopPack({super.key, required this.itemType, required this.quantity, required this.price, required this.affordable, required this.onTap, this.tag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 10),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            itemType == 'streak_merge' ? const MergeIcon(size: 48) : const FreezeIcon(size: 48),
            const SizedBox(height: 6),
            Text('×$quantity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.primaryDark)),
            const SizedBox(height: 6),
            Opacity(
              opacity: affordable ? 1 : 0.45,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(99)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const DiamondIcon(size: 16),
                    const SizedBox(width: 5),
                    Text(compactNumber(price), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
        if (tag != null)
          Positioned(
            top: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99)),
              child: Text(tag!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ),
      ]),
    );
  }
}
