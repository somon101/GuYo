import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'remote_image.dart';

/// A leaderboard status emoji: GuYo's own picture (the same on every
/// phone, unlike a system emoji), on a small white disc so it reads on
/// any avatar.
class StatusEmojiBadge extends StatelessWidget {
  final String url;
  final double size;

  const StatusEmojiBadge({super.key, required this.url, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.18), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      // Keyed by the picture, so a rebuilt list can never show one
      // person's emoji on another's avatar.
      child: RemoteImage(key: ValueKey(url), url: url, width: size, height: size, fallbackBuilder: () => const SizedBox.shrink()),
    );
  }
}

/// [child] (an avatar) with the status emoji pinned to its bottom-right
/// corner -- the whole status, kept to the size of the avatar itself.
class AvatarWithStatus extends StatelessWidget {
  final Widget child;
  final String? emojiUrl;
  final double badgeSize;

  const AvatarWithStatus({super.key, required this.child, required this.emojiUrl, this.badgeSize = 20});

  @override
  Widget build(BuildContext context) {
    final url = emojiUrl;
    if (url == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(right: -badgeSize * 0.3, bottom: -badgeSize * 0.25, child: StatusEmojiBadge(url: url, size: badgeSize)),
      ],
    );
  }
}

/// Tapping [child] shows the person's status in a small bubble above it
/// (the emoji and the phrase) for a few seconds. Without a status it's
/// just [child].
class StatusBubble extends StatefulWidget {
  final String? emojiUrl;
  final String? text;
  final Widget child;

  const StatusBubble({super.key, required this.emojiUrl, required this.text, required this.child});

  @override
  State<StatusBubble> createState() => _StatusBubbleState();
}

class _StatusBubbleState extends State<StatusBubble> with SingleTickerProviderStateMixin {
  OverlayEntry? _entry;
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  int _shown = 0;

  bool get _hasStatus => widget.emojiUrl != null || widget.text != null;

  void _show() {
    _hide();
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return;
    // Where the row/place is, in the overlay's coordinates.
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final screen = overlayBox.size;
    const margin = 12.0;
    final centerX = topLeft.dx + box.size.width / 2;
    final bottom = screen.height - topLeft.dy + 2;
    // Align maps -1..1 across the free width, so the bubble sits over the
    // person but never past the screen edge.
    final usable = screen.width - margin * 2;
    final ax = ((centerX - margin) / usable * 2 - 1).clamp(-1.0, 1.0);
    _entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: FadeTransition(
          opacity: _anim,
          child: Stack(
            children: [
              Positioned(
                left: margin,
                right: margin,
                bottom: bottom + 7,
                child: Align(
                  alignment: Alignment(ax, 1),
                  child: ScaleTransition(
                    scale: Tween(begin: .92, end: 1.0).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutBack)),
                    child: _Bubble(emojiUrl: widget.emojiUrl, text: widget.text),
                  ),
                ),
              ),
              Positioned(
                left: centerX - 8,
                bottom: bottom,
                child: CustomPaint(size: const Size(16, 8), painter: _TailPainter()),
              ),
            ],
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
    _anim.forward(from: 0);
    final token = ++_shown;
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && token == _shown) _anim.reverse().then((_) => _hide());
    });
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hide();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasStatus) return widget.child;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: _show, child: widget.child);
  }
}

class _Bubble extends StatelessWidget {
  final String? emojiUrl;
  final String? text;
  const _Bubble({required this.emojiUrl, required this.text});

  @override
  Widget build(BuildContext context) {
    final url = emojiUrl;
    final phrase = text;
    return Material(
      color: AppColors.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(18),
      shadowColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.16), blurRadius: 18, offset: const Offset(0, 6))],
          color: AppColors.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (url != null) RemoteImage(key: ValueKey(url), url: url, width: 28, height: 28, fallbackBuilder: () => const SizedBox(width: 28)),
            if (url != null && phrase != null) const SizedBox(width: 8),
            if (phrase != null)
              Flexible(
                child: Text(
                  phrase,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark, decoration: TextDecoration.none),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The small hint next to a name that this person wrote something: tap
/// the row to read it.
class StatusPhraseHint extends StatelessWidget {
  const StatusPhraseHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 6),
      child: Icon(Icons.chat_bubble_rounded, size: 13, color: AppColors.muted),
    );
  }
}
