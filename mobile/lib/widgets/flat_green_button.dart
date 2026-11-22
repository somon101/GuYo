import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The flat green button of the owner's pick («Продолжить» on the goal card): a soft green face on a darker
/// edge that sinks when pressed, dark green capitals on it. Used wherever the owner asked for «a button like
/// Продолжить» (the goal card, the gifts). The older glossy [GreenButton] stays where it already is.
class FlatGreenButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;

  /// A fixed width; null takes the whole width of the place (a column) or, in a row, [compact]'s size.
  final double? width;

  /// Smaller (44) for cards and lists; the large one (54) stands alone.
  final bool compact;
  const FlatGreenButton({super.key, required this.label, required this.onTap, this.width, this.compact = true});

  @override
  State<FlatGreenButton> createState() => _FlatGreenButtonState();
}

class _FlatGreenButtonState extends State<FlatGreenButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final face = widget.compact ? 44.0 : 54.0;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          height: face + 4,
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              margin: EdgeInsets.only(top: _down ? 4 : 0),
              height: face,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: FlatGreen.face,
                borderRadius: BorderRadius.circular(widget.compact ? 14 : 16),
                boxShadow: _down ? null : [BoxShadow(color: FlatGreen.edge, offset: const Offset(0, 4))],
              ),
              child: Text(
                widget.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: FlatGreen.text, fontSize: widget.compact ? 14 : 15.5, fontWeight: FontWeight.w800, letterSpacing: 0.4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The soft greens of the flat button, a light and a dark value.
class FlatGreen {
  FlatGreen._();
  static bool get _d => AppColors.dark;
  static Color get face => _d ? const Color(0xFF7BDA5E) : const Color(0xFF62C94A);
  static Color get edge => _d ? const Color(0xFF4FA936) : const Color(0xFF47A72F);
  static Color get text => _d ? const Color(0xFF10300A) : const Color(0xFF123D0A);
}
