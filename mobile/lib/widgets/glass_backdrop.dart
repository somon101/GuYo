import 'dart:ui';

import 'package:flutter/material.dart';

/// A soft, mostly-solid backdrop with a couple of large, blurred colour
/// blobs behind it -- just enough depth to justify a glass card on top
/// without turning the whole screen into stacked panes of glass. Shared by
/// every Practice exercise screen (see BuildPhraseScreen, and any future
/// exercise) so the same visual language doesn't get re-implemented per
/// screen.
class GlassBackdrop extends StatelessWidget {
  final Widget child;
  const GlassBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.indigo.shade50, Colors.white, Colors.white],
              ),
            ),
          ),
        ),
        Positioned(top: -60, right: -40, child: _GlassBlob(color: Colors.indigo.shade100, size: 220)),
        Positioned(bottom: -80, left: -60, child: _GlassBlob(color: Colors.deepPurple.shade50, size: 260)),
        child,
      ],
    );
  }
}

class _GlassBlob extends StatelessWidget {
  final Color color;
  final double size;
  const _GlassBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}
