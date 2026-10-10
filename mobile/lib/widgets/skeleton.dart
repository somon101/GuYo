import '../l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The app's one loading look: grey blocks in the shape of the screen that
/// is about to appear, under a soft moving highlight -- never a spinner.
///
/// Build a placeholder from [SkeletonBox] / [SkeletonCircle] /
/// [SkeletonLine] inside a [Skeleton], or use one of the ready layouts
/// below ([SkeletonList], [SkeletonDashboard], [SkeletonExercise],
/// [SkeletonForm]). [SkeletonPulse] is the in-progress look for a button,
/// an avatar or the microphone.
class Skeleton extends StatefulWidget {
  final Widget child;
  const Skeleton({super.key, required this.child});

  static Color get bone => AppColors.dark ? const Color(0xFF232739) : AppColors.separator;
  static Color get highlight => AppColors.dark ? const Color(0xFF2F3450) : const Color(0xFFF6F7FC);

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr('Загрузка'),
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          child: widget.child,
          builder: (context, child) => ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              final t = _controller.value * 3 - 1; // sweeps from left of the box to right of it
              return LinearGradient(
                begin: Alignment(t - 1, -0.3),
                end: Alignment(t + 1, 0.3),
                colors: [Skeleton.bone, Skeleton.highlight, Skeleton.bone],
                stops: const [0.35, 0.5, 0.65],
              ).createShader(bounds);
            },
            child: child,
          ),
        ),
      ),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, this.width, required this.height, this.radius = AppShapes.rowRadius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: Skeleton.bone, borderRadius: BorderRadius.circular(radius)),
    );
  }
}

class SkeletonCircle extends StatelessWidget {
  final double size;
  const SkeletonCircle({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Skeleton.bone, shape: BoxShape.circle),
    );
  }
}

class SkeletonLine extends StatelessWidget {
  final double? width;
  final double height;
  const SkeletonLine({super.key, this.width, this.height = 12});

  @override
  Widget build(BuildContext context) => SkeletonBox(width: width, height: height, radius: height / 2);
}

/// Rows of a list: an optional round avatar, a long line and a short one.
class SkeletonList extends StatelessWidget {
  final int rows;
  final bool avatar;
  final EdgeInsets padding;
  const SkeletonList({super.key, this.rows = 8, this.avatar = true, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: rows,
        separatorBuilder: (_, _) => const SizedBox(height: 22),
        itemBuilder: (_, i) => Row(
          children: [
            if (avatar) ...[const SkeletonCircle(size: 48), const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonLine(height: 14),
                  const SizedBox(height: 10),
                  FractionallySizedBox(widthFactor: i.isEven ? 0.55 : 0.4, child: const SkeletonLine(height: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A screen of cards: a wide header card with a row of tiles, then blocks.
class SkeletonDashboard extends StatelessWidget {
  const SkeletonDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SkeletonBox(height: 150, radius: AppShapes.cardRadius),
          const SizedBox(height: 16),
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 110, radius: AppShapes.cardRadius)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 110, radius: AppShapes.cardRadius)),
            ],
          ),
          const SizedBox(height: 16),
          const SkeletonBox(height: 90, radius: AppShapes.cardRadius),
          const SizedBox(height: 16),
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 100, radius: AppShapes.cardRadius)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 100, radius: AppShapes.cardRadius)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 100, radius: AppShapes.cardRadius)),
            ],
          ),
        ],
      ),
    );
  }
}

/// An exercise: the progress header, the word card, and answer buttons.
class SkeletonExercise extends StatelessWidget {
  final int options;
  const SkeletonExercise({super.key, this.options = 2});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.canvas,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Skeleton(
        child: Column(
          children: [
            Row(
              children: const [
                SkeletonLine(width: 70, height: 14),
                Spacer(),
                SkeletonLine(width: 50, height: 14),
              ],
            ),
            const SizedBox(height: 10),
            const SkeletonLine(height: 8),
            const Spacer(),
            const SkeletonBox(height: 220, radius: AppShapes.cardRadius),
            const SizedBox(height: 20),
            for (var i = 0; i < options; i++) ...[
              const SkeletonBox(height: 56, radius: AppShapes.pillRadius),
              const SizedBox(height: 12),
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// A form or a plain page: a title, a couple of lines and field-like blocks.
class SkeletonForm extends StatelessWidget {
  final int fields;
  const SkeletonForm({super.key, this.fields = 5});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: 0.6, child: SkeletonLine(height: 22)),
          const SizedBox(height: 12),
          const SkeletonLine(height: 12),
          const SizedBox(height: 8),
          const FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: 0.7, child: SkeletonLine(height: 12)),
          const SizedBox(height: 24),
          for (var i = 0; i < fields; i++) ...[
            const SkeletonBox(height: 56),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Something whose action is in progress -- a button label, an avatar being
/// replaced, the microphone while it listens -- gently fading in and out,
/// the same calm motion as the skeleton instead of a spinner.
class SkeletonPulse extends StatefulWidget {
  final Widget child;
  const SkeletonPulse({super.key, required this.child});

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller), child: widget.child);
  }
}
