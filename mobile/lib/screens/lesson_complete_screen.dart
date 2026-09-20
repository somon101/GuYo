import 'dart:math';

import 'package:flutter/material.dart';

/// Shown once, right when a lesson's LAST word crosses the learning
/// threshold and the backend reports `lesson_completed: true` (see the
/// exercise screens' `_RoundCompleteView`, which routes here via
/// `pushReplacement` instead of popping back to the lesson normally). A
/// dedicated, visually rich moment of positive feedback, separate from the
/// ordinary per-round "Правильно: N/M" summary -- adapted to GuYo's own
/// indigo palette (a gradient backdrop, a floating trophy badge, a
/// scattering of small celebratory dots) rather than copying any
/// particular reference design, mascot, or color scheme.
///
/// "Продолжить" pops all the way back past this lesson's own detail screen
/// to the "Уроки" chain root (LessonsScreen, kept alive in HomeScreen's
/// IndexedStack) -- the awaited push in whichever screen opened this one
/// picks up the reload once that happens, so the chain shows the next
/// lesson unlocked with no extra plumbing here.
class LessonCompleteScreen extends StatefulWidget {
  final int lessonNumber;
  const LessonCompleteScreen({super.key, required this.lessonNumber});

  @override
  State<LessonCompleteScreen> createState() => _LessonCompleteScreenState();
}

class _ConfettiSpec {
  final Alignment alignment;
  final Color color;
  final double size;
  final double delay; // 0..1, where in the controller's timeline this pops in
  const _ConfettiSpec(this.alignment, this.color, this.size, this.delay);
}

class _LessonCompleteScreenState extends State<LessonCompleteScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  late final List<_ConfettiSpec> _confetti;

  static const _confettiColors = [
    Colors.amber,
    Colors.pinkAccent,
    Colors.tealAccent,
    Colors.orangeAccent,
    Colors.lightBlueAccent,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _scale = CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.55, curve: Curves.elasticOut));
    _fade = CurvedAnimation(parent: _controller, curve: const Interval(0.15, 0.6, curve: Curves.easeIn));

    final random = Random(widget.lessonNumber);
    _confetti = List.generate(14, (i) {
      final dx = -1.0 + random.nextDouble() * 2.0;
      final dy = -1.0 + random.nextDouble() * 0.9;
      final color = _confettiColors[random.nextInt(_confettiColors.length)];
      final size = 6.0 + random.nextDouble() * 8.0;
      final delay = random.nextDouble() * 0.5;
      return _ConfettiSpec(Alignment(dx, dy), color, size, delay);
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      // The back gesture/button must follow the same "all the way back to
      // the chain" rule as the "Продолжить" button -- never leave the user
      // stranded on the (now-history) lesson detail screen underneath.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).popUntil((route) => route.isFirst);
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.indigo.shade700, Colors.indigo.shade400, scheme.surface],
                    stops: const [0.0, 0.42, 0.85],
                  ),
                ),
              ),
            ),
            for (final spec in _confetti)
              Align(
                alignment: spec.alignment,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final t = Interval(spec.delay, (spec.delay + 0.5).clamp(0.0, 1.0)).transform(_controller.value);
                    return Opacity(
                      opacity: Curves.easeOut.transform(t),
                      child: Transform.scale(scale: Curves.elasticOut.transform(t), child: child),
                    );
                  },
                  child: Container(
                    width: spec.size,
                    height: spec.size,
                    decoration: BoxDecoration(color: spec.color, borderRadius: BorderRadius.circular(spec.size * 0.3)),
                  ),
                ),
              ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: _scale,
                        child: Container(
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD54F), Color(0xFFFFA000)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withValues(alpha: 0.5),
                                blurRadius: 32,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 68),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FadeTransition(
                              opacity: _fade,
                              child: Text(
                                'УРОК ${widget.lessonNumber}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            FadeTransition(
                              opacity: _fade,
                              child: const Text(
                                'Пройден!',
                                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 10),
                            FadeTransition(
                              opacity: _fade,
                              child: const Text(
                                'Все слова этого урока изучены. Отличная работа!',
                                style: TextStyle(color: Colors.black54, fontSize: 15),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                                child: const Text('Продолжить'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
