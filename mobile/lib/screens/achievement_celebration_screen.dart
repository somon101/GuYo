import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/achievement_icon.dart';
import '../widgets/rank_icon.dart';

/// Takes the achievements this account has earned but has never been shown,
/// and marks them shown.
///
/// The server keeps that record, so each achievement is celebrated exactly
/// once per account -- logging out and in, or another phone, never brings it
/// back. Marked BEFORE anything is displayed: a celebration cut short (the app
/// closed, a phone call) still counts as shown rather than popping up again and
/// again.
///
/// Separate from the showing itself ([AchievementCelebrationScreen]) because
/// the caller wants to fetch EARLY and show LATER: the results screen asks for
/// these the moment it opens, so tapping «Далее» can present them instantly
/// instead of waiting on the network.
Future<List<UserAchievement>> takeNewAchievements() async {
  final List<UserAchievement> fresh;
  try {
    fresh = await ApiClient.instance.fetchNewAchievements();
  } catch (_) {
    return const [];
  }
  if (fresh.isEmpty) return const [];
  try {
    await ApiClient.instance.markAchievementsSeen([for (final a in fresh) a.id]);
  } catch (_) {
    return const [];
  }
  return fresh;
}

/// How many taps it takes to crack the geode open -- the same four the
/// reference animation asks for: one to learn the gesture, three to watch the
/// glass come apart.
const int _kTapsToBreak = 4;

/// The geode and every crack in it are drawn in these 200 units (traced from
/// the reference), scaled to whatever size the flower ends up on screen.
const double _kGeode = 200;
const Offset _kGeodeCenter = Offset(100, 100);
const double _kPanelRadius = 45;

/// How far a panel flies when the geode gives way, in the same units.
const double _kPanelFlight = 100;

/// When, in the break timeline, the reward itself starts to arrive: right
/// after the flash, while the glass is still in the air.
const double _kRewardAt = 0.18;

/// The stone the geode is made of: a cold grey glass, top-lit. Deliberately
/// the same in both themes -- rock does not turn white in daylight, and the
/// panels only ever read as the shell the badge is locked in.
const Color _kStoneTop = Color(0xFF6A6A76);
const Color _kStoneMid = Color(0xFF4A4A56);
const Color _kStoneDeep = Color(0xFF2E2E3A);
const Color _kStoneDark = Color(0xFF1A1A24);
const Color _kStoneEdge = Color(0xFF151621);
const Color _kCrackLine = Color(0xFF0A0A14);

/// One crack drawn on a panel: a polyline in the geode's own units, its two
/// stroke widths (the dark cut itself and the glowing edge on top of it), and
/// which tap reveals it.
class _Crack {
  final int level;
  final List<Offset> points;
  final double base;
  final double edge;
  const _Crack(this.level, this.points, this.base, this.edge);
}

/// One of the four glass panels: a circle around the middle carrying its own
/// cracks. Together they make the flower the badge sits behind.
class _Panel {
  final Offset center;
  final List<_Crack> cracks;
  const _Panel(this.center, this.cracks);
}

const List<_Panel> _panels = [
  // Top.
  _Panel(Offset(100, 68), [
    _Crack(1, [Offset(90, 50), Offset(96, 58), Offset(92, 66)], 1.8, 3),
    _Crack(2, [Offset(82, 40), Offset(90, 50), Offset(96, 58), Offset(100, 70), Offset(96, 82)], 1.8, 3),
    _Crack(2, [Offset(96, 58), Offset(110, 54), Offset(120, 58)], 1.5, 2.5),
    _Crack(3, [Offset(92, 66), Offset(84, 74), Offset(74, 78)], 1.5, 2.5),
    _Crack(3, [Offset(100, 70), Offset(112, 78), Offset(118, 90)], 1.5, 2.5),
    _Crack(3, [Offset(74, 78), Offset(68, 88)], 1.2, 2),
  ]),
  // Right.
  _Panel(Offset(132, 100), [
    _Crack(1, [Offset(118, 90), Offset(126, 96), Offset(122, 106)], 1.8, 3),
    _Crack(2, [Offset(110, 82), Offset(118, 90), Offset(126, 96), Offset(140, 98)], 1.8, 3),
    _Crack(2, [Offset(126, 96), Offset(130, 112), Offset(126, 124)], 1.5, 2.5),
    _Crack(3, [Offset(122, 106), Offset(112, 114), Offset(108, 126)], 1.5, 2.5),
    _Crack(3, [Offset(140, 98), Offset(152, 104), Offset(158, 114)], 1.5, 2.5),
    _Crack(3, [Offset(130, 112), Offset(142, 118)], 1.2, 2),
  ]),
  // Bottom.
  _Panel(Offset(100, 132), [
    _Crack(1, [Offset(96, 118), Offset(100, 126), Offset(94, 136)], 1.8, 3),
    _Crack(2, [Offset(100, 114), Offset(100, 126), Offset(94, 136), Offset(88, 150)], 1.8, 3),
    _Crack(2, [Offset(100, 126), Offset(114, 130), Offset(122, 140)], 1.5, 2.5),
    _Crack(3, [Offset(94, 136), Offset(82, 142), Offset(76, 154)], 1.5, 2.5),
    _Crack(3, [Offset(88, 150), Offset(96, 158)], 1.5, 2.5),
    _Crack(3, [Offset(122, 140), Offset(134, 144)], 1.2, 2),
  ]),
  // Left.
  _Panel(Offset(68, 100), [
    _Crack(1, [Offset(56, 90), Offset(62, 96), Offset(58, 106)], 1.8, 3),
    _Crack(2, [Offset(48, 80), Offset(56, 90), Offset(62, 96), Offset(74, 100)], 1.8, 3),
    _Crack(2, [Offset(62, 96), Offset(58, 112), Offset(52, 122)], 1.5, 2.5),
    _Crack(3, [Offset(58, 106), Offset(44, 112), Offset(38, 122)], 1.5, 2.5),
    _Crack(3, [Offset(74, 100), Offset(82, 92)], 1.5, 2.5),
    _Crack(3, [Offset(48, 80), Offset(42, 70)], 1.2, 2),
  ]),
];

/// A speck thrown by the burst: it starts at the geode's heart and flies
/// outward, glowing, shrinking and fading -- all of it in the geode's units,
/// so the whole effect keeps its proportions on any screen.
class _Spark {
  final Offset dir;
  final double dist;
  final double size;
  final double spin;
  final double delay;
  final double span;
  final bool round;
  final Color color;
  const _Spark({
    required this.dir,
    required this.dist,
    required this.size,
    required this.spin,
    required this.delay,
    required this.span,
    required this.round,
    required this.color,
  });
}

/// A piece of the glass itself, thrown from the panel it just left.
class _Shard {
  final Offset origin;
  final Offset dir;
  final double dist;
  final double size;
  final double spin;
  final double delay;
  final double span;
  final int shape;
  const _Shard({
    required this.origin,
    required this.dir,
    required this.dist,
    required this.size,
    required this.spin,
    required this.delay,
    required this.span,
    required this.shape,
  });
}

/// One strip of the gold rain that falls once the badge is out.
class _ConfettiPiece {
  final double x;
  final double size;
  final double spin;
  final double delay;
  final double span;
  final Color color;
  const _ConfettiPiece({
    required this.x,
    required this.size,
    required this.spin,
    required this.delay,
    required this.span,
    required this.color,
  });
}

/// The three glass shapes a shard is cut into (unit coordinates, scaled by the
/// shard's own size).
const List<List<Offset>> _shardShapes = [
  [Offset(0.5, 0), Offset(1, 0.5), Offset(0.5, 1), Offset(0, 0.5)],
  [Offset(0, 0), Offset(1, 0.2), Offset(0.8, 1), Offset(0.2, 0.8)],
  [Offset(0.3, 0), Offset(1, 0.3), Offset(0.7, 1), Offset(0, 0.7)],
];

/// The burst's own palette, the reference's: white hot, the achievement's
/// colour twice (light and deep), then the app's gold. Every achievement
/// therefore bursts in its own colour and still shares the reward accent.
const List<Color> _kGold = [Color(0xFFFFD46B), Color(0xFFFFF0B0)];
const List<Color> _kConfettiColors = [Color(0xFFFFC84A), Color(0xFFFFF0A5), Color(0xFF8D65FF), Color(0xFFDCCBFF)];

/// The "achievement unlocked" celebration, played as something physical rather
/// than a card that simply appears: the badge arrives shut inside a geode of
/// four glass panels, the player taps it open -- four taps, each cracking the
/// glass further and driving more light out of the seams -- and only when it
/// gives way does the reward land: flash, shockwave, flying shards, gold rain,
/// and the badge springing into place with its name and description.
///
/// Every effect is a slice of ONE timeline ([_break]) instead of a pile of
/// timers, so the sequence cannot drift out of order, and the reward can never
/// arrive before the glass has flown. The achievement was already recorded as
/// seen by [takeNewAchievements], so a celebration interrupted half-way is
/// never replayed -- which is why skipping it is safe and always available.
///
/// Several achievements earned at once are shown one after another in the same
/// screen: the button becomes «Следующее» and the page only closes after the
/// last one, so nothing is skipped.
class AchievementCelebrationScreen extends StatefulWidget {
  final List<UserAchievement> achievements;

  const AchievementCelebrationScreen({super.key, required this.achievements});

  @override
  State<AchievementCelebrationScreen> createState() => _AchievementCelebrationScreenState();
}

class _AchievementCelebrationScreenState extends State<AchievementCelebrationScreen>
    with TickerProviderStateMixin {
  /// The whole story in one timeline: the flash (0..0.18), the glass and the
  /// pieces flying (0..0.75), and the reward arriving in steps behind them
  /// (icon 0.18, pill 0.5, title 0.62, description 0.72, button 0.82).
  late final AnimationController _break = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  /// The newest layer of cracks drawing itself across the glass, one tap long.
  late final AnimationController _crack = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..value = 1;

  /// The flinch of the glass under the finger, restarted on every tap.
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  /// The gold rain, once, after the badge is out.
  late final AnimationController _confetti = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  /// The light breathing behind the geode and then behind the badge -- the one
  /// thing that keeps moving while the screen is open.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  late final Listenable _timeline = Listenable.merge([_break, _pulse, _confetti, _crack, _shake]);

  /// Which achievement of the batch is on screen, and how many taps its geode
  /// has taken. Both reset for the next one.
  int _index = 0;
  int _taps = 0;
  bool _rainStarted = false;

  /// Whether the device asks for as little movement as possible, read once per
  /// dependency change rather than inside the timeline's own callbacks. The
  /// gesture stays -- a tap still has to be given -- but the fireworks do not:
  /// the geode opens and the reward is simply there.
  bool _calm = false;

  /// The burst's pieces, rolled once per achievement from its own id: the same
  /// achievement always breaks the same way, and nothing is re-randomised on
  /// every rebuild.
  late List<_Spark> _sparks;
  late List<_Shard> _shards;
  late List<_ConfettiPiece> _rain;

  // The reward's own entrance, all slices of the same timeline.
  late final Animation<double> _crestFade = _at(_kRewardAt, _kRewardAt + 0.10);
  late final Animation<double> _crestScale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.45, end: 1.08).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 28),
    TweenSequenceItem(tween: Tween(begin: 1.08, end: 0.98).chain(CurveTween(curve: Curves.easeInOut)), weight: 24),
    TweenSequenceItem(tween: Tween(begin: 0.98, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 48),
  ]).animate(CurvedAnimation(parent: _break, curve: const Interval(_kRewardAt, 0.52)));
  late final Animation<double> _crestTurn = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: -8.0, end: 3.0).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 28),
    TweenSequenceItem(tween: Tween(begin: 3.0, end: -1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 24),
    TweenSequenceItem(tween: Tween(begin: -1.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)), weight: 48),
  ]).animate(CurvedAnimation(parent: _break, curve: const Interval(_kRewardAt, 0.52)));
  late final Animation<double> _pill = _at(0.50, 0.72);
  late final Animation<double> _title = _at(0.62, 0.84);
  late final Animation<double> _desc = _at(0.72, 0.94);
  late final Animation<double> _cta = _at(0.82, 1.0);

  Animation<double> _at(double begin, double end) => CurvedAnimation(
        parent: _break,
        curve: Interval(begin, end.clamp(0.0, 1.0), curve: Curves.easeOutCubic),
      );

  @override
  void initState() {
    super.initState();
    if (widget.achievements.isEmpty) {
      // The caller only ever sends achievements it has just taken, but a race
      // could still hand us an empty list: leave rather than show a blank
      // screen with a button that does nothing.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    } else {
      _rollPieces();
    }
    // The gold rain is part of the same break, so it is started by the
    // timeline itself rather than by a timer of its own.
    _break.addListener(() {
      if (_rainStarted || _calm) return;
      if (_break.value >= 0.6) {
        _rainStarted = true;
        _confetti.forward(from: 0);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void dispose() {
    _break.dispose();
    _crack.dispose();
    _shake.dispose();
    _confetti.dispose();
    _pulse.dispose();
    super.dispose();
  }

  UserAchievement get _current => widget.achievements[_index];
  bool get _hasMore => _index < widget.achievements.length - 1;
  bool get _broken => _taps >= _kTapsToBreak;

  void _rollPieces() {
    final rnd = math.Random(_current.id);
    final color = parseHexColor(_current.color);
    final palette = <Color>[
      Colors.white,
      Color.lerp(color, Colors.white, 0.35)!,
      color,
      ..._kGold,
    ];

    _sparks = List.generate(45, (i) {
      final angle = (math.pi * 2 * i) / 45 + (rnd.nextDouble() - 0.5) * 0.8;
      return _Spark(
        dir: Offset(math.cos(angle), math.sin(angle)),
        dist: 70 + rnd.nextDouble() * 150,
        size: 2 + rnd.nextDouble() * 4,
        spin: rnd.nextDouble() * 900 - 450,
        delay: rnd.nextDouble() * 0.06,
        span: 0.28 + rnd.nextDouble() * 0.30,
        round: rnd.nextBool(),
        color: palette[rnd.nextInt(palette.length)],
      );
    });

    _shards = <_Shard>[];
    for (final panel in _panels) {
      for (var i = 0; i < 10; i++) {
        final angle = (math.pi * 2 * i) / 10 + (rnd.nextDouble() - 0.5) * 0.8;
        _shards.add(_Shard(
          origin: panel.center,
          dir: Offset(math.cos(angle), math.sin(angle)),
          dist: 80 + rnd.nextDouble() * 120,
          size: 8 + rnd.nextDouble() * 12,
          spin: rnd.nextDouble() * 1440 - 720,
          delay: rnd.nextDouble() * 0.06,
          span: 0.37 + rnd.nextDouble() * 0.31,
          shape: rnd.nextInt(_shardShapes.length),
        ));
      }
    }

    _rain = List.generate(24, (_) {
      return _ConfettiPiece(
        x: rnd.nextDouble(),
        size: 4 + rnd.nextDouble() * 6,
        spin: rnd.nextDouble() * 900 - 450,
        delay: rnd.nextDouble() * 0.14,
        span: 0.60 + rnd.nextDouble() * 0.40,
        color: _kConfettiColors[rnd.nextInt(_kConfettiColors.length)],
      );
    });
  }

  void _onTap() {
    if (_broken || _break.isAnimating || _break.isCompleted) return;
    setState(() => _taps++);
    if (!_calm) {
      _shake.forward(from: 0);
      _crack.forward(from: 0);
    }
    if (_taps >= _kTapsToBreak) _giveWay();
  }

  /// The glass loses: the whole sequence runs from here.
  void _giveWay() {
    if (_calm) {
      // Nothing to watch, so nothing is animated -- straight to the reward.
      _break.value = 1;
      return;
    }
    _shake.reset();
    _break.forward(from: 0);
  }

  /// Skips the cracking, not the celebration.
  void _skip() {
    if (_broken) return;
    setState(() => _taps = _kTapsToBreak);
    _giveWay();
  }

  void _next() {
    if (!_hasMore) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _index++;
      _taps = 0;
      _rainStarted = false;
      _rollPieces();
    });
    _break.reset();
    _confetti.reset();
    _crack.value = 1;
    _shake.reset();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.achievements.isEmpty) return const Scaffold();

    final achievement = _current;
    final color = parseHexColor(achievement.color);
    final dark = AppColors.dark;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _timeline,
          builder: (context, _) {
            final t = _break.value;
            // The whole screen takes the hit when the glass gives way, so the
            // burst is felt and not only seen.
            final hit = (t / 0.13).clamp(0.0, 1.0);
            final shakeDx = hit >= 1 ? 0.0 : math.sin(hit * math.pi * 2) * 4 * (1 - hit);
            final shakeDy = hit >= 1 ? 0.0 : math.cos(hit * math.pi * 2) * 3 * (1 - hit);

            return LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                // Both the geode and, later, the badge sit on this one point:
                // the break then reads as the glass giving way AROUND the
                // badge, not as two unrelated screens.
                final center = Offset(size.width / 2, size.height * 0.34);
                final geodeSize = math.min(size.width * 0.62, 236.0);
                final geodeBox = geodeSize * 1.7;
                final unit = geodeSize / _kGeode;
                final crestSize = math.min(size.width * 0.46, 176.0);

                return Transform.translate(
                  offset: Offset(shakeDx, shakeDy),
                  child: Stack(
                    children: [
                      Positioned.fill(child: _Backdrop(center: center, dark: dark, calm: _calm)),

                      // The pieces of the burst: sparks, shards and the
                      // shockwave. Drawn over the whole screen, because they
                      // are supposed to fly well past the geode's own box.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _BurstFxPainter(
                              sparks: _sparks,
                              shards: _shards,
                              center: center,
                              unit: unit,
                              t: t,
                              color: color,
                              calm: _calm,
                            ),
                          ),
                        ),
                      ),

                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _RainPainter(
                              pieces: _rain,
                              t: _confetti.value,
                              dark: dark,
                              calm: _calm,
                            ),
                          ),
                        ),
                      ),

                      // The geode: glass, cracks, the badge locked inside it
                      // (dimmed, its own art) and the light coming through.
                      Positioned(
                        left: center.dx - geodeBox / 2,
                        top: center.dy - geodeBox / 2,
                        width: geodeBox,
                        height: geodeBox,
                        child: IgnorePointer(
                          ignoring: _broken,
                          child: GestureDetector(
                            key: const ValueKey('achievement-geode'),
                            behavior: HitTestBehavior.opaque,
                            onTap: _onTap,
                            child: Opacity(
                              opacity: (1 - (t / 0.22).clamp(0.0, 1.0)),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _GeodePainter(
                                        taps: _taps,
                                        crackT: _crack.value,
                                        shakeT: _shake.value,
                                        pulse: _pulse.value,
                                        burst: t,
                                        color: color,
                                        extent: geodeSize,
                                      ),
                                    ),
                                  ),
                                  Center(
                                    child: AchievementIcon(
                                      achievement: achievement,
                                      dimmed: true,
                                      size: geodeSize * 0.34,
                                    ),
                                  ),
                                  // The hint lives INSIDE the tap target, so a
                                  // player who reads it can act on it right
                                  // there instead of hunting for the glass.
                                  Positioned(
                                    top: geodeBox / 2 + geodeSize * 0.5 + 22,
                                    left: -60,
                                    right: -60,
                                    child: Opacity(
                                      opacity: (1 - (t / 0.1).clamp(0.0, 1.0)),
                                      child: Text(
                                        _hintFor(_taps),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.secondaryText,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Leaving early is always allowed: the achievement is
                      // already recorded as seen, so nothing is lost by it.
                      Positioned(
                        top: 0,
                        right: 4,
                        child: IgnorePointer(
                          ignoring: _broken,
                          child: Opacity(
                            opacity: (1 - (t / 0.12).clamp(0.0, 1.0)),
                            child: TextButton(
                              key: const ValueKey('achievement-celebration-skip'),
                              onPressed: _skip,
                              child: Text(
                                tr('Пропустить'),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // The flash, under the reward: it belongs to the moment
                      // the glass breaks, not to the reward itself.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Colors.white.withValues(alpha: _flashAt(t) * (dark ? 0.72 : 0.62)),
                          ),
                        ),
                      ),

                      Positioned.fill(
                        child: _reward(achievement, color, size, center, crestSize, t),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _reward(
    UserAchievement achievement,
    Color color,
    Size size,
    Offset center,
    double crestSize,
    double t,
  ) {
    final crestBox = crestSize * 1.7;
    // The button's own ink. [AppColors.primary] is a deep indigo in the light
    // theme and a light periwinkle in the dark one, so white would be unreadable
    // there. Set on the label and the icon by hand rather than left to the
    // button style: while the reward is arriving the button is deliberately
    // disabled, and a style-driven colour would leave it looking washed out
    // even after it becomes pressable.
    final ink = AppColors.dark ? const Color(0xFF11131C) : Colors.white;
    return Stack(
      children: [
        Positioned(
          left: center.dx - crestBox / 2,
          top: center.dy - crestBox / 2,
          width: crestBox,
          height: crestBox,
          child: IgnorePointer(
            child: Opacity(
              opacity: _crestFade.value,
              child: Transform.rotate(
                angle: _crestTurn.value * math.pi / 180,
                child: Transform.scale(
                  scale: _crestScale.value,
                  child: _Crest(achievement: achievement, color: color, size: crestSize, breath: _pulse.value),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: size.height * 0.50,
          left: 16,
          right: 16,
          bottom: 92,
          child: IgnorePointer(
            ignoring: t < 0.84,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Line(
                    animation: _pill,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.violetSurface,
                        borderRadius: BorderRadius.circular(AppShapes.pillRadius),
                        border: Border.all(color: color.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, size: 15, color: color),
                          const SizedBox(width: 6),
                          Text(
                            tr('Достижение получено!'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _Line(
                    animation: _title,
                    child: Text(
                      achievement.title ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: AppColors.primaryDark,
                        shadows: [
                          Shadow(color: color.withValues(alpha: 0.45), blurRadius: 30),
                        ],
                      ),
                    ),
                  ),
                  if ((achievement.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _Line(
                      animation: _desc,
                      child: Text(
                        achievement.description!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, height: 1.45, color: AppColors.secondaryText),
                      ),
                    ),
                  ],
                  if (widget.achievements.length > 1) ...[
                    const SizedBox(height: 16),
                    _Line(
                      animation: _desc,
                      child: Text(
                        tr('{0} из {1}', [_index + 1, widget.achievements.length]),
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.muted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 22,
          right: 22,
          bottom: 20,
          child: _Line(
            animation: _cta,
            child: SizedBox(
              height: 54,
              child: FilledButton(
                key: const ValueKey('achievement-celebration-next'),
                // The reward is never withheld: the button only has to be
                // reachable once it is on screen.
                onPressed: t < 0.84 ? null : _next,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: ink,
                  disabledBackgroundColor: AppColors.primary,
                  disabledForegroundColor: ink,
                  elevation: 6,
                  shadowColor: AppColors.primary.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(27),
                    side: const BorderSide(color: Color(0xC0C5B1FF)),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _hasMore ? tr('Следующее') : tr('Отлично!'),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 18, color: ink),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// What the player is told while the geode is still shut. Counting down,
  /// rather than naming the gesture twice, and phrased so it needs no plural
  /// forms in any of the app's languages.
  String _hintFor(int taps) => taps == 0
      ? tr('Нажмите, чтобы открыть')
      : tr('Осталось нажатий: {0}', [_kTapsToBreak - taps]);
}

/// The white flash at the instant the glass gives way, as an alpha: it snaps up
/// and falls away, so the burst is felt in the eyes as well as seen.
double _flashAt(double t) {
  const span = 0.18;
  if (t <= 0 || t >= span) return 0;
  final p = t / span;
  return p < 0.32 ? 0.72 * (p / 0.32) : 0.72 * (1 - (p - 0.32) / 0.68);
}

/// One line of the entrance: it rises a little and fades in.
class _Line extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _Line({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 14 * (1 - animation.value)), child: child),
      ),
      child: child,
    );
  }
}

/// The badge itself, framed: the halo ring and the light behind it breathe
/// while the screen is open, and the badge sits bright in the middle -- the
/// same artwork that was dimmed inside the geode a moment ago.
class _Crest extends StatelessWidget {
  final UserAchievement achievement;
  final Color color;
  final double size;
  final double breath;

  const _Crest({required this.achievement, required this.color, required this.size, required this.breath});

  @override
  Widget build(BuildContext context) {
    final badge = size * 0.82;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size * 1.6,
          height: size * 1.6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.42 + 0.18 * breath),
                color.withValues(alpha: 0.16 + 0.08 * breath),
                color.withValues(alpha: 0.0),
              ],
              stops: const [0, 0.35, 1],
            ),
          ),
        ),
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.52), width: 1.5),
          ),
        ),
        Container(
          width: badge,
          height: badge,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.14),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
          ),
          child: AchievementIcon(achievement: achievement, dimmed: false, size: badge - 12),
        ),
      ],
    );
  }
}

/// The violet light the geode sits in, the vignette that keeps the eye on it,
/// and -- in the dark theme only -- a little star dust.
class _Backdrop extends StatelessWidget {
  final Offset center;
  final bool dark;
  final bool calm;

  const _Backdrop({required this.center, required this.dark, required this.calm});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BackdropPainter(center: center, dark: dark, calm: calm));
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({required this.center, required this.dark, required this.calm});

  final Offset center;
  final bool dark;
  final bool calm;

  @override
  void paint(Canvas canvas, Size size) {
    final violet = const Color(0xFF8B5CFF);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            violet.withValues(alpha: dark ? 0.55 : 0.30),
            violet.withValues(alpha: dark ? 0.22 : 0.12),
            violet.withValues(alpha: 0.0),
          ],
          stops: const [0, 0.4, 0.62],
        ).createShader(Rect.fromCircle(center: center, radius: size.width * 0.95)),
    );

    // The vignette: a radial from the middle outward, so the corners of the
    // screen fall away and the reward is the only bright thing left. Wide
    // enough that its own edge never shows as a ring around the badge.
    final corner = Offset(size.width, size.height).distance;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            (dark ? const Color(0xFF02030A) : const Color(0xFFCFC8E8)).withValues(alpha: dark ? 0.62 : 0.30),
          ],
          stops: const [0.55, 1],
        ).createShader(Rect.fromCircle(center: center, radius: corner * 0.78)),
    );

    if (dark && !calm) {
      final dust = Paint()..color = Colors.white.withValues(alpha: 0.5);
      const spots = [
        Offset(0.22, 0.22),
        Offset(0.78, 0.15),
        Offset(0.45, 0.78),
        Offset(0.88, 0.55),
        Offset(0.12, 0.72),
        Offset(0.65, 0.88),
      ];
      for (var i = 0; i < spots.length; i++) {
        canvas.drawCircle(
          Offset(spots[i].dx * size.width, spots[i].dy * size.height),
          i % 3 == 0 ? 0.9 : 0.6,
          dust,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.center != center || old.dark != dark || old.calm != calm;
}

/// The geode: the light inside it, the four glass panels, and the cracks the
/// player's taps have opened up in them.
class _GeodePainter extends CustomPainter {
  _GeodePainter({
    required this.taps,
    required this.crackT,
    required this.shakeT,
    required this.pulse,
    required this.burst,
    required this.color,
    required this.extent,
  });

  /// How many taps the glass has taken: cracks up to `taps - 1` are complete,
  /// the one at exactly `taps` is still drawing itself in.
  final int taps;
  final double crackT;
  final double shakeT;
  final double pulse;
  final double burst;
  final Color color;

  /// How wide the flower is on screen; the 200-unit space maps onto it.
  final double extent;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = extent / _kGeode;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-_kGeodeCenter.dx, -_kGeodeCenter.dy);

    // The flinch: the GLASS shudders under the finger, never the whole screen
    // -- that is saved for the moment it actually breaks.
    if (shakeT > 0 && shakeT < 1) {
      final damp = 1 - shakeT;
      canvas.translate(
        math.sin(shakeT * math.pi * 4) * 2 * damp,
        math.cos(shakeT * math.pi * 4) * 2 * damp,
      );
      canvas.translate(_kGeodeCenter.dx, _kGeodeCenter.dy);
      canvas.rotate(math.sin(shakeT * math.pi * 2) * 0.02 * damp);
      canvas.translate(-_kGeodeCenter.dx, -_kGeodeCenter.dy);
    }

    // Everything the geode is made of leaves with the burst; the pieces that
    // keep flying live in the burst layer instead.
    final fade = 1 - (burst / 0.25).clamp(0.0, 1.0);

    // The light the whole thing sits in. It brightens with every tap -- this
    // is what shows through the seams between the panels, since the heart
    // itself stays hidden until the glass actually comes apart.
    final halo = (0.42 + 0.07 * taps) * fade;
    canvas.drawCircle(
      _kGeodeCenter,
      98,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: halo), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: _kGeodeCenter, radius: 98)),
    );

    // The heart: it brightens with every tap and breathes the whole time.
    final beat = 0.96 + 0.10 * pulse;
    final core = (0.55 + 0.15 * taps) * fade;
    canvas.drawCircle(
      _kGeodeCenter,
      42 * beat,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: core),
            const Color(0xFFF0E4FF).withValues(alpha: core * 0.9),
            const Color(0xFFB69AFF).withValues(alpha: core * 0.55),
            const Color(0xFF8B5CFF).withValues(alpha: 0),
          ],
          stops: const [0, 0.25, 0.6, 1],
        ).createShader(Rect.fromCircle(center: _kGeodeCenter, radius: 42 * beat)),
    );
    canvas.drawCircle(
      _kGeodeCenter,
      20 * beat,
      Paint()..color = Colors.white.withValues(alpha: 0.95 * fade),
    );

    final glass = 1 - (burst / 0.22).clamp(0.0, 1.0);
    if (glass <= 0.01) {
      canvas.restore();
      return;
    }
    final fly = Curves.easeOutCubic.transform((burst / 0.5).clamp(0.0, 1.0));
    for (final panel in _panels) {
      final away = (panel.center - _kGeodeCenter) / 32;
      canvas.save();
      canvas.translate(away.dx * _kPanelFlight * fly, away.dy * _kPanelFlight * fly);
      _paintPanel(canvas, panel, glass);
      canvas.restore();
    }

    // The cracks go on after EVERY panel, not with the panel they belong to:
    // the panels overlap, and a crack drawn with its own body would disappear
    // under the neighbour on top of it -- exactly the feedback the tap is
    // supposed to give.
    for (final panel in _panels) {
      final away = (panel.center - _kGeodeCenter) / 32;
      canvas.save();
      canvas.translate(away.dx * _kPanelFlight * fly, away.dy * _kPanelFlight * fly);
      _paintCracks(canvas, panel, glass);
      canvas.restore();
    }

    canvas.restore();
  }

  void _paintPanel(Canvas canvas, _Panel panel, double alpha) {
    final c = panel.center;
    final rect = Rect.fromCircle(center: c, radius: _kPanelRadius);

    // The stone: a cold glass, top-lit, so it reads as a body and not a disc.
    canvas.drawCircle(
      c,
      _kPanelRadius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _kStoneTop.withValues(alpha: alpha),
            _kStoneMid.withValues(alpha: alpha),
            _kStoneDeep.withValues(alpha: alpha),
            _kStoneDark.withValues(alpha: alpha),
          ],
          stops: const [0, 0.35, 0.75, 1],
        ).createShader(rect),
    );

    // Its violet rim -- the light inside trying to get out.
    canvas.drawCircle(
      c,
      _kPanelRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.25 * alpha)],
          stops: const [0.7, 1],
        ).createShader(rect),
    );

    // A soft highlight along the top edge, so the glass reads as glass.
    final gloss = Rect.fromCenter(center: Offset(c.dx, c.dy - 30), width: 40, height: 10);
    canvas.drawOval(
      gloss,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.30 * alpha), Colors.white.withValues(alpha: 0)],
        ).createShader(gloss),
    );

    canvas.drawCircle(
      c,
      _kPanelRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _kStoneEdge.withValues(alpha: alpha),
    );
  }

  /// The cracks the player's taps have opened in one panel: never crossing the
  /// edge of their own panel. The glowing edge goes down FIRST and the dark cut
  /// on top of it, which is what makes them read as breaks in the glass rather
  /// than as ridges on it.
  void _paintCracks(Canvas canvas, _Panel panel, double alpha) {
    final rect = Rect.fromCircle(center: panel.center, radius: _kPanelRadius);
    final rim = Color.lerp(color, Colors.white, 0.45)!;
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    for (final crack in panel.cracks) {
      final grow = crack.level <= taps - 1 ? 1.0 : (crack.level == taps ? crackT : 0.0);
      if (grow <= 0) continue;
      final path = _crackUpTo(crack.points, grow);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = crack.edge
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = rim.withValues(alpha: 0.75 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = crack.base
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = _kCrackLine.withValues(alpha: 0.95 * alpha),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GeodePainter old) =>
      old.taps != taps ||
      old.crackT != crackT ||
      old.shakeT != shakeT ||
      old.pulse != pulse ||
      old.burst != burst ||
      old.color != color ||
      old.extent != extent;
}

/// The burst: the shockwave, then the sparks and the pieces of glass, all of
/// them positioned around the point the geode just occupied.
class _BurstFxPainter extends CustomPainter {
  _BurstFxPainter({
    required this.sparks,
    required this.shards,
    required this.center,
    required this.unit,
    required this.t,
    required this.color,
    required this.calm,
  });

  final List<_Spark> sparks;
  final List<_Shard> shards;
  final Offset center;
  final double unit;
  final double t;
  final Color color;
  final bool calm;

  @override
  void paint(Canvas canvas, Size size) {
    if (calm || t <= 0 || t >= 1) return;

    // The shockwave: one thin ring running out of the break.
    final wave = (t / 0.32).clamp(0.0, 1.0);
    if (wave < 1) {
      canvas.drawCircle(
        center,
        unit * 30 * (0.18 + 2.42 * wave),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - 0.4 * wave)
          ..color = const Color(0xFFC6A4FF).withValues(alpha: 0.85 * (1 - wave)),
      );
    }

    for (final spark in sparks) {
      final p = (t - spark.delay) / spark.span;
      if (p <= 0 || p >= 1) continue;
      final away = Curves.easeOutCubic.transform(p);
      final at = center + spark.dir * (spark.dist * unit * away);
      final radius = spark.size * unit * (1 - 0.8 * p) / 2;
      final alpha = 1 - p;
      // A soft halo plus a solid core -- cheaper than a blurred draw, and at
      // this size impossible to tell apart from one.
      canvas.drawCircle(at, radius * 2.4, Paint()..color = spark.color.withValues(alpha: alpha * 0.22));
      if (spark.round) {
        canvas.drawCircle(at, radius, Paint()..color = spark.color.withValues(alpha: alpha));
      } else {
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(spark.spin * p * math.pi / 180);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: radius * 1.6, height: radius * 2.4),
            const Radius.circular(0.8),
          ),
          Paint()..color = spark.color.withValues(alpha: alpha),
        );
        canvas.restore();
      }
    }

    for (final shard in shards) {
      final p = (t - shard.delay) / shard.span;
      if (p <= 0 || p >= 1) continue;
      final away = Curves.easeOutCubic.transform(p);
      final from = center + (shard.origin - _kGeodeCenter) * unit;
      final at = from + shard.dir * (shard.dist * unit * away);
      final side = shard.size * unit * (1 - 0.6 * p);
      final alpha = 1 - p;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(shard.spin * p * math.pi / 180);
      final path = _shardPath(_shardShapes[shard.shape], side, side * 0.85);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _kStoneTop.withValues(alpha: alpha),
              _kStoneMid.withValues(alpha: alpha),
              _kStoneDark.withValues(alpha: alpha),
            ],
          ).createShader(Rect.fromCenter(center: Offset.zero, width: side, height: side)),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = _kCrackLine.withValues(alpha: alpha),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstFxPainter old) =>
      old.t != t || old.center != center || old.unit != unit || old.calm != calm || old.color != color;
}

/// The gold rain that starts a beat after the badge lands.
class _RainPainter extends CustomPainter {
  _RainPainter({required this.pieces, required this.t, required this.dark, required this.calm});

  final List<_ConfettiPiece> pieces;
  final double t;
  final bool dark;
  final bool calm;

  @override
  void paint(Canvas canvas, Size size) {
    if (calm || t <= 0) return;
    for (final piece in pieces) {
      final p = (t - piece.delay) / piece.span;
      if (p <= 0 || p >= 1) continue;
      final x = piece.x * size.width;
      final y = -20 + p * (size.height + 60);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(piece.spin * p * math.pi / 180);
      final alpha = p > 0.85 ? (1 - p) / 0.15 : 1.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: piece.size * (dark ? 1.4 : 1), height: piece.size * 1.6 * (dark ? 1.4 : 1)),
          const Radius.circular(2),
        ),
        Paint()..color = piece.color.withValues(alpha: alpha),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_RainPainter old) => old.t != t || old.calm != calm || old.dark != dark;
}

/// The run of a crack up to `t` of its whole length: the cut travels through
/// the glass on each tap instead of simply fading in.
Path _crackUpTo(List<Offset> points, double t) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  final segments = points.length - 1;
  if (segments <= 0) return path;
  final total = t * segments;
  for (var i = 0; i < segments; i++) {
    final local = (total - i).clamp(0.0, 1.0);
    if (local <= 0) break;
    final end = Offset.lerp(points[i], points[i + 1], local)!;
    path.lineTo(end.dx, end.dy);
  }
  return path;
}

/// One shard's outline, built from its unit shape and scaled.
Path _shardPath(List<Offset> shape, double width, double height) {
  final path = Path();
  for (var i = 0; i < shape.length; i++) {
    final x = (shape[i].dx - 0.5) * width;
    final y = (shape[i].dy - 0.5) * height;
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  return path..close();
}
